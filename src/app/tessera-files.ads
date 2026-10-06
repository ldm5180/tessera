with Ada.Finalization;
with Ada.Strings.Unbounded;

with Interfaces;

with Tessera.Columns;
with Tessera.Footer;

--  A Parquet file on disk: Open reads its last eight bytes, then its
--  footer, and keeps the decoded footer; each Read_* reads one column
--  chunk's byte range and decodes it into a column on the heap, sized
--  from the checked footer.  Nothing raises: every failure, the disk's
--  included, is an Outcome.  A File is not changed by reading it, and
--  each read opens the file anew, so two tasks may read two chunks of
--  one File at once.

package Tessera.Files is

   type File is limited private;

   --  Opens Path into F.  Result is Ok, or the refusal that names the
   --  feature or the fault: Not_Parquet, Truncated, Encrypted, a
   --  Corrupt_Footer, a Nested_Schema, an unsupported codec, encoding or
   --  type, or Cannot_Read when the disk will not give the bytes.
   procedure Open (Path : String; F : in out File; Result : out Outcome);

   function Is_Open (F : File) return Boolean;

   --  The rows of the whole file, and of row group Group.
   function Rows (F : File) return Interfaces.Integer_64;
   function Row_Groups (F : File) return Footer.Group_Count;
   function Group_Rows (F : File; Group : Positive) return Natural;

   --  How many columns, and column Number's name, type and annotation.
   function Column_Total (F : File) return Column_Count;
   function Column
     (F : File; Number : Column_Number) return Footer.Column_Info;

   --  The column named Name, or 0.
   function Find (F : File; Name : String) return Column_Count;

   type Truths_Access is access Tessera.Columns.Truths;
   type Ints_32_Access is access Tessera.Columns.Ints_32;
   type Ints_64_Access is access Tessera.Columns.Ints_64;
   type Bits_32_Access is access Tessera.Columns.Bits_32;
   type Bits_64_Access is access Tessera.Columns.Bits_64;
   type Coded_Access is access Tessera.Columns.Coded;

   --  Column Name of row group Group, read into a new column on the heap
   --  (null when refused).  Each reads one physical type: a BOOLEAN, an
   --  INT32, an INT64, a FLOAT, a DOUBLE or a BYTE_ARRAY column; any other
   --  is Wrong_Type.  No_Such_Row_Group, No_Such_Column, Unsupported_Type
   --  (an annotation tessera does not read), and every refusal of the
   --  chunk's pages, name the column.
   procedure Read_Truths
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Truths_Access;
      Result : out Outcome);

   procedure Read_Ints_32
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Ints_32_Access;
      Result : out Outcome);

   procedure Read_Ints_64
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Ints_64_Access;
      Result : out Outcome);

   procedure Read_Bits_32
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Bits_32_Access;
      Result : out Outcome);

   procedure Read_Bits_64
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Bits_64_Access;
      Result : out Outcome);

   procedure Read_Coded
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Coded_Access;
      Result : out Outcome);

   procedure Free (Column : in out Truths_Access);
   procedure Free (Column : in out Ints_32_Access);
   procedure Free (Column : in out Ints_64_Access);
   procedure Free (Column : in out Bits_32_Access);
   procedure Free (Column : in out Bits_64_Access);
   procedure Free (Column : in out Coded_Access);

   --  Forgets F's footer; F may be opened again.
   procedure Close (F : in out File);

private

   type Metadata_Access is access Footer.Metadata;

   type File is new Ada.Finalization.Limited_Controlled with record
      Path : Ada.Strings.Unbounded.Unbounded_String;
      Meta : Metadata_Access;
   end record;

   overriding
   procedure Finalize (F : in out File);

end Tessera.Files;
