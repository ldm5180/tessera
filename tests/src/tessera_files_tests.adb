with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;        use Tessera;
with Tessera.Columns;
with Tessera.Files;  use Tessera.Files;
with Tessera.Footer; use Tessera.Footer;

--  The disk: opening each fixture, reading a column by name and type,
--  the refusals a read earns, and two tasks reading one file at once.

package body Tessera_Files_Tests is

   use AUnit.Test_Cases.Registration;

   Data : constant String := "tests/data/";

   procedure Test_Open (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      F      : File;
      Result : Outcome;
   begin
      Open (Data & "groups.parquet", F, Result);
      Assert (Result.Ok and then Is_Open (F), "groups.parquet opens");
      Assert
        (Rows (F) = 30
         and then Row_Groups (F) = 3
         and then Group_Rows (F, 2) = 10,
         "30 rows in 3 groups of 10");
      Assert
        (Column_Total (F) = 2 and then Name_Of (Column (F, 2)) = "label",
         "two columns, the second label");
      Assert (Find (F, "row") = 1 and then Find (F, "none") = 0, "find");
      Assert (Group_Rows (F, 4) = 0, "no fourth group");
      Assert
        (Chunk_Bytes (F, 1, 1) > 0 and then Chunk_Bytes (F, 4, 1) = 0,
         "a chunk's bytes on disk; none past the groups");
      Close (F);
      Assert (not Is_Open (F) and then Rows (F) = 0, "closed");
      Open (Data & "missing.parquet", F, Result);
      Assert
        (Result.Why = Cannot_Read and then not Is_Open (F),
         "a file that is not there");
      Open (Data & "zstd.parquet", F, Result);
      Assert
        (Result.Why = Unsupported_Codec and then not Is_Open (F),
         "a refused file is not open");
      Open (Data & "badmagic.parquet", F, Result);
      Assert (Result.Why = Not_Parquet, "no magic");
   end Test_Open;

   procedure Test_Read (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      F      : File;
      Result : Outcome;
      Double : Bits_64_Access;
      Day    : Ints_32_Access;
      Text   : Coded_Access;
   begin
      Open (Data & "flat.parquet", F, Result);
      Read_Bits_64 (F, 1, "double", Double, Result);
      Assert
        (Result.Ok and then Double.Rows = 10 and then Double.Valid (1),
         "double reads");
      Assert
        (Double.Value (1) = 16#4118_844C_6682_C324#,
         "its first pattern, as written");
      Read_Ints_32 (F, 1, "day", Day, Result);
      Assert (Result.Ok and then Day.Value (1) = 27_720, "a date, in days");
      Read_Coded (F, 1, "text", Text, Result);
      Assert
        (Result.Ok
         and then Tessera.Columns.Text (Text.all, Text.Code (1)) = "w517",
         "a string, by its code");
      Free (Double);
      Free (Day);
      Free (Text);
      Assert (Double = null and then Text = null, "freed");
   end Test_Read;

   procedure Test_Read_Refused (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      F      : File;
      Result : Outcome;
      Double : Bits_64_Access;
      Flags  : Truths_Access;
      Wide   : Ints_64_Access;
   begin
      Open (Data & "flat.parquet", F, Result);
      Read_Bits_64 (F, 1, "single", Double, Result);
      Assert
        (Result.Why = Wrong_Type
         and then Result.Column = 11
         and then Result.Value = Physical_Type'Pos (Float32)
         and then Double = null,
         "a FLOAT is not read as a DOUBLE");
      Read_Bits_64 (F, 1, "nothing", Double, Result);
      Assert (Result.Why = No_Such_Column, "no such column");
      Read_Bits_64 (F, 2, "double", Double, Result);
      Assert
        (Result.Why = No_Such_Row_Group and then Result.Value = 2,
         "no second row group");
      Close (F);
      Read_Truths (F, 1, "flag", Flags, Result);
      Assert (Result.Why = No_Such_Row_Group, "a closed file has none");
      Open (Data & "v2pages.parquet", F, Result);
      Read_Ints_64 (F, 1, "x", Wide, Result);
      Assert
        (Result.Why = Unsupported_Page_Version
         and then Result.Column = 1
         and then Result.Value = 3
         and then Wide = null,
         "a version 2 page, its column named");
   end Test_Read_Refused;

   --  Reads every row group's x of groups.parquet's "row" column, again
   --  and again, from a File another task reads at the same time.
   task type Reader (F : access constant File) is
      entry Total (Sum : out Integer_64; Ok : out Boolean);
   end Reader;

   Passes : constant := 20;

   task body Reader is
      Rows_Read : Ints_64_Access;
      Result    : Outcome;
      Sum       : Integer_64 := 0;
      Ok        : Boolean := True;
   begin
      for Pass in 1 .. Passes loop
         for G in 1 .. Row_Groups (F.all) loop
            Read_Ints_64 (F.all, G, "row", Rows_Read, Result);
            Ok := Ok and then Result.Ok;
            if Result.Ok then
               Sum := Sum + Rows_Read.Value (Rows_Read.Rows);
            end if;
            Free (Rows_Read);
         end loop;
      end loop;
      accept Total (Sum : out Integer_64; Ok : out Boolean) do
         Sum := Reader.Sum;
         Ok := Reader.Ok;
      end Total;
   end Reader;

   procedure Test_Two_Tasks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      F      : aliased File;
      Result : Outcome;
   begin
      Open (Data & "groups.parquet", F, Result);
      declare
         One, Two     : Reader (F'Access);
         Sum_1, Sum_2 : Integer_64;
         Ok_1, Ok_2   : Boolean;
      begin
         One.Total (Sum_1, Ok_1);
         Two.Total (Sum_2, Ok_2);
         --  The last row of each group: 9 + 19 + 29, twenty times.
         Assert
           (Ok_1
            and then Ok_2
            and then Sum_1 = 57 * Passes
            and then Sum_2 = Sum_1,
            "two tasks read the same rows:"
            & Sum_1'Image
            & Sum_2'Image
            & Ok_1'Image
            & Ok_2'Image);
      end;
   end Test_Two_Tasks;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Open'Access, "open");
      Register_Routine (T, Test_Read'Access, "read");
      Register_Routine (T, Test_Read_Refused'Access, "refused reads");
      Register_Routine (T, Test_Two_Tasks'Access, "two tasks, one file");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Files");
   end Name;

end Tessera_Files_Tests;
