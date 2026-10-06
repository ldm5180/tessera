package body Tessera.Thrift
  with SPARK_Mode
is

   --  A varint of 64 bits takes at most ten bytes; the tenth holds one.
   Max_Varint_Bytes : constant := 10;

   Low_Seven   : constant Byte := 16#7F#;
   More_Bit    : constant Byte := 16#80#;
   Nibble      : constant := 16;
   Long_Form   : constant := 15;
   Double_Size : constant := 8;

   --  The codes of the wire types, 1 .. 12.
   subtype Kind_Code is Byte range 1 .. 12;

   function To_Kind (Code : Kind_Code) return Wire_Kind
   is (Wire_Kind'Val (Code - 1));

   procedure Fail (C : in out Cursor)
   with Post => not C.Ok and then C.Pos = C.Pos'Old;

   procedure Fail (C : in out Cursor) is
   begin
      C.Ok := False;
   end Fail;

   procedure Read_Byte (Input : Bytes; C : in out Cursor; Value : out Byte) is
   begin
      Value := 0;
      if C.Ok and then C.Pos < Input'Length then
         Value := Byte_At (Input, C.Pos);
         C.Pos := C.Pos + 1;
      else
         Fail (C);
      end if;
   end Read_Byte;

   --  Steps over Count bytes, or fails when fewer are left.
   procedure Step_Over (Input : Bytes; C : in out Cursor; Count : Buffer_Count)
   with
     Post =>
       Sound (C, Input)
       and then (if C.Ok then C'Old.Ok and then C.Pos = C'Old.Pos + Count);

   procedure Step_Over (Input : Bytes; C : in out Cursor; Count : Buffer_Count)
   is
   begin
      if C.Ok and then Within (C, Input) and then Count <= Left (C, Input) then
         C.Pos := C.Pos + Count;
      else
         Fail (C);
      end if;
   end Step_Over;

   --  The seven payload bits of the K-th byte of a varint, in place.
   function Payload (B : Byte; K : Positive) return Unsigned_64
   is (Shift_Left (Unsigned_64 (B and Low_Seven), 7 * (K - 1)))
   with Pre => K <= Max_Varint_Bytes;

   procedure Read_Varint
     (Input : Bytes; C : in out Cursor; Value : out Unsigned_64)
   is
      Start : constant Cursor := C;
      B     : Byte;
   begin
      Value := 0;
      for K in 1 .. Max_Varint_Bytes loop
         Read_Byte (Input, C, B);
         if C.Ok and then K = Max_Varint_Bytes and then B > 1 then
            Fail (C);
         end if;
         exit when not C.Ok;
         Value := Value or Payload (B, K);
         exit when B < More_Bit;
         if K = Max_Varint_Bytes then
            Fail (C);
         end if;
         pragma Loop_Invariant (Advanced (Start, C, Input));
      end loop;
      if not C.Ok then
         Value := 0;
      end if;
   end Read_Varint;

   function Unzigzag (U : Unsigned_64) return Integer_64
   is (if U mod 2 = 0 then Integer_64 (U / 2) else -Integer_64 (U / 2) - 1);

   procedure Read_Zigzag
     (Input : Bytes; C : in out Cursor; Value : out Integer_64)
   is
      U : Unsigned_64;
   begin
      Read_Varint (Input, C, U);
      Value := Unzigzag (U);
   end Read_Zigzag;

   procedure Read_I32
     (Input : Bytes; C : in out Cursor; Value : out Integer_32)
   is
      Wide : Integer_64;
   begin
      Value := 0;
      Read_Zigzag (Input, C, Wide);
      if Wide in Integer_64 (Integer_32'First) .. Integer_64 (Integer_32'Last)
      then
         Value := Integer_32 (Wide);
      else
         Fail (C);
      end if;
   end Read_I32;

   --  The id of a field whose header carries no delta: a zigzag i16.
   procedure Read_Long_Id
     (Input : Bytes; C : in out Cursor; Id : out Integer_16)
   with Post => Advanced (C'Old, C, Input);

   procedure Read_Long_Id
     (Input : Bytes; C : in out Cursor; Id : out Integer_16)
   is
      Wide : Integer_64;
   begin
      Id := 0;
      Read_Zigzag (Input, C, Wide);
      if Wide in Integer_64 (Integer_16'First) .. Integer_64 (Integer_16'Last)
      then
         Id := Integer_16 (Wide);
      else
         Fail (C);
      end if;
   end Read_Long_Id;

   --  The field id a short header's delta gives after Last_Id.
   procedure Add_Delta
     (C       : in out Cursor;
      Last_Id : Integer_16;
      Step    : Byte;
      Id      : out Integer_16)
   with Post => C.Pos = C.Pos'Old and then (if C.Ok then C.Ok'Old);

   procedure Add_Delta
     (C       : in out Cursor;
      Last_Id : Integer_16;
      Step    : Byte;
      Id      : out Integer_16) is
   begin
      Id := 0;
      if Last_Id <= Integer_16'Last - Integer_16 (Step) then
         Id := Last_Id + Integer_16 (Step);
      else
         Fail (C);
      end if;
   end Add_Delta;

   procedure Read_Field_Header
     (Input   : Bytes;
      C       : in out Cursor;
      Last_Id : in out Integer_16;
      Header  : out Field_Header)
   is
      B : Byte;
   begin
      Header := (others => <>);
      Read_Byte (Input, C, B);
      if not C.Ok or else B = 0 then
         return;
      elsif B mod Nibble not in Kind_Code then
         Fail (C);
         return;
      end if;
      Header := (Stop => False, Id => 0, Kind => To_Kind (B mod Nibble));
      if B / Nibble = 0 then
         Read_Long_Id (Input, C, Header.Id);
      else
         Add_Delta (C, Last_Id, B / Nibble, Header.Id);
      end if;
      if C.Ok then
         Last_Id := Header.Id;
      end if;
   end Read_Field_Header;

   --  A varint length that must fit within the bytes left after it.
   procedure Read_Length
     (Input : Bytes; C : in out Cursor; Length : out Buffer_Count)
   with
     Post =>
       Advanced (C'Old, C, Input)
       and then (if C.Ok then Length <= Left (C, Input));

   procedure Read_Length
     (Input : Bytes; C : in out Cursor; Length : out Buffer_Count)
   is
      U : Unsigned_64;
   begin
      Length := 0;
      Read_Varint (Input, C, U);
      if C.Ok and then U <= Unsigned_64 (Left (C, Input)) then
         Length := Buffer_Count (U);
      else
         Fail (C);
      end if;
   end Read_Length;

   procedure Read_Binary (Input : Bytes; C : in out Cursor; Value : out Span)
   is
      Start  : constant Cursor := C;
      Length : Buffer_Count;
   begin
      Value := (others => <>);
      Read_Length (Input, C, Length);
      if C.Ok then
         Value := (Start => C.Pos, Length => Length);
         Step_Over (Input, C, Length);
      end if;
      pragma Assert (Advanced (Start, C, Input));
   end Read_Binary;

   procedure Read_List_Header
     (Input : Bytes; C : in out Cursor; Header : out List_Header)
   is
      Start : constant Cursor := C;
      B     : Byte;
   begin
      Header := (others => <>);
      Read_Byte (Input, C, B);
      if C.Ok and then B mod Nibble not in Kind_Code then
         Fail (C);
      end if;
      if not C.Ok then
         return;
      end if;
      Header.Element := To_Kind (B mod Nibble);
      if B / Nibble = Long_Form then
         Read_Length (Input, C, Header.Count);
      elsif Buffer_Count (B / Nibble) <= Left (C, Input) then
         Header.Count := Buffer_Count (B / Nibble);
      else
         Fail (C);
      end if;
      pragma Assert (Advanced (Start, C, Input));
   end Read_List_Header;

   ---------------------------------------------------------------------
   --  Skip: a walk over one value of any shape, with the containers it
   --  is inside of on an explicit stack.
   ---------------------------------------------------------------------

   type Frame_Kind is (In_Struct, In_Items);

   --  One open container: a struct (and the id of its last field), or a
   --  list, set or map with Remaining items left.  A map's items
   --  alternate key and value, so Remaining counts both.
   type Frame is record
      Kind      : Frame_Kind := In_Struct;
      Last_Id   : Integer_16 := 0;
      Remaining : Buffer_Count := 0;
      Element   : Wire_Kind := Struct;
      Value     : Wire_Kind := Struct;
      Is_Map    : Boolean := False;
   end record;

   subtype Depth_Count is Natural range 0 .. Max_Depth;

   type Frame_Array is array (1 .. Max_Depth) of Frame;

   --  The walk: the open containers, and whether a value of Kind is due
   --  next (In_Item when it is an element, where a boolean takes a byte).
   type Walk is record
      Frames  : Frame_Array;
      Depth   : Depth_Count := 0;
      Pending : Boolean := True;
      Kind    : Wire_Kind := Struct;
      In_Item : Boolean := False;
   end record;

   procedure Push (C : in out Cursor; W : in out Walk; F : Frame)
   with Post => C.Pos = C.Pos'Old and then (if C.Ok then C.Ok'Old);

   procedure Push (C : in out Cursor; W : in out Walk; F : Frame) is
   begin
      if W.Depth < Max_Depth then
         W.Depth := W.Depth + 1;
         W.Frames (W.Depth) := F;
      else
         Fail (C);
      end if;
   end Push;

   --  The items of a list or set, as a frame; none to open when empty.
   procedure Open_List (Input : Bytes; C : in out Cursor; W : in out Walk)
   with Post => Sound (C, Input) and then (if C.Ok then C.Ok'Old);

   procedure Open_List (Input : Bytes; C : in out Cursor; W : in out Walk) is
      H : List_Header;
   begin
      Read_List_Header (Input, C, H);
      if C.Ok and then H.Count > 0 then
         Push
           (C,
            W,
            (Kind      => In_Items,
             Remaining => H.Count,
             Element   => H.Element,
             others    => <>));
      end if;
   end Open_List;

   --  A map's key and value types, one nibble each.
   procedure Read_Map_Kinds
     (Input : Bytes; C : in out Cursor; Key, Value : out Wire_Kind)
   with Post => Advanced (C'Old, C, Input);

   procedure Read_Map_Kinds
     (Input : Bytes; C : in out Cursor; Key, Value : out Wire_Kind)
   is
      B : Byte;
   begin
      Key := Struct;
      Value := Struct;
      Read_Byte (Input, C, B);
      if C.Ok
        and then B / Nibble in Kind_Code
        and then B mod Nibble in Kind_Code
      then
         Key := To_Kind (B / Nibble);
         Value := To_Kind (B mod Nibble);
      else
         Fail (C);
      end if;
   end Read_Map_Kinds;

   --  The entries of a map, as a frame; none to open when empty.  Every
   --  entry takes at least two bytes.
   procedure Open_Map (Input : Bytes; C : in out Cursor; W : in out Walk)
   with Post => Sound (C, Input) and then (if C.Ok then C.Ok'Old);

   procedure Open_Map (Input : Bytes; C : in out Cursor; W : in out Walk) is
      Size       : Buffer_Count;
      Key, Value : Wire_Kind;
   begin
      Read_Length (Input, C, Size);
      if not C.Ok or else Size = 0 then
         return;
      end if;
      Read_Map_Kinds (Input, C, Key, Value);
      if C.Ok and then Size <= Left (C, Input) / 2 then
         Push
           (C,
            W,
            (Kind      => In_Items,
             Remaining => 2 * Size,
             Element   => Key,
             Value     => Value,
             Is_Map    => True,
             others    => <>));
      else
         Fail (C);
      end if;
   end Open_Map;

   --  Steps over the due value, or opens the container it begins.
   procedure Skip_Due (Input : Bytes; C : in out Cursor; W : in out Walk)
   with
     Pre  => Sound (C, Input),
     Post => Sound (C, Input) and then (if C.Ok then C.Ok'Old);

   procedure Skip_Due (Input : Bytes; C : in out Cursor; W : in out Walk) is
      Ignored : Unsigned_64;
      Length  : Buffer_Count;
   begin
      case W.Kind is
         when Bool_True | Bool_False =>
            Step_Over (Input, C, (if W.In_Item then 1 else 0));

         when I8                     =>
            Step_Over (Input, C, 1);

         when I16 | I32 | I64        =>
            Read_Varint (Input, C, Ignored);

         when Double                 =>
            Step_Over (Input, C, Double_Size);

         when Binary                 =>
            Read_Length (Input, C, Length);
            Step_Over (Input, C, Length);

         when List | Set             =>
            Open_List (Input, C, W);

         when Map                    =>
            Open_Map (Input, C, W);

         when Struct                 =>
            Push (C, W, (Kind => In_Struct, others => <>));
      end case;
      W.Pending := False;
   end Skip_Due;

   --  The kind of the next item of an items frame: a map alternates key
   --  and value, a key when an even number of items is left.
   function Item_Kind (F : Frame) return Wire_Kind
   is (if F.Is_Map and then F.Remaining mod 2 = 1 then F.Value else F.Element);

   --  The next field of the innermost struct, or its end.
   procedure Next_Field (Input : Bytes; C : in out Cursor; W : in out Walk)
   with
     Pre  => W.Depth > 0,
     Post => Sound (C, Input) and then (if C.Ok then C.Ok'Old);

   procedure Next_Field (Input : Bytes; C : in out Cursor; W : in out Walk) is
      H : Field_Header;
   begin
      Read_Field_Header (Input, C, W.Frames (W.Depth).Last_Id, H);
      if not C.Ok then
         return;
      elsif H.Stop then
         W.Depth := W.Depth - 1;
      else
         W.Pending := True;
         W.Kind := H.Kind;
         W.In_Item := False;
      end if;
   end Next_Field;

   --  The next item of the innermost list, set or map, or its end.
   procedure Next_Item (W : in out Walk)
   with Pre => W.Depth > 0;

   procedure Next_Item (W : in out Walk) is
      Top : constant Depth_Count := W.Depth;
   begin
      if W.Frames (Top).Remaining = 0 then
         W.Depth := Top - 1;
      else
         W.Kind := Item_Kind (W.Frames (Top));
         W.Frames (Top).Remaining := W.Frames (Top).Remaining - 1;
         W.Pending := True;
         W.In_Item := True;
      end if;
   end Next_Item;

   --  The most steps a skip of Input can take: every step reads a byte,
   --  or is one of at most two that read none before one that does, or
   --  closes a container.
   function Step_Bound (Input : Bytes) return Positive
   is (3 * Input'Length + Max_Depth + 1);

   --  True when no value is due and no container is open.
   function Finished (W : Walk) return Boolean
   is (not W.Pending and then W.Depth = 0);

   procedure Skip (Input : Bytes; C : in out Cursor; Kind : Wire_Kind) is
      W : Walk := (Kind => Kind, others => <>);
   begin
      if not Within (C, Input) then
         Fail (C);
      end if;
      for Step in 1 .. Step_Bound (Input) loop
         exit when Finished (W) or else not C.Ok;
         if W.Pending then
            Skip_Due (Input, C, W);
         elsif W.Frames (W.Depth).Kind = In_Struct then
            Next_Field (Input, C, W);
         else
            Next_Item (W);
         end if;
         pragma
           Loop_Invariant
             (Sound (C, Input) and then (if C.Ok then C'Loop_Entry.Ok));
      end loop;
      if not Finished (W) then
         Fail (C);
      end if;
   end Skip;

end Tessera.Thrift;
