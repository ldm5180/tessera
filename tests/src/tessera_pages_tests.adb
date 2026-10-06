with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;          use Tessera;
with Tessera.Footer;   use Tessera.Footer;
with Tessera.Hybrid;   use Tessera.Hybrid;
with Tessera.Pages;    use Tessera.Pages;
with Tessera.Thrift;   use Tessera.Thrift;
with Tessera_Fixtures; use Tessera_Fixtures;

--  One page at a time: headers, levels, plain values and dictionary
--  indices, for words and for text, and the pages that lie.

package body Tessera_Pages_Tests is

   use AUnit.Test_Cases.Registration;

   function Data (Values : Natural; Encoding : Integer_32) return Header
   is ((Kind     => Data_Page,
        Values   => Values,
        Encoding => Encoding,
        others   => <>));

   function Dictionary
     (Values : Natural; Encoding : Integer_32 := Plain_Encoding) return Header
   is ((Kind     => Dictionary_Page,
        Values   => Values,
        Encoding => Encoding,
        others   => <>));

   --  How a page with header H is read.
   function Plan
     (H        : Header;
      Width    : Plain_Width := Four_Bytes;
      Optional : Boolean := False) return Page_Plan
   is ((H => H, Width => Width, Optional => Optional));

   --  The little-endian bytes of an INT64 value.
   function Int64 (V : Unsigned_64) return Bytes is
      B : Bytes (1 .. 8);
   begin
      for K in B'Range loop
         B (K) := Byte (Shift_Right (V, 8 * (K - 1)) and 16#FF#);
      end loop;
      return B;
   end Int64;

   procedure Test_Null_Among_Values
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Levels: 2 bytes of hybrid, one packed group, 1 0 1.  Then the
      --  two INT64 values 7 and 9.
      Page    : constant Bytes :=
        [2, 0, 0, 0, 16#03#, 16#05#] & Int64 (7) & Int64 (9);
      Into    : Word_Column (3, 0);
      Scratch : Codes (1 .. 3);
      Result  : Outcome;
   begin
      Data_Words
        (Page,
         Plan (Data (3, Plain_Encoding), Eight_Bytes, Optional => True),
         Into,
         Scratch,
         Result);
      Assert (Result.Ok and then Into.Filled = 3, "three rows");
      Assert
        (Into.Valid (1) and then not Into.Valid (2) and then Into.Valid (3),
         "value, null, value");
      Assert
        (Into.Value (1) = 7 and then Into.Value (3) = 9,
         "the two values in the valid rows");
   end Test_Null_Among_Values;

   --  The first two page headers of flat.parquet's chunk Column.
   procedure Two_Headers (Column : Positive; First, Second : out Header) is
      Opened : constant Opened_File := Open ("flat.parquet");
      File   : constant Bytes_Access := Opened.File;
      Meta   : constant Metadata_Access := Opened.Meta;
      Result : Outcome := Opened.Result;
      Chunk  : Chunk_Info;
      C      : Cursor;
   begin
      Chunk := Meta.Group (1).Chunks (Column);
      declare
         Input : constant Bytes :=
           File
             (Natural (Chunk.Start)
              + 1
              .. Natural (Chunk.Start + Chunk.Compressed_Size));
      begin
         Read_Header (Input, C, First, Result);
         Assert (Result.Ok, "the first header reads");
         C.Pos := C.Pos + First.Compressed;
         Read_Header (Input, C, Second, Result);
         Assert (Result.Ok, "the second header reads");
      end;
   end Two_Headers;

   procedure Test_Real_Headers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      First, Second : Header;
   begin
      Two_Headers (2, First, Second);
      Assert
        (First.Kind = Dictionary_Page
         and then First.Values = 10
         and then First.Encoding = Plain_Encoding,
         "i32's chunk starts with a dictionary page of ten PLAIN values");
      Assert
        (Second.Kind = Data_Page
         and then Second.Values = 10
         and then Second.Encoding = Rle_Dictionary_Encoding
         and then Second.Level_Encoding = Rle_Encoding,
         "then a data page of ten RLE_DICTIONARY values, RLE levels");
      Assert
        (Second.Uncompressed >= Second.Compressed - 8,
         "with sizes that agree roughly");
   end Test_Real_Headers;

   function Header_Outcome (Input : Bytes) return Outcome is
      C      : Cursor;
      H      : Header;
      Result : Outcome;
   begin
      Read_Header (Input, C, H, Result);
      return Result;
   end Header_Outcome;

   procedure Test_Bad_Headers (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  type 0, sizes 4 and 4, data page header {1: 2}, then 4 bytes.
      Good : constant Bytes :=
        [16#15#, 0, 16#15#, 8, 16#15#, 8, 16#2C#, 16#15#, 4, 0, 0, 1, 2, 3, 4];
   begin
      Assert (Header_Outcome (Good).Ok, "a whole header");
      Assert
        (Header_Outcome (Good (1 .. 14)).Why = Corrupt_Page,
         "a page past its bytes");
      Assert
        (not Header_Outcome ([16#15#, 8, 16#15#, 8, 16#15#, 8, 0]).Ok,
         "page type 4");
      Assert
        (not Header_Outcome ([16#15#, 0, 16#15#, 1, 16#15#, 0, 0]).Ok,
         "a size below zero");
      Assert
        (not Header_Outcome ([16#15#, 0, 16#15#, 0, 16#15#, 0, 0]).Ok,
         "a data page without its data header");
      Assert
        (Header_Outcome ([16#15#, 6, 16#15#, 0, 16#15#, 0, 0]).Ok,
         "a version 2 page reads; the chunk refuses it");
   end Test_Bad_Headers;

   procedure Test_Required_Plain (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Page    : constant Bytes := [1, 0, 0, 0, 16#FF#, 16#FF#, 16#FF#, 16#FF#];
      Into    : Word_Column (2, 0);
      Scratch : Codes (1 .. 2);
      Result  : Outcome;
   begin
      Data_Words
        (Page, Plan (Data (2, Plain_Encoding)), Into, Scratch, Result);
      Assert
        (Result.Ok
         and then Into.Valid = [True, True]
         and then Into.Value (1) = 1
         and then Into.Value (2) = 16#FFFF_FFFF#,
         "a required column has no levels; values zero-extended");
   end Test_Required_Plain;

   procedure Test_Booleans (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Ten values, low bit first: 1 0 1 1 0 0 0 0 | 0 1.
      Page    : constant Bytes := [16#0D#, 16#02#];
      Into    : Word_Column (10, 0);
      Scratch : Codes (1 .. 10);
      Result  : Outcome;
   begin
      Data_Words
        (Page,
         Plan (Data (10, Plain_Encoding), One_Bit),
         Into,
         Scratch,
         Result);
      Assert (Result.Ok, "ten bits read");
      Assert
        (Into.Value (1) = 1
         and then Into.Value (2) = 0
         and then Into.Value (4) = 1
         and then Into.Value (9) = 0
         and then Into.Value (10) = 1,
         "low bit first, into a second byte");
   end Test_Booleans;

   procedure Test_Dictionary_Words
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Dict_Page : constant Bytes := [5, 0, 0, 0, 6, 0, 0, 0, 7, 0, 0, 0];
      --  Levels 1 1 0 1 (packed), width 2, packed indices 2 0 1.
      Page      : constant Bytes :=
        [2, 0, 0, 0, 16#03#, 16#0B#, 2, 16#03#, 16#12#, 0];
      Into      : Word_Column (4, 3);
      Scratch   : Codes (1 .. 4);
      Result    : Outcome;
   begin
      Dictionary_Words (Dict_Page, Plan (Dictionary (3)), Into, Result);
      Assert
        (Result.Ok and then Into.Dictionary_Size = 3,
         "three dictionary values");
      Data_Words
        (Page,
         Plan (Data (4, Rle_Dictionary_Encoding), Optional => True),
         Into,
         Scratch,
         Result);
      Assert (Result.Ok, "indices read");
      Assert
        (Into.Value (1) = 7
         and then Into.Value (2) = 5
         and then not Into.Valid (3)
         and then Into.Value (4) = 6,
         "each index looked up, the null skipped");
   end Test_Dictionary_Words;

   --  What reading one data page into a fresh column of four rows (with
   --  a dictionary of one value) gives.
   function Words_Of (Page : Bytes; P : Page_Plan) return Outcome is
      Into    : Word_Column (4, 1);
      Scratch : Codes (1 .. 4);
      Result  : Outcome;
   begin
      Into.Dictionary_Size := 1;
      Data_Words (Page, P, Into, Scratch, Result);
      return Result;
   end Words_Of;

   procedure Test_Refused_Words (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Zeros  : constant Bytes := [1 .. 8 => 0];
      Into   : Word_Column (4, 1);
      Result : Outcome;
   begin
      Assert
        (Words_Of (Zeros, Plan (Data (2, 5))).Value = 5,
         "DELTA_BINARY_PACKED values are refused, named");
      Assert
        (Words_Of
           (Zeros,
            Plan
              ((Data (2, 0) with delta Level_Encoding => 4), Optional => True))
           .Why
         = Unsupported_Encoding,
         "BIT_PACKED levels are refused");
      Assert
        (Words_Of ([1, 0, 0, 0], Plan (Data (2, 0))).Why = Corrupt_Page,
         "fewer plain values than rows");
      Assert
        (Words_Of (Zeros, Plan (Data (5, 0))).Why = Corrupt_Page,
         "more rows than the column has room for");
      Assert
        (Words_Of ([1, 16#04#, 1], Plan (Data (2, 8))).Why = Corrupt_Page,
         "an index past the dictionary");
      Assert
        (Words_Of ([33], Plan (Data (1, 8))).Why = Corrupt_Page,
         "an index width past 32");
      Assert
        (Words_Of ([9, 0, 0, 0, 16#03#], Plan (Data (2, 0), Optional => True))
           .Why
         = Corrupt_Page,
         "levels longer than the page");
      Dictionary_Words (Zeros, Plan (Dictionary (2)), Into, Result);
      Assert (Result.Why = Corrupt_Page, "a dictionary past its room");
      Dictionary_Words ([1], Plan (Dictionary (1), One_Bit), Into, Result);
      Assert (Result.Why = Unsupported_Encoding, "a boolean dictionary");
   end Test_Refused_Words;

   function Text_Of (Column : Text_Column; Row : Positive) return String is
      B : constant Bytes := Entry_Bytes (Column, Column.Code (Row));
      S : String (1 .. B'Length);
   begin
      for K in S'Range loop
         S (K) := Character'Val (B (B'First + K - 1));
      end loop;
      return S;
   end Text_Of;

   procedure Test_Text_Fallback (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  A dictionary of "a" and "bc"; a page coding rows 1 .. 2 as 1 0;
      --  a plain page with "bc", "d", "d" for rows 3 .. 5.
      Dict_Page : constant Bytes := [1, 0, 0, 0, 97, 2, 0, 0, 0, 98, 99];
      Coded     : constant Bytes := [1, 16#03#, 16#01#];
      Plain     : constant Bytes :=
        [2, 0, 0, 0, 98, 99, 1, 0, 0, 0, 100, 1, 0, 0, 0, 100];
      Into      : Text_Column (5, 8, 16, 17);
      Scratch   : Codes (1 .. 5);
      Result    : Outcome;
   begin
      Dictionary_Text
        (Dict_Page, Plan (Dictionary (2)), Into, Scratch, Result);
      Assert (Result.Ok and then Into.Dictionary_Entries = 2, "two entries");
      Data_Text
        (Coded,
         Plan (Data (2, Rle_Dictionary_Encoding)),
         Into,
         Scratch,
         Result);
      Assert (Result.Ok and then Into.Code (1 .. 2) = [2, 1], "bc, a");
      Data_Text
        (Plain, Plan (Data (3, Plain_Encoding)), Into, Scratch, Result);
      Assert (Result.Ok and then Into.Filled = 5, "five rows");
      Assert
        (Into.Code (3) = 2,
         "a plain value already in the dictionary takes its code");
      Assert
        (Into.Code (4) = 3
         and then Into.Code (5) = 3
         and then Into.Entries = 3,
         "a new value is one new entry, however often it comes");
      Assert
        (Text_Of (Into, 1) = "bc" and then Text_Of (Into, 5) = "d",
         "codes read back as their bytes");
   end Test_Text_Fallback;

   procedure Test_Text_Nulls (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Levels 0 1 1; plain "x", "y".
      Page    : constant Bytes :=
        [2, 0, 0, 0, 16#03#, 16#06#, 1, 0, 0, 0, 120, 1, 0, 0, 0, 121];
      Into    : Text_Column (3, 4, 4, 9);
      Scratch : Codes (1 .. 3);
      Result  : Outcome;
   begin
      Data_Text
        (Page,
         Plan (Data (3, Plain_Encoding), Optional => True),
         Into,
         Scratch,
         Result);
      Assert
        (Result.Ok
         and then not Into.Valid (1)
         and then Into.Code (1) = 0
         and then Text_Of (Into, 2) = "x"
         and then Text_Of (Into, 3) = "y",
         "a null has code 0; its neighbours keep their places");
   end Test_Text_Nulls;

   procedure Test_Refused_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      One_A   : constant Bytes := [1, 0, 0, 0, 97];
      Into    : Text_Column (2, 2, 4, 5);
      Scratch : Codes (1 .. 2);
      Result  : Outcome;
   begin
      Data_Text
        ([5, 0, 0, 0, 97],
         Plan (Data (1, Plain_Encoding)),
         Into,
         Scratch,
         Result);
      Assert (Result.Why = Corrupt_Page, "a length past the page");
      Data_Text
        ([5, 0, 0, 0, 97, 98, 99, 100, 101],
         Plan (Data (1, Plain_Encoding)),
         Into,
         Scratch,
         Result);
      Assert (Result.Why = Corrupt_Page, "more bytes than the column holds");
      Dictionary_Text (One_A, Plan (Dictionary (1)), Into, Scratch, Result);
      Assert (Result.Ok, "a dictionary");
      Dictionary_Text (One_A, Plan (Dictionary (1)), Into, Scratch, Result);
      Assert (Result.Why = Corrupt_Page, "a second dictionary");
      Dictionary_Text (One_A, Plan (Dictionary (1, 7)), Into, Scratch, Result);
      Assert (Result.Why = Unsupported_Encoding, "a dictionary not PLAIN");
      Data_Text ([1 .. 4 => 0], Plan (Data (1, 6)), Into, Scratch, Result);
      Assert (Result.Value = 6, "DELTA_LENGTH_BYTE_ARRAY is refused, named");
   end Test_Refused_Text;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Null_Among_Values'Access, "a null among values");
      Register_Routine (T, Test_Real_Headers'Access, "real page headers");
      Register_Routine (T, Test_Bad_Headers'Access, "bad page headers");
      Register_Routine (T, Test_Required_Plain'Access, "required plain");
      Register_Routine (T, Test_Booleans'Access, "booleans");
      Register_Routine (T, Test_Dictionary_Words'Access, "dictionary words");
      Register_Routine (T, Test_Refused_Words'Access, "refused words");
      Register_Routine (T, Test_Text_Fallback'Access, "text and fallback");
      Register_Routine (T, Test_Text_Nulls'Access, "text with nulls");
      Register_Routine (T, Test_Refused_Text'Access, "refused text");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Pages");
   end Name;

end Tessera_Pages_Tests;
