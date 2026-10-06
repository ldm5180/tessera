with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Tessera_Expected is

   --  The fields of Line, split at each comma.
   function Split (Line : String) return Text_Vectors.Vector is
      Fields : Text_Vectors.Vector;
      From   : Positive := Line'First;
      Comma  : Natural;
   begin
      loop
         Comma := Ada.Strings.Fixed.Index (Line (From .. Line'Last), ",");
         exit when Comma = 0;
         Fields.Append (Line (From .. Comma - 1));
         From := Comma + 1;
      end loop;
      Fields.Append (Line (From .. Line'Last));
      return Fields;
   end Split;

   function Load (Path : String) return Table is
      use Ada.Text_IO;
      T    : Table;
      File : File_Type;
   begin
      if not Ada.Directories.Exists (Path) then
         return T;
      end if;
      Open (File, In_File, Path);
      T.Names := Split (Get_Line (File));
      while not End_Of_File (File) loop
         T.Rows.Append (Row'(Fields => Split (Get_Line (File))));
      end loop;
      Close (File);
      return T;
   end Load;

   function Column_Of (T : Table; Name : String) return Natural is
   begin
      for K in 1 .. Natural (T.Names.Length) loop
         if T.Names (K) = Name then
            return K;
         end if;
      end loop;
      return 0;
   end Column_Of;

end Tessera_Expected;
