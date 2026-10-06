with Sml.Machines;
with Sml.Machines.Operators;

with Tessera.Snappy;
with Tessera.Thrift; use Tessera.Thrift;

package body Tessera.Columns
  with SPARK_Mode
is

   ---------------------------------------------------------------------
   --  The page sequence machine
   ---------------------------------------------------------------------

   type State is (Start, Have_Dictionary, In_Data, Done, Refused);

   type Event_Kind is
     (E_Dictionary_Page,
      E_Data_Page,
      E_Other_Page,
      E_Bad_Page,
      E_End,
      E_Decoded,
      E_Failed);

   --  An event, and the refusal it carries when it is one: why a page
   --  could not be read, or which page type is not read.
   type Event is record
      Kind    : Event_Kind := E_Bad_Page;
      Verdict : Outcome := Tessera.Done;
   end record;

   type Guard_Kind is (Always, All_Rows);

   type Action_Kind is (Nothing, Want_Dictionary, Want_Data, Keep, Short);

   --  What the driver does with the page in hand.
   type Command is (None, Decode_Dictionary, Decode_Data);

   --  What the machine knows: rows read and wanted, the request it makes,
   --  and the refusal it has met.
   type Context is record
      Filled  : Row_Count := 0;
      Rows    : Row_Count := 0;
      Pending : Command := None;
      Verdict : Outcome := Tessera.Done;
   end record;

   function Kind_Of (E : Event) return Event_Kind
   is (E.Kind);

   function Evaluate
     (G : Guard_Kind; Ctx : Context; Evt : Event) return Boolean
   is (case G is
         when Always   => True,
         when All_Rows => Evt.Kind = E_End and then Ctx.Filled = Ctx.Rows);

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event);

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event) is
   begin
      Ctx.Pending :=
        (case A is
           when Want_Dictionary => Decode_Dictionary,
           when Want_Data       => Decode_Data,
           when others          => None);
      if A = Keep then
         Ctx.Verdict := Evt.Verdict;
      elsif A = Short then
         Ctx.Verdict := Refused (Corrupt_Page);
      end if;
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

   package Op is new Machines.Operators (Always, Nothing);
   use Op;

   Dictionary_In : constant Ev := (Kind => E_Dictionary_Page);
   Data_Page_In  : constant Ev := (Kind => E_Data_Page);
   Other_Page_In : constant Ev := (Kind => E_Other_Page);
   Bad_Page_In   : constant Ev := (Kind => E_Bad_Page);
   End_Of_Chunk  : constant Ev := (Kind => E_End);
   Decoded       : constant Ev := (Kind => E_Decoded);
   Failed        : constant Ev := (Kind => E_Failed);

   --  A chunk is done when its bytes end with every row read: after its
   --  data pages, or with none at all when it has no rows.
   --!format off
   Table : constant Transition_Table :=
     [Start           + Dictionary_In / Want_Dictionary >= Have_Dictionary,
      Start           + Data_Page_In  / Want_Data       >= In_Data,
      Have_Dictionary + Data_Page_In  / Want_Data       >= In_Data,
      Have_Dictionary + Decoded                         >= Have_Dictionary,
      In_Data         + Data_Page_In  / Want_Data       >= In_Data,
      In_Data         + Decoded                         >= In_Data,
      In_Data         + End_Of_Chunk (All_Rows)         >= Done,
      Start           + End_Of_Chunk (All_Rows)         >= Done,
      Have_Dictionary + End_Of_Chunk (All_Rows)         >= Done,
      Start           + End_Of_Chunk  / Short           >= Refused,
      Have_Dictionary + End_Of_Chunk  / Short           >= Refused,
      In_Data         + End_Of_Chunk  / Short           >= Refused,
      Have_Dictionary + Dictionary_In / Short           >= Refused,
      In_Data         + Dictionary_In / Short           >= Refused,
      Start           + Other_Page_In / Keep            >= Refused,
      Have_Dictionary + Other_Page_In / Keep            >= Refused,
      In_Data         + Other_Page_In / Keep            >= Refused,
      Start           + Bad_Page_In   / Keep            >= Refused,
      Have_Dictionary + Bad_Page_In   / Keep            >= Refused,
      In_Data         + Bad_Page_In   / Keep            >= Refused,
      Have_Dictionary + Failed        / Keep            >= Refused,
      In_Data         + Failed        / Keep            >= Refused];
   --!format on

   ---------------------------------------------------------------------
   --  One page: its header, its bytes made plain
   ---------------------------------------------------------------------

   --  The page type codes of the pages not read, named in a refusal.
   function Page_Event (H : Pages.Header) return Event
   is (case H.Kind is
         when Dictionary_Page => (Kind => E_Dictionary_Page, others => <>),
         when Data_Page       => (Kind => E_Data_Page, others => <>),
         when others          =>
           (E_Other_Page,
            Refused_With
              (Unsupported_Page_Version, 0, Page_Kind'Pos (H.Kind))));

   --  A page read: how it is to be decoded, and the event it gives the
   --  machine.
   type Page_Read is record
      Plan : Page_Plan;
      Evt  : Event;
   end record;

   --  The body of a page, Expected bytes once plain, into Space.Page:
   --  decompressed when Snappy, copied when not.  Corrupt_Page when it
   --  does not come to Expected bytes, or they do not fit.
   procedure Expand
     (Page_Body : Bytes;
      Snappy    : Boolean;
      Expected  : Buffer_Count;
      Space     : in out Workspace;
      Result    : out Outcome);

   procedure Expand
     (Page_Body : Bytes;
      Snappy    : Boolean;
      Expected  : Buffer_Count;
      Space     : in out Workspace;
      Result    : out Outcome)
   is
      Last : Buffer_Count;
   begin
      if Expected > Space.Page_Size then
         Result := Refused (Corrupt_Page);
      elsif Snappy then
         Tessera.Snappy.Decompress
           (Page_Body, Space.Page (1 .. Expected), Last, Result);
         if Result.Ok and then Last /= Expected then
            Result := Refused (Corrupt_Page);
         end if;
      elsif Page_Body'Length = Expected then
         Space.Page (1 .. Expected) := Page_Body;
         Result := Tessera.Done;
      else
         Result := Refused (Corrupt_Page);
      end if;
   end Expand;

   --  The page at C: its header read, its body made plain in Space.Page,
   --  and C stepped past it.  Its event says which kind of page it was,
   --  or why it cannot be read.
   procedure Next_Page
     (Chunk : Bytes;
      C     : in out Cursor;
      Shape : Chunk_Shape;
      Space : in out Workspace;
      Page  : out Page_Read)
   with Pre => Sound (C, Chunk), Post => Sound (C, Chunk);

   procedure Next_Page
     (Chunk : Bytes;
      C     : in out Cursor;
      Shape : Chunk_Shape;
      Space : in out Workspace;
      Page  : out Page_Read)
   is
      Result : Outcome;
      H      : Pages.Header;
      From   : Buffer_Count;
   begin
      Read_Header (Chunk, C, H, Result);
      Page :=
        (Plan => (H => H, Width => Shape.Width, Optional => Shape.Optional),
         Evt  => (E_Bad_Page, Result));
      if not Result.Ok then
         return;
      end if;
      From := C.Pos;
      C.Pos := C.Pos + H.Compressed;
      if H.Kind not in Dictionary_Page | Data_Page then
         Page.Evt := Page_Event (H);
         return;
      end if;
      Expand
        (Chunk (Chunk'First + From .. Chunk'First + C.Pos - 1),
         Shape.Snappy,
         H.Uncompressed,
         Space,
         Result);
      Page.Evt := (if Result.Ok then Page_Event (H) else (E_Bad_Page, Result));
   end Next_Page;

   ---------------------------------------------------------------------
   --  The chunk driver
   ---------------------------------------------------------------------

   --  The pages of a chunk read into a column through Take_Dictionary
   --  and Take_Data, which decode one page of Plan from its plain bytes.
   generic
      type Column (<>) is limited private;
      with
        procedure Take_Dictionary
          (Page    : Bytes;
           Plan    : Page_Plan;
           Into    : in out Column;
           Scratch : in out Hybrid.Codes;
           Result  : out Outcome);
      with
        procedure Take_Data
          (Page    : Bytes;
           Plan    : Page_Plan;
           Into    : in out Column;
           Scratch : in out Hybrid.Codes;
           Result  : out Outcome);
      with function Filled (Into : Column) return Row_Count;
      with function Rows (Into : Column) return Row_Count;
   package Chunk_Reader is

      procedure Read_Chunk
        (Chunk  : Bytes;
         Shape  : Chunk_Shape;
         Space  : in out Workspace;
         Into   : in out Column;
         Result : out Outcome);

   end Chunk_Reader;

   package body Chunk_Reader is

      --  The page in Space.Page decoded as Request asks, and the event
      --  that says how it went.
      procedure Decode_Page
        (Page    : Page_Read;
         Request : Command;
         Space   : in out Workspace;
         Into    : in out Column;
         Evt     : out Event);

      procedure Decode_Page
        (Page    : Page_Read;
         Request : Command;
         Space   : in out Workspace;
         Into    : in out Column;
         Evt     : out Event)
      is
         Size   : constant Buffer_Count := Page.Plan.H.Uncompressed;
         Result : Outcome := Refused (Corrupt_Page);
      begin
         if Size > Space.Page_Size then
            null;
         elsif Request = Decode_Dictionary then
            Take_Dictionary
              (Space.Page (1 .. Size), Page.Plan, Into, Space.Scratch, Result);
         elsif Request = Decode_Data then
            Take_Data
              (Space.Page (1 .. Size), Page.Plan, Into, Space.Scratch, Result);
         end if;
         Evt :=
           (if Result.Ok then (E_Decoded, Result) else (E_Failed, Result));
      end Decode_Page;

      procedure Read_Chunk
        (Chunk  : Bytes;
         Shape  : Chunk_Shape;
         Space  : in out Workspace;
         Into   : in out Column;
         Result : out Outcome)
      is
         M       : Machine := Make (Table, Initial => Start);
         Ctx     : Context := (Rows => Rows (Into), others => <>);
         C       : Cursor;
         Page    : Page_Read;
         Evt     : Event;
         Handled : Boolean := True;
      begin
         for Step in 1 .. 2 * Chunk'Length + 2 loop
            exit when State_Of (M) in Done | Refused or else not Handled;
            if Ctx.Pending /= None then
               Decode_Page (Page, Ctx.Pending, Space, Into, Evt);
            elsif C.Ok and then C.Pos >= Chunk'Length then
               Evt := (Kind => E_End, others => <>);
            else
               Next_Page (Chunk, C, Shape, Space, Page);
               Evt := Page.Evt;
            end if;
            Ctx.Filled := Filled (Into);
            Process_Event (M, Ctx, Evt, Handled);
            pragma Loop_Invariant (Sound (C, Chunk));
         end loop;
         Result :=
           (if State_Of (M) = Done
            then Tessera.Done
            elsif not Ctx.Verdict.Ok
            then Ctx.Verdict
            else Refused (Corrupt_Page));
      end Read_Chunk;

   end Chunk_Reader;

   ---------------------------------------------------------------------
   --  The two kinds of column
   ---------------------------------------------------------------------

   --  A dictionary page of a fixed-width column; it needs no scratch.
   procedure Words_Dictionary
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome);

   procedure Words_Dictionary
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome)
   is
      pragma Unreferenced (Scratch);
   begin
      Dictionary_Words (Page, Plan, Into, Result);
   end Words_Dictionary;

   --  A data page of a fixed-width column, when Scratch has a code for
   --  each of its rows.
   procedure Words_Data
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome);

   procedure Words_Data
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome) is
   begin
      if Scratch'Length >= Into.Rows then
         Data_Words (Page, Plan, Into, Scratch, Result);
      else
         Result := Refused (Too_Large);
      end if;
   end Words_Data;

   --  A data page of a byte-array column, when Scratch has a code for
   --  each of its rows.
   procedure Text_Data
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome);

   procedure Text_Data
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Hybrid.Codes;
      Result  : out Outcome) is
   begin
      if Scratch'Length >= Into.Rows then
         Data_Text (Page, Plan, Into, Scratch, Result);
      else
         Result := Refused (Too_Large);
      end if;
   end Text_Data;

   function Words_Filled (Into : Word_Column) return Row_Count
   is (Into.Filled);

   function Words_Rows (Into : Word_Column) return Row_Count
   is (Into.Rows);

   function Text_Filled (Into : Text_Column) return Row_Count
   is (Into.Filled);

   function Text_Rows (Into : Text_Column) return Row_Count
   is (Into.Rows);

   package Word_Chunks is new
     Chunk_Reader
       (Column          => Word_Column,
        Take_Dictionary => Words_Dictionary,
        Take_Data       => Words_Data,
        Filled          => Words_Filled,
        Rows            => Words_Rows);

   package Text_Chunks is new
     Chunk_Reader
       (Column          => Text_Column,
        Take_Dictionary => Dictionary_Text,
        Take_Data       => Text_Data,
        Filled          => Text_Filled,
        Rows            => Text_Rows);

   procedure Read_Words
     (Chunk  : Bytes;
      Shape  : Chunk_Shape;
      Space  : in out Workspace;
      Into   : in out Word_Column;
      Result : out Outcome)
   renames Word_Chunks.Read_Chunk;

   procedure Read_Text
     (Chunk  : Bytes;
      Shape  : Chunk_Shape;
      Space  : in out Workspace;
      Into   : in out Text_Column;
      Result : out Outcome)
   renames Text_Chunks.Read_Chunk;

   ---------------------------------------------------------------------
   --  The typed columns
   ---------------------------------------------------------------------

   --  The bits of a 32-bit pattern.
   Low_32 : constant := 2**32 - 1;

   procedure To_Truths (From : Word_Column; Into : in out Truths) is
   begin
      Into.Valid := From.Valid;
      for R in 1 .. From.Rows loop
         Into.Value (R) := From.Value (R) /= 0;
      end loop;
   end To_Truths;

   procedure To_Ints_32 (From : Word_Column; Into : in out Ints_32) is
   begin
      Into.Valid := From.Valid;
      for R in 1 .. From.Rows loop
         Into.Value (R) := Signed_32 (From.Value (R));
      end loop;
   end To_Ints_32;

   procedure To_Ints_64 (From : Word_Column; Into : in out Ints_64) is
   begin
      Into.Valid := From.Valid;
      for R in 1 .. From.Rows loop
         Into.Value (R) := Signed_64 (From.Value (R));
      end loop;
   end To_Ints_64;

   procedure To_Bits_32 (From : Word_Column; Into : in out Bits_32) is
   begin
      Into.Valid := From.Valid;
      for R in 1 .. From.Rows loop
         Into.Value (R) := Unsigned_32 (From.Value (R) and Low_32);
      end loop;
   end To_Bits_32;

   procedure To_Bits_64 (From : Word_Column; Into : in out Bits_64) is
   begin
      Into.Valid := From.Valid;
      for R in 1 .. From.Rows loop
         Into.Value (R) := From.Value (R);
      end loop;
   end To_Bits_64;

   function Text (Names : Coded; Code : Natural) return String is
      Raw    : constant Bytes := Entry_Bytes (Names, Code);
      Result : String (1 .. Raw'Length);
   begin
      for K in Result'Range loop
         Result (K) := Character'Val (Raw (Raw'First + K - 1));
      end loop;
      return Result;
   end Text;

end Tessera.Columns;
