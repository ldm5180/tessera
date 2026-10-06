with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;        use Tessera;
with Tessera.Hybrid; use Tessera.Hybrid;

--  The RLE/bit-packed hybrid: repeated runs, packed runs at each width
--  that matters, the last run's spare values, and the runs that lie.

package body Tessera_Hybrid_Tests is

   use AUnit.Test_Cases.Registration;

   procedure Test_Packed_Width_3 (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Input  : constant Bytes := [16#03#, 16#88#, 16#C6#, 16#FA#];
      Values : Codes (1 .. 8) := [others => 99];
      Result : Outcome;
   begin
      Decode (Input, 3, 8, Values, Result);
      Assert (Result.Ok, "the run decodes");
      Assert
        ((for all K in Values'Range => Values (K) = Unsigned_32 (K - 1)),
         "0 through 7");
   end Test_Packed_Width_3;

   --  Values packed Width bits each, low bit first, as one bit-packed
   --  run behind its header (the count of values a multiple of eight).
   function Pack (V : Codes; Width : Bit_Width) return Bytes is
      Groups : constant Natural := V'Length / 8;
      Out_B  : Bytes (1 .. 1 + Groups * Width) := [others => 0];
      Bit    : Natural := 0;
   begin
      Out_B (1) := Byte (Groups * 2 + 1);
      for X of V loop
         for B in 0 .. Width - 1 loop
            if (Shift_Right (X, B) and 1) = 1 then
               Out_B (2 + (Bit + B) / 8) :=
                 Out_B (2 + (Bit + B) / 8) or Shift_Left (1, (Bit + B) mod 8);
            end if;
         end loop;
         Bit := Bit + Width;
      end loop;
      return Out_B;
   end Pack;

   procedure Test_Every_Width (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Want   : Codes (1 .. 16);
      Got    : Codes (1 .. 16);
      Result : Outcome;
   begin
      for Width in Bit_Width range 1 .. 32 loop
         for K in Want'Range loop
            Want (K) :=
              (if Width = 32
               then Unsigned_32'Last - Unsigned_32 (K)
               else Unsigned_32 (K * 7919) mod 2**Width);
         end loop;
         Got := [others => 0];
         Decode (Pack (Want, Width), Width, 16, Got, Result);
         Assert
           (Result.Ok and then Got = Want, "packed at width" & Width'Image);
      end loop;
   end Test_Every_Width;

   procedure Test_Repeated (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Values : Codes (1 .. 10) := [others => 99];
      Result : Outcome;
   begin
      Decode ([16#14#, 1], 1, 10, Values, Result);
      Assert
        (Result.Ok and then (for all V of Values => V = 1),
         "ten ones at width 1");
      Decode ([16#0A#, 16#2C#, 16#01#], 9, 5, Values, Result);
      Assert
        (Result.Ok and then (for all K in 1 .. 5 => Values (K) = 300),
         "a nine-bit value in two bytes");
      Decode ([16#04#, 16#FF#, 16#FF#, 16#FF#, 16#FF#], 32, 2, Values, Result);
      Assert
        (Result.Ok and then Values (2) = Unsigned_32'Last,
         "a 32-bit value in four bytes");
      Decode ([16#08#, 0, 16#03#, 16#3F#], 3, 6, Values, Result);
      Assert
        (Result.Ok
         and then Values (4) = 0
         and then Values (5) = 7
         and then Values (6) = 7,
         "a repeated run that stops short of Count, then a packed one");
   end Test_Repeated;

   procedure Test_Width_Zero (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Values : Codes (1 .. 12) := [others => 99];
      Result : Outcome;
   begin
      Decode ([16#08#, 16#03#], 0, 12, Values, Result);
      Assert
        (Result.Ok and then (for all V of Values => V = 0),
         "width 0: every value is 0 and takes no byte");
   end Test_Width_Zero;

   procedure Test_Spare_Values (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Values : Codes (1 .. 8) := [others => 99];
      Result : Outcome;
   begin
      Decode ([16#03#, 16#88#, 16#C6#, 16#FA#], 3, 5, Values, Result);
      Assert
        (Result.Ok and then Values (5) = 4 and then Values (6) = 99,
         "the last run's spare values are dropped");
      Values := [others => 99];
      Decode ([16#03#, 16#88#], 3, 2, Values, Result);
      Assert
        (Result.Ok and then Values (1) = 0 and then Values (2) = 1,
         "a last run cut after the values asked for");
   end Test_Spare_Values;

   procedure Test_Corrupt (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Values : Codes (1 .. 8) := [others => 0];
      Result : Outcome;
   begin
      Decode ([16#03#, 16#88#], 3, 5, Values, Result);
      Assert (Result.Why = Corrupt_Page, "a packed run past the input");
      Decode ([16#04#, 2], 1, 2, Values, Result);
      Assert (not Result.Ok, "a repeated value wider than its width");
      Decode ([16#04#, 1], 1, 5, Values, Result);
      Assert (not Result.Ok, "the input ends before Count values");
      Decode ([16#04#], 1, 2, Values, Result);
      Assert (not Result.Ok, "a repeated run without its value");
      Decode ([16#80#], 1, 2, Values, Result);
      Assert (not Result.Ok, "a header cut short");
      Decode ([1 .. 0 => 0], 1, 0, Values, Result);
      Assert (Result.Ok, "nothing asked, nothing read");
   end Test_Corrupt;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Packed_Width_3'Access, "packed, width 3");
      Register_Routine (T, Test_Every_Width'Access, "every width");
      Register_Routine (T, Test_Repeated'Access, "repeated runs");
      Register_Routine (T, Test_Width_Zero'Access, "width 0");
      Register_Routine (T, Test_Spare_Values'Access, "spare values");
      Register_Routine (T, Test_Corrupt'Access, "corrupt runs");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Hybrid");
   end Name;

end Tessera_Hybrid_Tests;
