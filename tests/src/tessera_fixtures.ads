with Tessera;        use Tessera;
with Tessera.Footer; use Tessera.Footer;
with Tessera.Pages;  use Tessera.Pages;

--  The committed fixtures under tests/data, read whole for the unit
--  tests (each is a few kilobytes), and their footers.

package Tessera_Fixtures is

   type Bytes_Access is access Bytes;
   type Metadata_Access is access Metadata;

   --  Every byte of the fixture Name (say "flat.parquet").
   function Load (Name : String) return Bytes_Access;

   --  The footer of File: located, decoded and checked.
   procedure Footer_Of
     (File : Bytes; Meta : out Metadata_Access; Result : out Outcome);

   --  A fixture opened: its bytes, its footer, and what opening it gave.
   type Opened_File is record
      File   : Bytes_Access;
      Meta   : Metadata_Access;
      Result : Outcome;
   end record;

   --  Load and Footer_Of together.
   function Open (Name : String) return Opened_File;

   type Word_Access is access Word_Column;
   type Text_Access is access Text_Column;

   --  One chunk read: its column's schema entry, and the fixed-width or
   --  byte-array column read, or the refusal.
   type Chunk_Read is record
      Number : Column_Number := 1;
      Rows   : Natural := 0;
      Column : Column_Info;
      Words  : Word_Access;
      Text   : Text_Access;
      Result : Outcome;
   end record;

   --  The chunk of column Column in row group Group of an opened file.
   function Read_Chunk
     (Opened : Opened_File; Group : Group_Number; Column : Column_Number)
      return Chunk_Read
   with Pre => Opened.Result.Ok;

   --  Row Row of a chunk read, as the fixtures' .expected.csv writes it:
   --  true or false, an integer, 0x and the hex of a FLOAT or DOUBLE
   --  pattern, the text, or <null>.
   function Render (Read : Chunk_Read; Row : Positive) return String
   with Pre => Read.Result.Ok;

end Tessera_Fixtures;
