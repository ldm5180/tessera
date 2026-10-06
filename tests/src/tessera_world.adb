with Ada.Directories;

with Tessera.Pages; use Tessera.Pages;

package body Tessera_World is

   --  Row group G's chunk of the column last read.
   function Chunk (G : Group_Number) return Chunk_Read
   is (Last_Read.Chunks (G));

   --  How many distinct codes the valid rows of Column hold.
   function Distinct (Column : Text_Column) return Natural is
      Seen  : array (1 .. Column.Entries) of Boolean := [others => False];
      Count : Natural := 0;
   begin
      for R in 1 .. Column.Rows loop
         if Column.Valid (R)
           and then Column.Code (R) in Seen'Range
           and then not Seen (Column.Code (R))
         then
            Seen (Column.Code (R)) := True;
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Distinct;

   function Data_Dir (Info : Fabula.Frames.Frame) return String is
      use Ada.Directories;
      File     : constant String := Fabula.Frames.Value (Info.File);
      Features : constant String := Containing_Directory (File);
   begin
      return Containing_Directory (Features) & "/data";
   end Data_Dir;

   procedure Open (Path : String) is
      Name : constant String := Ada.Directories.Simple_Name (Path);
      Base : constant String := Ada.Directories.Base_Name (Path);
   begin
      Opened := Tessera_Fixtures.Open (Name);
      Expected :=
        Tessera_Expected.Load
          (Ada.Directories.Containing_Directory (Path)
           & "/"
           & Base
           & ".expected.csv");
   end Open;

   procedure Read_Column (Name : String) is
      Column : constant Column_Count := Find (Opened.Meta.all, Name);
      Read   : Column_Read (Opened.Meta.Groups);
   begin
      for G in Read.Chunks'Range loop
         if Column > 0 then
            Read.Chunks (G) := Read_Chunk (Opened, G, Column);
            if Read.Result.Ok then
               Read.Result := Read.Chunks (G).Result;
            end if;
         end if;
      end loop;
      Last_Read := Read;
   end Read_Column;

   function First_Difference (Name : String) return Natural is
      Column : constant Natural := Tessera_Expected.Column_Of (Expected, Name);
      Row    : Natural := 0;
   begin
      for G in 1 .. Last_Read.Groups loop
         for R in 1 .. Chunk (G).Rows loop
            Row := Row + 1;
            if Column = 0
              or else Row > Natural (Expected.Rows.Length)
              or else Render (Chunk (G), R)
                      /= Tessera_Expected.Value (Expected, Row, Column)
            then
               return Row;
            end if;
         end loop;
      end loop;
      return (if Row = Natural (Expected.Rows.Length) then 0 else Row + 1);
   end First_Difference;

   function Distinct_Codes return Natural is
      Total : Natural := 0;
   begin
      for G in 1 .. Last_Read.Groups loop
         if Chunk (G).Text /= null then
            Total := Total + Distinct (Chunk (G).Text.all);
         end if;
      end loop;
      return Total;
   end Distinct_Codes;

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
