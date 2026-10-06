with Fabula.Frames;

with Tessera;          use Tessera;
with Tessera.Footer;   use Tessera.Footer;
with Tessera_Expected;
with Tessera_Fixtures; use Tessera_Fixtures;

--  What the features read that is not per scenario, and what is too big
--  for fabula to copy per step: where the fixtures are, and the file a
--  scenario has opened.  A scenario's small values live in
--  Tessera_Steps.World.

package Tessera_World is

   --  The file last opened: its bytes, its footer, and what opening it
   --  gave.
   Opened : Opened_File;

   --  What the file opened should read back as: its .expected.csv.
   Expected : Tessera_Expected.Table;

   --  Opens the file at Path into Opened, and loads Expected.
   procedure Open (Path : String);

   type Chunk_Reads is array (Group_Number range <>) of Chunk_Read;

   --  The column last read: one chunk read a row group, and the first
   --  refusal among them.
   type Column_Read (Groups : Group_Count := 0) is record
      Chunks : Chunk_Reads (1 .. Groups);
      Result : Outcome;
   end record;

   Last_Read : Column_Read;

   --  Reads the column Name, every row group of it, into Last_Read.
   procedure Read_Column (Name : String);

   --  The first row (counting across row groups, from 1) of Last_Read
   --  whose value differs from Expected's column Name, or 0.
   function First_Difference (Name : String) return Natural;

   --  How many distinct codes the rows of Last_Read hold, summed over its
   --  row groups.
   function Distinct_Codes return Natural;

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
