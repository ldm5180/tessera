with Fabula.Frames;

with Tessera;          use Tessera;
with Tessera.Footer;   use Tessera.Footer;
with Tessera_Fixtures; use Tessera_Fixtures;

--  What the features read that is not per scenario, and what is too big
--  for fabula to copy per step: where the fixtures are, and the file a
--  scenario has opened.  A scenario's small values live in
--  Tessera_Steps.World.

package Tessera_World is

   --  The file last opened: its bytes, its footer, and what opening it
   --  gave.
   Opened : Opened_File;

   --  Opens the file at Path into Opened.
   procedure Open (Path : String);

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
