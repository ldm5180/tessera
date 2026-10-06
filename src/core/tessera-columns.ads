with Interfaces; use Interfaces;

with Tessera.Footer;
with Tessera.Hybrid;
with Tessera.Pages; use Tessera.Pages;

--  A column chunk's pages, read in turn into one column of the chunk's
--  rows.  The page sequence is an sml machine: Start, then a dictionary
--  page (Have_Dictionary) or data pages (In_Data), then Done when the
--  bytes end with every row read; a second dictionary, a version 2 or
--  index page, a page that cannot be read, or bytes that end short of
--  the rows, is Refused.  Each page is decompressed into the workspace
--  and handed to Tessera.Pages.  The typed columns a caller is handed
--  are made from the column read: every physical value keeps its bit
--  pattern, and FLOAT and DOUBLE are never formed into numbers.

package Tessera.Columns
  with SPARK_Mode
is

   subtype Row_Count is Footer.Row_Count;

   --  How a chunk is read: compressed with Snappy or not, how wide one
   --  of its fixed-width values is, whether it may hold nulls.
   type Chunk_Shape is record
      Snappy   : Boolean := True;
      Width    : Plain_Width := Eight_Bytes;
      Optional : Boolean := True;
   end record;

   --  The room a chunk is read in: one decompressed page, and one code a
   --  row for levels and indices.
   type Workspace
     (Page_Size : Buffer_Count;
      Rows      : Row_Count)
   is record
      Page    : Bytes (1 .. Page_Size) := [others => 0];
      Scratch : Hybrid.Codes (1 .. Rows) := [others => 0];
   end record;

   --  The pages of Chunk read into Into, a fixed-width column.
   procedure Read_Words
     (Chunk  : Bytes;
      Shape  : Chunk_Shape;
      Space  : in out Workspace;
      Into   : in out Word_Column;
      Result : out Outcome);

   --  The pages of Chunk read into Into, a byte-array column.
   procedure Read_Text
     (Chunk  : Bytes;
      Shape  : Chunk_Shape;
      Space  : in out Workspace;
      Into   : in out Text_Column;
      Result : out Outcome);

   ---------------------------------------------------------------------
   --  The columns a caller is handed
   ---------------------------------------------------------------------

   type Bits_32_Array is array (Buffer_Index range <>) of Unsigned_32;
   type Bits_64_Array is array (Buffer_Index range <>) of Unsigned_64;
   type Int_32_Array is array (Buffer_Index range <>) of Integer_32;
   type Int_64_Array is array (Buffer_Index range <>) of Integer_64;

   --  A BOOLEAN column: each row valid or null, and its value.
   type Truths (Rows : Row_Count) is record
      Valid : Flags (1 .. Rows) := [others => False];
      Value : Flags (1 .. Rows) := [others => False];
   end record;

   --  An INT32 column (DATE: days since 1970-01-01).  An unsigned 32-bit
   --  annotation's value past Integer_32'Last arrives as its pattern.
   type Ints_32 (Rows : Row_Count) is record
      Valid : Flags (1 .. Rows) := [others => False];
      Value : Int_32_Array (1 .. Rows) := [others => 0];
   end record;

   --  An INT64 column (TIME and TIMESTAMP: microseconds).  An unsigned
   --  64-bit value past Integer_64'Last arrives as its pattern.
   type Ints_64 (Rows : Row_Count) is record
      Valid : Flags (1 .. Rows) := [others => False];
      Value : Int_64_Array (1 .. Rows) := [others => 0];
   end record;

   --  A FLOAT column: each value its 32-bit pattern.
   type Bits_32 (Rows : Row_Count) is record
      Valid : Flags (1 .. Rows) := [others => False];
      Value : Bits_32_Array (1 .. Rows) := [others => 0];
   end record;

   --  A DOUBLE column: each value its 64-bit pattern.
   type Bits_64 (Rows : Row_Count) is record
      Valid : Flags (1 .. Rows) := [others => False];
      Value : Bits_64_Array (1 .. Rows) := [others => 0];
   end record;

   --  A BYTE_ARRAY column: Code (I) is row I's entry, 0 for a null.
   subtype Coded is Text_Column;

   --  The sign bit of a 32-bit pattern, and the bits below it.
   Sign_32 : constant := 2**31;
   Low_31  : constant := 2**31 - 1;

   --  The integer whose 32-bit two's-complement pattern is the low half
   --  of W.
   function Signed_32 (W : Unsigned_64) return Integer_32
   is (if (W and Sign_32) = 0
       then Integer_32 (W and Low_31)
       else -Integer_32 ((not W) and Low_31) - 1);

   --  The integer whose 64-bit two's-complement pattern is W.
   function Signed_64 (W : Unsigned_64) return Integer_64
   is (if W < 2**63 then Integer_64 (W) else -Integer_64 (not W) - 1);

   procedure To_Truths (From : Word_Column; Into : in out Truths)
   with Pre => Into.Rows = From.Rows;

   procedure To_Ints_32 (From : Word_Column; Into : in out Ints_32)
   with Pre => Into.Rows = From.Rows;

   procedure To_Ints_64 (From : Word_Column; Into : in out Ints_64)
   with Pre => Into.Rows = From.Rows;

   procedure To_Bits_32 (From : Word_Column; Into : in out Bits_32)
   with Pre => Into.Rows = From.Rows;

   procedure To_Bits_64 (From : Word_Column; Into : in out Bits_64)
   with Pre => Into.Rows = From.Rows;

   --  The text of entry Code of Names; empty for 0 or no such entry.
   function Text (Names : Coded; Code : Natural) return String;

end Tessera.Columns;
