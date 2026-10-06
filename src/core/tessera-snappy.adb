with Interfaces; use Interfaces;

with Sml.Machines;

with Tessera.Thrift; use Tessera.Thrift;

package body Tessera.Snappy
  with SPARK_Mode
is

   procedure Declared_Length
     (Input : Bytes; Length : out Buffer_Count; Ok : out Boolean)
   is
      C : Cursor;
      U : Unsigned_64;
   begin
      Length := 0;
      Read_Varint (Input, C, U);
      Ok := C.Ok and then U <= Max_Buffer;
      if Ok then
         Length := Buffer_Count (U);
      end if;
   end Declared_Length;

   ---------------------------------------------------------------------
   --  An element's tag, and the bytes after it
   ---------------------------------------------------------------------

   --  The low two bits of a tag: what the element is.
   Literal_Tag     : constant := 0;
   Copy_1_Tag      : constant := 1;
   Copy_2_Tag      : constant := 2;
   Element_Kinds   : constant := 4;
   --  A literal's length minus one, at or past this, follows the tag in
   --  (value - 59) bytes.
   Long_Literal    : constant := 60;
   Long_Bias       : constant := 59;
   --  A one-byte-offset copy: length 4 + three bits, offset eleven bits.
   Short_Copy_Base : constant := 4;
   Three_Bits      : constant := 8;
   High_Offset     : constant := 32;
   Byte_Range      : constant := 256;

   type Event_Kind is (E_Literal, E_Copy, E_End, E_Bad, E_Moved);

   --  An element as its tag states it: a literal of Length bytes, or a
   --  copy of Length bytes from Offset bytes back.
   type Event is record
      Kind   : Event_Kind := E_Bad;
      Length : Buffer_Count := 0;
      Offset : Buffer_Count := 0;
   end record;

   --  Reads Count (1 .. 4) little-endian bytes.
   procedure Read_LE
     (Input : Bytes;
      C     : in out Cursor;
      Count : Positive;
      Value : out Unsigned_64)
   with Pre => Count <= 4, Post => Sound (C, Input);

   procedure Read_LE
     (Input : Bytes;
      C     : in out Cursor;
      Count : Positive;
      Value : out Unsigned_64)
   is
      B : Byte;
   begin
      Value := 0;
      for K in 0 .. Count - 1 loop
         Read_Byte (Input, C, B);
         Value := Value or Shift_Left (Unsigned_64 (B), 8 * K);
         pragma Loop_Invariant (Sound (C, Input));
      end loop;
   end Read_LE;

   --  A value read from the file as a length or an offset: the element
   --  is Bad when it is past any buffer.
   function Counted
     (Kind : Event_Kind; Length, Offset : Unsigned_64) return Event
   is (if Length <= Max_Buffer and then Offset <= Max_Buffer
       then (Kind, Buffer_Count (Length), Buffer_Count (Offset))
       else (Kind => E_Bad, others => <>));

   procedure Read_Literal
     (Input : Bytes; C : in out Cursor; Tag : Byte; Evt : out Event)
   with Pre => Sound (C, Input), Post => Sound (C, Input);

   procedure Read_Literal
     (Input : Bytes; C : in out Cursor; Tag : Byte; Evt : out Event)
   is
      Short : constant Unsigned_64 := Unsigned_64 (Tag / Element_Kinds);
      Long  : Unsigned_64;
   begin
      if Short < Long_Literal then
         Evt := Counted (E_Literal, Short + 1, 0);
      else
         Read_LE (Input, C, Natural (Short) - Long_Bias, Long);
         Evt := Counted (E_Literal, Long + 1, 0);
      end if;
   end Read_Literal;

   procedure Read_Copy
     (Input : Bytes; C : in out Cursor; Tag : Byte; Evt : out Event)
   with Pre => Tag mod Element_Kinds /= Literal_Tag, Post => Sound (C, Input);

   procedure Read_Copy
     (Input : Bytes; C : in out Cursor; Tag : Byte; Evt : out Event)
   is
      Low    : Unsigned_64;
      Length : constant Unsigned_64 := Unsigned_64 (Tag / Element_Kinds) + 1;
   begin
      case Tag mod Element_Kinds is
         when Copy_1_Tag =>
            Read_LE (Input, C, 1, Low);
            Evt :=
              Counted
                (E_Copy,
                 Short_Copy_Base
                 + Unsigned_64 (Tag / Element_Kinds mod Three_Bits),
                 Unsigned_64 (Tag / High_Offset) * Byte_Range + Low);

         when Copy_2_Tag =>
            Read_LE (Input, C, 2, Low);
            Evt := Counted (E_Copy, Length, Low);

         when others     =>
            Read_LE (Input, C, 4, Low);
            Evt := Counted (E_Copy, Length, Low);
      end case;
   end Read_Copy;

   --  The next element: its tag and the bytes that complete it; End when
   --  the input is spent, Bad when it is cut short.
   procedure Read_Element (Input : Bytes; C : in out Cursor; Evt : out Event)
   with Pre => Sound (C, Input), Post => Sound (C, Input);

   procedure Read_Element (Input : Bytes; C : in out Cursor; Evt : out Event)
   is
      Tag : Byte;
   begin
      if C.Ok and then C.Pos = Input'Length then
         Evt := (Kind => E_End, others => <>);
         return;
      end if;
      Read_Byte (Input, C, Tag);
      if Tag mod Element_Kinds = Literal_Tag then
         Read_Literal (Input, C, Tag, Evt);
      else
         Read_Copy (Input, C, Tag, Evt);
      end if;
      if not C.Ok then
         Evt := (Kind => E_Bad, others => <>);
      end if;
   end Read_Element;

   ---------------------------------------------------------------------
   --  The element machine
   ---------------------------------------------------------------------

   --  Reading a tag; a literal or a copy asked of the driver; done; or
   --  corrupt.
   type State is (Tag, Literal, Copy, Done, Corrupt);

   type Guard_Kind is (Always, Literal_Fits, Copy_Fits, All_Written);

   type Action_Kind is (Nothing, Want_Literal, Want_Copy);

   type Command is (None, Move_Literal, Move_Copy);

   --  What the machine knows: the declared length, how much is written,
   --  how many input bytes are left after the element's tag, and the
   --  move it asks of the driver.
   type Context is record
      Declared : Buffer_Count := 0;
      Written  : Buffer_Count := 0;
      In_Left  : Buffer_Count := 0;
      Pending  : Command := None;
      Length   : Buffer_Count := 0;
      Offset   : Buffer_Count := 0;
   end record;

   function Room (Ctx : Context; Length : Buffer_Count) return Boolean
   is (Ctx.Written <= Ctx.Declared
       and then Length <= Ctx.Declared - Ctx.Written);

   --  A literal fits when its bytes are in the input and room is left.
   function Fits_Literal (Ctx : Context; Length : Buffer_Count) return Boolean
   is (Length <= Ctx.In_Left and then Room (Ctx, Length));

   --  A copy fits when it reaches back no further than the output's
   --  start, and room is left.
   function Fits_Copy
     (Ctx : Context; Length, Offset : Buffer_Count) return Boolean
   is (Offset in 1 .. Ctx.Written and then Room (Ctx, Length));

   function Kind_Of (E : Event) return Event_Kind
   is (E.Kind);

   function Evaluate
     (G : Guard_Kind; Ctx : Context; Evt : Event) return Boolean
   is (case G is
         when Always       => True,
         when Literal_Fits => Fits_Literal (Ctx, Evt.Length),
         when Copy_Fits    => Fits_Copy (Ctx, Evt.Length, Evt.Offset),
         when All_Written  => Ctx.Written = Ctx.Declared);

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event);

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event) is
   begin
      Ctx.Pending :=
        (case A is
           when Nothing      => None,
           when Want_Literal => Move_Literal,
           when Want_Copy    => Move_Copy);
      Ctx.Length := Evt.Length;
      Ctx.Offset := Evt.Offset;
   end Execute;

   package Machines is new
     Sml.Machines
       (State       => State,
        Event_Kind  => Event_Kind,
        Event       => Event,
        Context     => Context,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Action_Kind,
        Kind_Of     => Kind_Of,
        Evaluate    => Evaluate,
        Execute     => Execute);
   use Machines;

   --!format off
   Table : constant Transition_Table :=
     [(Tag,     E_Literal, Literal_Fits, Want_Literal, Literal),
      (Tag,     E_Literal, Always,       Nothing,      Corrupt),
      (Tag,     E_Copy,    Copy_Fits,    Want_Copy,    Copy),
      (Tag,     E_Copy,    Always,       Nothing,      Corrupt),
      (Tag,     E_End,     All_Written,  Nothing,      Done),
      (Tag,     E_End,     Always,       Nothing,      Corrupt),
      (Tag,     E_Bad,     Always,       Nothing,      Corrupt),
      (Literal, E_Moved,   Always,       Nothing,      Tag),
      (Copy,    E_Moved,   Always,       Nothing,      Tag)];
   --!format on

   ---------------------------------------------------------------------
   --  The moves the driver makes
   ---------------------------------------------------------------------

   --  The literal's Length bytes, from the input at C into the output
   --  after its first Written.
   procedure Move_Literal_Bytes
     (Input   : Bytes;
      C       : in out Cursor;
      Output  : in out Bytes;
      Length  : Buffer_Count;
      Written : in out Buffer_Count)
   with
     Pre  =>
       Within (C, Input)
       and then Length <= Left (C, Input)
       and then Written <= Output'Length
       and then Length <= Output'Length - Written,
     Post => Within (C, Input) and then Written <= Output'Length;

   procedure Move_Literal_Bytes
     (Input   : Bytes;
      C       : in out Cursor;
      Output  : in out Bytes;
      Length  : Buffer_Count;
      Written : in out Buffer_Count) is
   begin
      if Length > 0 then
         Output
           (Output'First + Written .. Output'First + Written + Length - 1) :=
           Input (Input'First + C.Pos .. Input'First + C.Pos + Length - 1);
      end if;
      C.Pos := C.Pos + Length;
      Written := Written + Length;
   end Move_Literal_Bytes;

   --  The copy's Length bytes from Offset back, one at a time, since it
   --  may overlap itself.
   procedure Move_Copy_Bytes
     (Output  : in out Bytes;
      Length  : Buffer_Count;
      Offset  : Buffer_Count;
      Written : in out Buffer_Count)
   with
     Pre  =>
       Offset in 1 .. Written
       and then Written <= Output'Length
       and then Length <= Output'Length - Written,
     Post => Written <= Output'Length;

   procedure Move_Copy_Bytes
     (Output  : in out Bytes;
      Length  : Buffer_Count;
      Offset  : Buffer_Count;
      Written : in out Buffer_Count) is
   begin
      for K in Written .. Written + Length - 1 loop
         Output (Output'First + K) := Output (Output'First + K - Offset);
      end loop;
      Written := Written + Length;
   end Move_Copy_Bytes;

   --  The move the machine asked for in Request, its bounds checked again
   --  against the buffers themselves; the cursor fails when they do not
   --  hold.
   procedure Move
     (Input   : Bytes;
      C       : in out Cursor;
      Output  : in out Bytes;
      Request : Context;
      Written : in out Buffer_Count)
   with
     Pre  => Sound (C, Input) and then Written <= Output'Length,
     Post => Sound (C, Input) and then Written <= Output'Length;

   procedure Move
     (Input   : Bytes;
      C       : in out Cursor;
      Output  : in out Bytes;
      Request : Context;
      Written : in out Buffer_Count)
   is
      Length : constant Buffer_Count := Request.Length;
   begin
      if not C.Ok or else Length > Output'Length - Written then
         C.Ok := False;
      elsif Request.Pending = Move_Literal and then Length <= Left (C, Input)
      then
         Move_Literal_Bytes (Input, C, Output, Length, Written);
      elsif Request.Pending = Move_Copy and then Request.Offset in 1 .. Written
      then
         Move_Copy_Bytes (Output, Length, Request.Offset, Written);
      else
         C.Ok := False;
      end if;
   end Move;

   --  The event the next element gives, with the machine told how many
   --  input bytes are left after it.
   procedure Next_Event
     (Input : Bytes; C : in out Cursor; Ctx : in out Context; Evt : out Event)
   with Pre => Sound (C, Input), Post => Sound (C, Input);

   procedure Next_Event
     (Input : Bytes; C : in out Cursor; Ctx : in out Context; Evt : out Event)
   is
   begin
      Read_Element (Input, C, Evt);
      Ctx.In_Left := (if C.Ok then Left (C, Input) else 0);
   end Next_Event;

   --  Every element reads at least its tag, and takes two steps.
   function Step_Bound (Input : Bytes) return Positive
   is (2 * Input'Length + 2);

   procedure Decompress
     (Input  : Bytes;
      Output : in out Bytes;
      Last   : out Buffer_Count;
      Result : out Outcome)
   is
      C       : Cursor;
      U       : Unsigned_64;
      M       : Machine := Make (Table, Initial => Tag);
      Ctx     : Context;
      Evt     : Event;
      Written : Buffer_Count := 0;
      Handled : Boolean := True;
   begin
      Read_Varint (Input, C, U);
      if not C.Ok or else U > Unsigned_64 (Output'Length) then
         Last := 0;
         Result := Refused (Corrupt_Page);
         return;
      end if;
      Ctx.Declared := Buffer_Count (U);
      for Step in 1 .. Step_Bound (Input) loop
         exit when State_Of (M) in Done | Corrupt or else not Handled;
         if State_Of (M) = Tag then
            Next_Event (Input, C, Ctx, Evt);
         else
            Move (Input, C, Output, Ctx, Written);
            Evt := (Kind => (if C.Ok then E_Moved else E_Bad), others => <>);
         end if;
         Ctx.Written := Written;
         Process_Event (M, Ctx, Evt, Handled);
         pragma
           Loop_Invariant (Sound (C, Input) and then Written <= Output'Length);
      end loop;
      Last := Written;
      Result :=
        (if State_Of (M) = Done then Tessera.Done else Refused (Corrupt_Page));
   end Decompress;

end Tessera.Snappy;
