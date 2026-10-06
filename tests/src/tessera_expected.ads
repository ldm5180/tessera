with Ada.Containers.Indefinite_Vectors;

with Interfaces;

--  A fixture's .expected.csv: its header names the columns, and each
--  line after it is one row, every value as tessera hands it over.

package Tessera_Expected is

   package Text_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, String);

   type Row is record
      Fields : Text_Vectors.Vector;
   end record;

   package Row_Vectors is new
     Ada.Containers.Indefinite_Vectors (Positive, Row);

   --  The header, then the rows.
   type Table is record
      Names : Text_Vectors.Vector;
      Rows  : Row_Vectors.Vector;
   end record;

   --  The table in the file at Path; empty when there is none.
   function Load (Path : String) return Table;

   --  The column of T named Name, or 0.
   function Column_Of (T : Table; Name : String) return Natural;

   --  The value in row Row (from 1) of column Column of T.
   function Value (T : Table; Row, Column : Positive) return String
   is (T.Rows (Row).Fields (Column));

   --  How the table writes a FLOAT or DOUBLE pattern: 0x and Figures
   --  lowercase hex figures.
   function Hex (W : Interfaces.Unsigned_64; Figures : Positive) return String;

   --  How the table writes a number: its image without the leading
   --  blank.
   function Plain (Image : String) return String
   is (if Image'Length > 0 and then Image (Image'First) = ' '
       then Image (Image'First + 1 .. Image'Last)
       else Image);

   --  How the table writes a null.
   Null_Text : constant String := "<null>";

   --  How the table writes a boolean.
   function Truth (B : Boolean) return String
   is (if B then "true" else "false");

end Tessera_Expected;
