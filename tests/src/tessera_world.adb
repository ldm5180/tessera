with Ada.Directories;

package body Tessera_World is

   function Data_Dir (Info : Fabula.Frames.Frame) return String is
      use Ada.Directories;
      File     : constant String := Fabula.Frames.Value (Info.File);
      Features : constant String := Containing_Directory (File);
   begin
      return Containing_Directory (Features) & "/data";
   end Data_Dir;

end Tessera_World;
