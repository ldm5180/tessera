with Ada.Directories;

with Interfaces; use Interfaces;

with Tessera.Columns;
with Tessera_Expected; use Tessera_Expected;

package body Tessera_World is

   function Data_Dir (Info : Fabula.Frames.Frame) return String is
      use Ada.Directories;
      Feature  : constant String := Fabula.Frames.Value (Info.File);
      Features : constant String := Containing_Directory (Feature);
   begin
      return Containing_Directory (Features) & "/data";
   end Data_Dir;

   procedure Open (Path : String) is
      use Ada.Directories;
   begin
      Tessera.Files.Open (Path, Open_File, Opened);
      Expected :=
        Load
          (Containing_Directory (Path)
           & "/"
           & Base_Name (Path)
           & ".expected.csv");
   end Open;

   --  Row group Group's chunk of column Number, through the Read_* its
   --  physical type takes.
   function Read_Typed
     (Group : Group_Number; Number : Column_Number) return Typed_Read
   is
      Column : constant Column_Info :=
        Tessera.Files.Column (Open_File, Number);
      Name   : constant String := Name_Of (Column);
      Read   : Typed_Read := (Column => Column, others => <>);
   begin
      Read.Rows := Group_Rows (Open_File, Group);
      case Column.Kind is
         when Bool    =>
            Read_Truths (Open_File, Group, Name, Read.Truths, Read.Result);

         when Int32   =>
            Read_Ints_32 (Open_File, Group, Name, Read.Ints_4, Read.Result);

         when Int64   =>
            Read_Ints_64 (Open_File, Group, Name, Read.Ints_8, Read.Result);

         when Float32 =>
            Read_Bits_32 (Open_File, Group, Name, Read.Bits_4, Read.Result);

         when Float64 =>
            Read_Bits_64 (Open_File, Group, Name, Read.Bits_8, Read.Result);

         when others  =>
            Read_Coded (Open_File, Group, Name, Read.Coded, Read.Result);
      end case;
      return Read;
   end Read_Typed;

   --  An unsigned annotation's value, from the pattern it arrives as.
   function Unsigned_Image (V : Integer_64) return String
   is (Plain (Unsigned_64'Mod (V)'Image));

   function Render_32 (Read : Typed_Read; Row : Positive) return String
   is (if Read.Column.Note = Uint_32
       then Unsigned_Image (Integer_64 (Read.Ints_4.Value (Row)) mod 2**32)
       else Plain (Read.Ints_4.Value (Row)'Image));

   function Render_64 (Read : Typed_Read; Row : Positive) return String
   is (if Read.Column.Note = Uint_64
       then Unsigned_Image (Read.Ints_8.Value (Row))
       else Plain (Read.Ints_8.Value (Row)'Image));

   --  Whether row Row of Read holds a value.
   function Valid (Read : Typed_Read; Row : Positive) return Boolean
   is (case Read.Column.Kind is
         when Bool    => Read.Truths.Valid (Row),
         when Int32   => Read.Ints_4.Valid (Row),
         when Int64   => Read.Ints_8.Valid (Row),
         when Float32 => Read.Bits_4.Valid (Row),
         when Float64 => Read.Bits_8.Valid (Row),
         when others  => Read.Coded.Valid (Row));

   function Render (Read : Typed_Read; Row : Positive) return String
   is (if not Valid (Read, Row)
       then Null_Text
       else
         (case Read.Column.Kind is
            when Bool    => Truth (Read.Truths.Value (Row)),
            when Int32   => Render_32 (Read, Row),
            when Int64   => Render_64 (Read, Row),
            when Float32 => Hex (Unsigned_64 (Read.Bits_4.Value (Row)), 8),
            when Float64 => Hex (Read.Bits_8.Value (Row), 16),
            when others  =>
              Tessera.Columns.Text (Read.Coded.all, Read.Coded.Code (Row))));

   procedure Read_Column (Name : String) is
      Number : constant Column_Count := Tessera.Files.Find (Open_File, Name);
      Read   : Column_Read (Row_Groups (Open_File));
   begin
      for G in Read.Chunks'Range loop
         exit when Number = 0;
         Read.Chunks (G) := Read_Typed (G, Number);
         if Read.Result.Ok then
            Read.Result := Read.Chunks (G).Result;
         end if;
      end loop;
      Last_Read := Read;
   end Read_Column;

   --  Row group G's chunk of the column last read.
   function Chunk (G : Group_Number) return Typed_Read
   is (Last_Read.Chunks (G));

   --  The first row of chunk G (from 1) that differs from row Base + R
   --  of Expected's column Column; 0 when none does.
   function Chunk_Difference
     (G : Group_Number; Column : Natural; Base : Natural) return Natural is
   begin
      for R in 1 .. Chunk (G).Rows loop
         if Column = 0
           or else Base + R > Natural (Expected.Rows.Length)
           or else Render (Chunk (G), R) /= Value (Expected, Base + R, Column)
         then
            return R;
         end if;
      end loop;
      return 0;
   end Chunk_Difference;

   function First_Difference (Name : String) return Natural is
      Column : constant Natural := Column_Of (Expected, Name);
      Base   : Natural := 0;
   begin
      for G in 1 .. Last_Read.Groups loop
         if not Chunk (G).Result.Ok
           or else Chunk_Difference (G, Column, Base) > 0
         then
            return Base + Natural'Max (Chunk_Difference (G, Column, Base), 1);
         end if;
         Base := Base + Chunk (G).Rows;
      end loop;
      return (if Base = Natural (Expected.Rows.Length) then 0 else Base + 1);
   end First_Difference;

   --  How many distinct codes the valid rows of Coded hold.
   function Distinct (Coded : Tessera.Columns.Coded) return Natural is
      Seen  : array (1 .. Coded.Entries) of Boolean := [others => False];
      Count : Natural := 0;
   begin
      for R in 1 .. Coded.Rows loop
         if Coded.Valid (R)
           and then Coded.Code (R) in Seen'Range
           and then not Seen (Coded.Code (R))
         then
            Seen (Coded.Code (R)) := True;
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Distinct;

   function Distinct_Codes return Natural is
      Total : Natural := 0;
   begin
      for G in 1 .. Last_Read.Groups loop
         if Chunk (G).Coded /= null then
            Total := Total + Distinct (Chunk (G).Coded.all);
         end if;
      end loop;
      return Total;
   end Distinct_Codes;

   function First_Wrong_Column return String is
   begin
      for K in 1 .. Column_Total (Open_File) loop
         declare
            Name : constant String :=
              Name_Of (Tessera.Files.Column (Open_File, K));
         begin
            Read_Column (Name);
            if First_Difference (Name) > 0 then
               return Name & First_Difference (Name)'Image;
            end if;
         end;
      end loop;
      return "";
   end First_Wrong_Column;

   function Type_Name (Kind : Physical_Type) return String
   is (case Kind is
         when Bool                 => "BOOLEAN",
         when Int32                => "INT32",
         when Int64                => "INT64",
         when Int96                => "INT96",
         when Float32              => "FLOAT",
         when Float64              => "DOUBLE",
         when Byte_Array           => "BYTE_ARRAY",
         when Fixed_Len_Byte_Array => "FIXED_LEN_BYTE_ARRAY");

   --  The bit width an integer annotation names.
   function Width (Note : Annotation) return String
   is (case Note is
         when Int_8 | Uint_8   => "8",
         when Int_16 | Uint_16 => "16",
         when Int_32 | Uint_32 => "32",
         when others           => "64");

   function Note_Name (Note : Annotation) return String
   is (case Note is
         when None              => "",
         when Text              => "STRING",
         when Date              => "DATE",
         when Time_Micros       => "TIME MICROS",
         when Timestamp_Micros  => "TIMESTAMP MICROS",
         when Int_8 .. Int_64   => "SIGNED " & Width (Note),
         when Uint_8 .. Uint_64 => "UNSIGNED " & Width (Note),
         when Other             => "OTHER");

end Tessera_World;
