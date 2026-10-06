with Interfaces; use Interfaces;

with Tessera.Footer;
with Tessera.Hybrid; use Tessera.Hybrid;
with Tessera.Thrift;

--  One page of a column chunk: its header, and its bytes (already
--  decompressed) turned into rows.  A dictionary page holds PLAIN
--  values; a version 1 data page holds, for a column that may hold
--  nulls, its definition levels (a 4-byte length, then the hybrid at
--  width 1: 1 a value, 0 a null), then the values of the non-null rows
--  only, PLAIN or as dictionary indices (a byte of bit width, then the
--  hybrid).  Rows are appended to a column under construction: a column
--  of 64-bit words for the fixed-width types, a coded column for byte
--  arrays.  A coded column keeps one entry per distinct byte string, so
--  the plain values a writer falls back to after its dictionary grew
--  too large take the codes their bytes already have.

package Tessera.Pages
  with SPARK_Mode
is

   subtype Row_Count is Footer.Row_Count;

   type Flags is array (Buffer_Index range <>) of Boolean;
   type Words is array (Buffer_Index range <>) of Unsigned_64;
   type Counts is array (Buffer_Index range <>) of Buffer_Count;

   --  The page types, in the order of their codes 0 .. 3.
   type Page_Kind is (Data_Page, Index_Page, Dictionary_Page, Data_Page_V2);

   --  The encodings a page names.
   Plain_Encoding            : constant := 0;
   Plain_Dictionary_Encoding : constant := 2;
   Rle_Encoding              : constant := 3;
   Rle_Dictionary_Encoding   : constant := 8;

   --  A page header: its kind, its sizes, how many values it holds
   --  (nulls included), and how they and its levels are encoded.
   type Header is record
      Kind           : Page_Kind := Data_Page;
      Uncompressed   : Buffer_Count := 0;
      Compressed     : Buffer_Count := 0;
      Values         : Buffer_Count := 0;
      Encoding       : Integer_32 := Plain_Encoding;
      Level_Encoding : Integer_32 := Rle_Encoding;
   end record;

   --  Reads a PageHeader at C.  Corrupt_Page when it is malformed, names
   --  a page type outside 0 .. 3, lacks the header its type needs, or
   --  states a size past the bytes left after it.
   procedure Read_Header
     (Input  : Bytes;
      C      : in out Thrift.Cursor;
      H      : out Header;
      Result : out Outcome)
   with
     Post =>
       Thrift.Sound (C, Input)
       and then (if Result.Ok
                 then C.Ok and then H.Compressed <= Thrift.Left (C, Input));

   --  How wide a fixed-width plain value is.
   type Plain_Width is (One_Bit, Four_Bytes, Eight_Bytes);

   --  How one page is read: its header, the width of a fixed-width plain
   --  value, and whether the page carries definition levels.
   type Page_Plan is record
      H        : Header;
      Width    : Plain_Width := Eight_Bytes;
      Optional : Boolean := True;
   end record;

   --  A fixed-width column under construction: Filled rows so far, each
   --  valid or null, each value its bit pattern zero-extended to 64; and
   --  the chunk's dictionary, Dictionary_Size values.
   type Word_Column
     (Rows     : Row_Count;
      Capacity : Buffer_Count)
   is record
      Filled          : Row_Count := 0;
      Valid           : Flags (1 .. Rows) := [others => False];
      Value           : Words (1 .. Rows) := [others => 0];
      Dictionary_Size : Buffer_Count := 0;
      Dictionary      : Words (1 .. Capacity) := [others => 0];
   end record;

   --  A dictionary page's Plan.H.Values plain values, as Into's
   --  dictionary.
   procedure Dictionary_Words
     (Page   : Bytes;
      Plan   : Page_Plan;
      Into   : in out Word_Column;
      Result : out Outcome);

   --  A data page's rows appended to Into.  Scratch holds levels and
   --  indices on the way.
   procedure Data_Words
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   with Pre => Scratch'Length >= Into.Rows;

   --  A byte-array column under construction: Filled rows so far, each
   --  valid or null and, when valid, the entry its bytes are (1 ..
   --  Entries).  Entry E is Length (E) bytes of Text from Start (E).  The
   --  first Dictionary_Entries entries are the dictionary page's, in its
   --  order.  Slots is an open-addressed table of entries by their bytes,
   --  which keeps the entries distinct.
   type Text_Column
     (Rows        : Row_Count;
      Max_Entries : Buffer_Count;
      Max_Bytes   : Buffer_Count;
      Slot_Count  : Buffer_Count)
   is record
      Filled             : Row_Count := 0;
      Valid              : Flags (1 .. Rows) := [others => False];
      Code               : Counts (1 .. Rows) := [others => 0];
      Entries            : Buffer_Count := 0;
      Dictionary_Entries : Buffer_Count := 0;
      Start              : Counts (1 .. Max_Entries) := [others => 0];
      Length             : Counts (1 .. Max_Entries) := [others => 0];
      Used               : Buffer_Count := 0;
      Text               : Bytes (1 .. Max_Bytes) := [others => 0];
      Slots              : Counts (1 .. Slot_Count) := [others => 0];
   end record;

   --  True when entry E of Column lies within its Text.
   function Entry_Fits (Column : Text_Column; E : Positive) return Boolean
   is (E <= Column.Entries
       and then E <= Column.Max_Entries
       and then Column.Start (E) <= Column.Max_Bytes
       and then Column.Length (E) <= Column.Max_Bytes - Column.Start (E));

   --  The bytes of entry E; empty when there is no such entry.
   function Entry_Bytes (Column : Text_Column; E : Natural) return Bytes
   is (if E > 0 and then Entry_Fits (Column, E) and then Column.Length (E) > 0
       then
         Column.Text
           (Column.Start (E) + 1 .. Column.Start (E) + Column.Length (E))
       else Column.Text (1 .. 0));

   --  A dictionary page's H.Values byte arrays, as Into's first entries.
   --  Scratch is working space.
   procedure Dictionary_Text
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome);

   --  A data page's rows appended to Into.
   procedure Data_Text
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   with Pre => Scratch'Length >= Into.Rows;

end Tessera.Pages;
