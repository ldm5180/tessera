with AUnit.Assertions; use AUnit.Assertions;

with Tessera;        use Tessera;
with Tessera.Snappy; use Tessera.Snappy;

--  Snappy's raw block: the elements, the copy that overlaps its own
--  output, and every way a block can lie about itself.

package body Tessera_Snappy_Tests is

   use AUnit.Test_Cases.Registration;

   function Text (B : Bytes) return String is
      S : String (1 .. B'Length);
   begin
      for K in S'Range loop
         S (K) := Character'Val (B (B'First + K - 1));
      end loop;
      return S;
   end Text;

   function Counting (N : Positive) return Bytes is
      B : Bytes (1 .. N);
   begin
      for K in B'Range loop
         B (K) := Byte (K - 1);
      end loop;
      return B;
   end Counting;

   procedure Test_Overlapping_Copy
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Length 8; a literal "ab"; a copy of 6 at offset 2.
      Input  : constant Bytes := [8, 16#04#, 97, 98, 16#09#, 2];
      Output : Bytes (1 .. 8) := [others => 0];
      Last   : Buffer_Count;
      Result : Outcome;
   begin
      Decompress (Input, Output, Last, Result);
      Assert (Result.Ok and then Last = 8, "eight bytes out");
      Assert (Text (Output) = "abababab", "the copy repeats its own output");
   end Test_Overlapping_Copy;

   --  "tessera " twelve times, the bytes 0 .. 69, "tessera tessera", as
   --  pyarrow compresses it: a literal, two copies with two-byte
   --  offsets, a literal whose length follows its tag, and a copy.
   Pyarrow_Block : constant Bytes :=
     [16#B5#,
      16#01#,
      16#1C#,
      16#74#,
      16#65#,
      16#73#,
      16#73#,
      16#65#,
      16#72#,
      16#61#,
      16#20#,
      16#FE#,
      16#08#,
      16#00#,
      16#5E#,
      16#08#,
      16#00#,
      16#F0#,
      16#54#]
     & Counting (70)
     & [16#74#,
        16#65#,
        16#73#,
        16#73#,
        16#65#,
        16#72#,
        16#61#,
        16#20#,
        16#74#,
        16#65#,
        16#73#,
        16#73#,
        16#65#,
        16#72#,
        16#61#];

   procedure Test_Pyarrow_Block (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Want   : constant String :=
        "tessera tessera tessera tessera tessera tessera "
        & "tessera tessera tessera tessera tessera tessera ";
      Output : Bytes (1 .. 181) := [others => 0];
      Last   : Buffer_Count;
      Result : Outcome;
      Length : Buffer_Count;
      Ok     : Boolean;
   begin
      Declared_Length (Pyarrow_Block, Length, Ok);
      Assert (Ok and then Length = 181, "B5 01 declares 181");
      Decompress (Pyarrow_Block, Output, Last, Result);
      Assert (Result.Ok and then Last = 181, "all 181 bytes");
      Assert (Text (Output (1 .. 96)) = Want, "the repeats");
      Assert (Output (97 .. 166) = Counting (70), "the literal");
      Assert (Text (Output (167 .. 181)) = "tessera tessera", "the tail");
   end Test_Pyarrow_Block;

   procedure Test_Long_Offsets (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Length 6; literal "xyz"; a copy of 3 with a four-byte offset 3.
      Input  : constant Bytes :=
        [6, 16#08#, 120, 121, 122, 16#0B#, 3, 0, 0, 0];
      Output : Bytes (1 .. 6) := [others => 0];
      Last   : Buffer_Count;
      Result : Outcome;
   begin
      Decompress (Input, Output, Last, Result);
      Assert (Result.Ok and then Text (Output) = "xyzxyz", "copy, offset 4B");
   end Test_Long_Offsets;

   --  What decompressing Input into a buffer of Room bytes gives.
   function Outcome_Of (Input : Bytes; Room : Natural := 8) return Outcome is
      Output : Bytes (1 .. Room) := [others => 0];
      Last   : Buffer_Count;
      Result : Outcome;
   begin
      Decompress (Input, Output, Last, Result);
      return Result;
   end Outcome_Of;

   procedure Test_Corrupt (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Outcome_Of ([4, 16#04#, 97, 98, 16#09#, 3]).Why = Corrupt_Page,
         "a copy reaching before the output's start");
      Assert
        (not Outcome_Of ([4, 16#04#, 97, 98, 16#05#, 0]).Ok,
         "a copy from offset 0");
      Assert
        (not Outcome_Of ([2, 16#08#, 97, 98, 99]).Ok,
         "a literal past the declared length");
      Assert
        (not Outcome_Of ([3, 16#08#, 97, 98]).Ok, "a literal past the input");
      Assert
        (not Outcome_Of ([4, 16#04#, 97, 98]).Ok,
         "a block that ends short of its length");
      Assert
        (not Outcome_Of ([2, 16#04#, 97, 98, 16#04#]).Ok,
         "bytes after the declared length");
      Assert
        (not Outcome_Of ([9, 16#20#, 97], Room => 8).Ok,
         "more than the output holds");
      Assert (not Outcome_Of ([2, 16#F0#]).Ok, "a literal length cut short");
      Assert
        (not Outcome_Of ([2, 16#04#, 97, 98, 16#0A#, 2]).Ok,
         "a copy offset cut short");
      Assert (not Outcome_Of ([16#80#]).Ok, "a length cut short");
      Assert (Outcome_Of ([0]).Ok, "an empty block");
   end Test_Corrupt;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Overlapping_Copy'Access, "overlapping copy");
      Register_Routine (T, Test_Pyarrow_Block'Access, "a pyarrow block");
      Register_Routine (T, Test_Long_Offsets'Access, "four-byte offsets");
      Register_Routine (T, Test_Corrupt'Access, "corrupt blocks");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Snappy");
   end Name;

end Tessera_Snappy_Tests;
