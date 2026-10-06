with Ada.Real_Time; use Ada.Real_Time;
with Ada.Text_IO;   use Ada.Text_IO;

with Interfaces; use Interfaces;

with Tessera;        use Tessera;
with Tessera.Files;  use Tessera.Files;
with Tessera.Footer; use Tessera.Footer;
with Tessera.Names;

package body Bench_Columns is

   Megabyte : constant := 1_000_000;
   Percent  : constant := 100;

   --  A count of bytes as megabytes, to two places.
   function Megabytes (Bytes : Integer_64) return String is
      Hundredths : constant Integer_64 := Bytes * Percent / Megabyte;
      Fraction   : constant String :=
        Integer_64'Image (Percent + Hundredths mod Percent);
   begin
      return
        Integer_64'Image (Hundredths / Percent)
        & "."
        & Fraction (Fraction'Last - 1 .. Fraction'Last);
   end Megabytes;

   --  What reading a column found: rows, bytes, and for a string column
   --  its dictionary entries and the plain values that added more.
   type Tally is record
      Rows       : Natural := 0;
      Bytes      : Integer_64 := 0;
      Dictionary : Natural := 0;
      Added      : Natural := 0;
      Result     : Outcome;
   end record;

   --  Row group G of column Name, a string column, added to T.
   procedure Read_Coded_Group
     (F : File; G : Positive; Name : String; T : in out Tally)
   is
      Coded : Coded_Access;
   begin
      Read_Coded (F, G, Name, Coded, T.Result);
      if T.Result.Ok then
         T.Rows := T.Rows + Coded.Rows;
         T.Dictionary := T.Dictionary + Coded.Dictionary_Entries;
         T.Added := T.Added + Coded.Entries - Coded.Dictionary_Entries;
      end if;
      Free (Coded);
   end Read_Coded_Group;

   --  Row group G of column Name, of physical type Kind, added to T.
   procedure Read_Group
     (F    : File;
      G    : Positive;
      Name : String;
      Kind : Physical_Type;
      T    : in out Tally);

   procedure Read_Group
     (F    : File;
      G    : Positive;
      Name : String;
      Kind : Physical_Type;
      T    : in out Tally)
   is
      Wide   : Ints_64_Access;
      Narrow : Ints_32_Access;
      Single : Bits_32_Access;
      Double : Bits_64_Access;
      Truth  : Truths_Access;
   begin
      case Kind is
         when Int64   =>
            Read_Ints_64 (F, G, Name, Wide, T.Result);
            Free (Wide);

         when Int32   =>
            Read_Ints_32 (F, G, Name, Narrow, T.Result);
            Free (Narrow);

         when Float32 =>
            Read_Bits_32 (F, G, Name, Single, T.Result);
            Free (Single);

         when Float64 =>
            Read_Bits_64 (F, G, Name, Double, T.Result);
            Free (Double);

         when Bool    =>
            Read_Truths (F, G, Name, Truth, T.Result);
            Free (Truth);

         when others  =>
            Read_Coded_Group (F, G, Name, T);
            return;
      end case;
      if T.Result.Ok then
         T.Rows := T.Rows + Group_Rows (F, G);
      end if;
   end Read_Group;

   procedure Report
     (Name : String; Kind : Physical_Type; T : Tally; Took : Time_Span) is
   begin
      Put
        (Name
         & " "
         & Tessera.Names.Physical_Name (Physical_Type'Pos (Kind))
         & ":"
         & T.Rows'Image
         & " rows,"
         & Megabytes (T.Bytes)
         & " MB,"
         & Duration'Image (To_Duration (Took))
         & " s");
      if Kind = Byte_Array then
         Put
           (", dictionary entries"
            & T.Dictionary'Image
            & ", plain values added"
            & T.Added'Image);
      end if;
      if not T.Result.Ok then
         Put (", refused: " & Tessera.Names.Describe (T.Result));
      end if;
      New_Line;
   end Report;

   procedure Bench (F : File; Name : String; Ok : out Boolean) is
      Number : constant Column_Count := Find (F, Name);
      Kind   : constant Physical_Type :=
        (if Number = 0 then Bool else Column (F, Number).Kind);
      T      : Tally;
      Start  : constant Time := Clock;
   begin
      Ok := Number > 0;
      if not Ok then
         Put_Line (Name & ": no such column");
         return;
      end if;
      for G in 1 .. Row_Groups (F) loop
         Read_Group (F, G, Name, Kind, T);
         exit when not T.Result.Ok;
         T.Bytes := T.Bytes + Chunk_Bytes (F, G, Number);
      end loop;
      Report (Name, Kind, T, Clock - Start);
      Ok := T.Result.Ok and then Integer_64 (T.Rows) = Rows (F);
   end Bench;

end Bench_Columns;
