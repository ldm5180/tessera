with Tessera;        use Tessera;
with Tessera.Footer; use Tessera.Footer;

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

end Tessera_Fixtures;
