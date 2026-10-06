with Ada.Strings.Unbounded;

with Fabula.Frames;

with Tessera;        use Tessera;
with Tessera.Files;  use Tessera.Files;
with Tessera.Footer; use Tessera.Footer;
with Tessera_Expected;

--  What the features read that is not per scenario, and what is too big
--  for fabula to copy per step: where the fixtures are, the file a
--  scenario has opened through Tessera.Files, and the columns it read.
--  A scenario's small values live in Tessera_Steps.World.

package Tessera_World is

   --  The file opened, what opening it gave, and what it should read
   --  back as: its .expected.csv.
   Open_File : Tessera.Files.File;
   Opened    : Outcome;
   Expected  : Tessera_Expected.Table;

   --  Opens the file at Path, and loads Expected.
   procedure Open (Path : String);

   --  One row group's chunk of a column, read through the Read_* its
   --  physical type takes, or the refusal.
   type Typed_Read is record
      Column : Column_Info;
      Rows   : Natural := 0;
      Truths : Truths_Access;
      Ints_4 : Ints_32_Access;
      Ints_8 : Ints_64_Access;
      Bits_4 : Bits_32_Access;
      Bits_8 : Bits_64_Access;
      Coded  : Coded_Access;
      Result : Outcome;
   end record;

   --  Row Row of a chunk read, as the fixtures' .expected.csv writes it.
   function Render (Read : Typed_Read; Row : Positive) return String;

   type Typed_Reads is array (Group_Number range <>) of Typed_Read;

   --  The column last read: one chunk read a row group, and the first
   --  refusal among them.
   type Column_Read (Groups : Group_Count := 0) is record
      Chunks : Typed_Reads (1 .. Groups);
      Result : Outcome;
   end record;

   Last_Read : Column_Read;
   Last_Name : Ada.Strings.Unbounded.Unbounded_String;

   --  Reads the column Name, every row group of it, into Last_Read.
   procedure Read_Column (Name : String);

   --  The first row (counting across row groups, from 1) of Last_Read
   --  whose value differs from Expected's column Name, or 0.
   function First_Difference (Name : String) return Natural;

   --  Row Row of Last_Read (counting across row groups, from 1) as the
   --  .expected.csv would write it; empty when there is no such row.
   function Row_Text (Row : Positive) return String;

   --  True when Last_Read holds rows and none of them a value.
   function All_Null return Boolean;

   --  How many distinct codes the rows of Last_Read hold, summed over its
   --  row groups.
   function Distinct_Codes return Natural;

   --  Every column read and checked against Expected in turn: the first
   --  that is refused or differs, as "name row", or "" when none does.
   function First_Wrong_Column return String;

   --  What First_Wrong_Column gave when every column was last read.
   Every_Read : Ada.Strings.Unbounded.Unbounded_String;

   --  Opens the file at Path and reads every column of every row group:
   --  the first refusal met, or Ok.
   function Read_In_Full (Path : String) return Outcome;

   --  The Parquet name of a physical type: BOOLEAN, INT32, ...
   function Type_Name (Kind : Physical_Type) return String;

   --  An annotation in the features' words: STRING, DATE, TIME MICROS,
   --  UNSIGNED 8, ...; empty for none.
   function Note_Name (Note : Annotation) return String;

   --  The fixture directory, tests/data, beside the features directory
   --  of the feature file Info is running.
   function Data_Dir (Info : Fabula.Frames.Frame) return String;

   --  The path of the fixture Name in Data_Dir (Info).
   function Fixture (Info : Fabula.Frames.Frame; Name : String) return String
   is (Data_Dir (Info) & "/" & Name);

end Tessera_World;
