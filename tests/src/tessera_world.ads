with Fabula.Frames;

--  What the features read that is not per scenario: where the fixtures
--  are.  A scenario's own values live in Tessera_Steps.World.

package Tessera_World is

   --  The fixture directory, tests/data, beside the features directory
   --  of the feature file Info is running.
   function Data_Dir (Info : Fabula.Frames.Frame) return String;

   --  The path of the fixture Name in Data_Dir (Info).
   function Fixture (Info : Fabula.Frames.Frame; Name : String) return String
   is (Data_Dir (Info) & "/" & Name);

end Tessera_World;
