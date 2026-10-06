with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;          use Tessera;
with Tessera.Columns;  use Tessera.Columns;
with Tessera.Footer;   use Tessera.Footer;
with Tessera.Pages;    use Tessera.Pages;
with Tessera_Expected;
with Tessera_Fixtures; use Tessera_Fixtures;

--  A chunk's pages in sequence: every column of the fixtures read back
--  as written, and the page sequences the machine refuses, built byte by
--  byte; then the typed columns made from what was read.

package body Tessera_Columns_Tests is

   use AUnit.Test_Cases.Registration;

   --  The first row of Read, a chunk whose first row is row Base + 1 of
   --  Want, that does not read back as Want says; 0 when none.
   function Wrong_Row
     (Read : Chunk_Read; Want : Tessera_Expected.Table; Base : Natural)
      return Natural is
   begin
      for R in 1 .. Read.Rows loop
         if Render (Read, R)
           /= Tessera_Expected.Value (Want, Base + R, Read.Number)
         then
            return R;
         end if;
      end loop;
      return 0;
   end Wrong_Row;

   --  The first chunk of the fixture Name that is refused or does not
   --  read back as its .expected.csv says, as "column" or "column: row";
   --  "" when every one does.
   function First_Wrong (Name : String) return String is
      Opened : constant Opened_File := Open (Name & ".parquet");
      Want   : constant Tessera_Expected.Table :=
        Tessera_Expected.Load ("tests/data/" & Name & ".expected.csv");
      Base   : Natural := 0;
      Read   : Chunk_Read;
   begin
      for G in 1 .. Opened.Meta.Groups loop
         for K in 1 .. Opened.Meta.Columns loop
            Read := Read_Chunk (Opened, G, K);
            if not Read.Result.Ok or else Wrong_Row (Read, Want, Base) > 0 then
               return
                 Name_Of (Read.Column) & Wrong_Row (Read, Want, Base)'Image;
            end if;
         end loop;
         Base := Base + Natural (Opened.Meta.Group (G).Rows);
      end loop;
      return "";
   end First_Wrong;

   procedure Test_Fixtures (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (First_Wrong ("flat") = "", "flat: " & First_Wrong ("flat"));
      Assert (First_Wrong ("nulls") = "", "nulls: " & First_Wrong ("nulls"));
      Assert
        (First_Wrong ("groups") = "", "groups: " & First_Wrong ("groups"));
      Assert
        (First_Wrong ("fallback") = "",
         "fallback: " & First_Wrong ("fallback"));
      Assert (First_Wrong ("runs") = "", "runs: " & First_Wrong ("runs"));
   end Test_Fixtures;

   --  A zigzag i32 field of a compact struct: field Id after Last.
   function Field (Delta_Id : Natural; Value : Natural) return Bytes
   is ([Byte (Delta_Id * 16 + 5), Byte (2 * Value)])
   with Pre => Delta_Id < 16 and then Value < 64;

   --  A PageHeader of type Kind (0 data, 2 dictionary, 1 index, 3 v2)
   --  for an uncompressed Body of Values values encoded Encoding.
   function Page
     (Kind : Natural; Values : Natural; Encoding : Natural; Body_Bytes : Bytes)
      return Bytes
   is (Field (1, Kind)
       & Field (1, Body_Bytes'Length)
       & Field (1, Body_Bytes'Length)
       & [Byte ((if Kind = 2 then 16#4C# else 16#2C#))]
       & Field (1, Values)
       & Field (1, Encoding)
       & [0, 0]
       & Body_Bytes);

   Data_Kind       : constant := 0;
   Index_Kind      : constant := 1;
   Dictionary_Kind : constant := 2;
   Version_2_Kind  : constant := 3;

   --  Two required INT32 rows, plain.
   Two_Plain : constant Bytes :=
     Page (Data_Kind, 2, Plain_Encoding, [5, 0, 0, 0, 6, 0, 0, 0]);

   Required : constant Chunk_Shape :=
     (Snappy => False, Width => Four_Bytes, Optional => False);

   --  What reading Chunk into a column of Rows rows gives.
   function Outcome_Of (Chunk : Bytes; Rows : Natural := 2) return Outcome is
      Space  : Workspace (64, Rows);
      Into   : Word_Column (Rows, 4);
      Result : Outcome;
   begin
      Read_Words (Chunk, Required, Space, Into, Result);
      return Result;
   end Outcome_Of;

   procedure Test_Page_Sequences (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Dict   : constant Bytes :=
        Page (Dictionary_Kind, 1, Plain_Encoding, [9, 0, 0, 0]);
      Result : Outcome;
   begin
      Assert (Outcome_Of (Two_Plain).Ok, "plain pages need no dictionary");
      Assert (Outcome_Of (Dict & Two_Plain).Ok, "a dictionary, then data");
      Assert
        (Outcome_Of (Two_Plain, Rows => 3).Why = Corrupt_Page,
         "bytes that end short of the rows");
      Assert
        (Outcome_Of (Dict & Dict & Two_Plain).Why = Corrupt_Page,
         "a second dictionary");
      Assert
        (Outcome_Of (Two_Plain & Dict).Why = Corrupt_Page,
         "a dictionary after the data");
      Result := Outcome_Of (Page (Version_2_Kind, 2, 0, [1 .. 8 => 0]));
      Assert
        (Result.Why = Unsupported_Page_Version and then Result.Value = 3,
         "a version 2 data page, named");
      Result := Outcome_Of (Page (Index_Kind, 2, 0, [1 .. 8 => 0]));
      Assert
        (Result.Why = Unsupported_Page_Version and then Result.Value = 1,
         "an index page, named");
      Assert
        (Outcome_Of (Two_Plain (1 .. 10)).Why = Corrupt_Page,
         "a page header cut short");
      Assert
        (Outcome_Of (Page (Data_Kind, 2, 5, [1 .. 8 => 0])).Value = 5,
         "a page's refusal is the chunk's");
      Assert
        (Outcome_Of ([1 .. 0 => 0], Rows => 0).Ok,
         "a chunk of no rows has no pages");
   end Test_Page_Sequences;

   procedure Test_Workspace (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Space  : Workspace (4, 2);
      Into   : Word_Column (2, 0);
      Result : Outcome;
   begin
      Read_Words (Two_Plain, Required, Space, Into, Result);
      Assert (Result.Why = Corrupt_Page, "a page larger than its room");
      declare
         Snappy : constant Chunk_Shape := (Required with delta Snappy => True);
         Wide   : Workspace (64, 2);
      begin
         Read_Words (Two_Plain, Snappy, Wide, Into, Result);
         Assert (Result.Why = Corrupt_Page, "plain bytes are not Snappy");
      end;
   end Test_Workspace;

   procedure Test_Typed (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Words : Word_Column (3, 0);
      B32   : Bits_32 (3);
      B64   : Bits_64 (3);
      I32   : Ints_32 (3);
      I64   : Ints_64 (3);
      Flags : Truths (3);
   begin
      Words.Valid := [True, False, True];
      Words.Value := [16#FFFF_FFFF#, 0, Unsigned_64'Last];
      To_Bits_32 (Words, B32);
      To_Bits_64 (Words, B64);
      To_Ints_32 (Words, I32);
      To_Ints_64 (Words, I64);
      To_Truths (Words, Flags);
      Assert (B32.Valid = Words.Valid, "validity carries over");
      Assert (B32.Value (3) = 16#FFFF_FFFF#, "the low 32 bits of a pattern");
      Assert (B64.Value (3) = Unsigned_64'Last, "all 64 bits");
      Assert (I32.Value (1) = -1, "a 32-bit pattern of ones is -1");
      Assert (I64.Value (1) = 16#FFFF_FFFF#, "a 64-bit pattern, positive");
      Assert (I64.Value (3) = -1, "a 64-bit pattern of ones is -1");
      Assert (Flags.Value = [True, False, True], "not zero is true");
      Assert (Signed_32 (16#8000_0000#) = Integer_32'First, "the least");
      Assert (Signed_64 (2**63) = Integer_64'First, "the least, 64");
   end Test_Typed;

   procedure Test_Text (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opened : constant Opened_File := Open ("nulls.parquet");
      Read   : constant Chunk_Read := Read_Chunk (Opened, 1, 3);
   begin
      Assert (Read.Result.Ok, "the name column reads");
      Assert (Text (Read.Text.all, Read.Text.Code (1)) = "n1", "row 1 n1");
      Assert (Text (Read.Text.all, 0) = "", "code 0 is no text");
      Assert (Text (Read.Text.all, 99) = "", "no such entry, no text");
   end Test_Text;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Fixtures'Access, "the fixtures read back");
      Register_Routine (T, Test_Page_Sequences'Access, "page sequences");
      Register_Routine (T, Test_Workspace'Access, "the workspace");
      Register_Routine (T, Test_Typed'Access, "typed columns");
      Register_Routine (T, Test_Text'Access, "text of a code");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Columns");
   end Name;

end Tessera_Columns_Tests;
