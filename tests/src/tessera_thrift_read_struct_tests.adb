with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;        use Tessera;
with Tessera.Thrift; use Tessera.Thrift;
with Tessera.Thrift.Read_Struct;

--  The struct reader's walk: a known field handed over, an unknown one
--  skipped whatever it holds, and a struct that does not end refused.

package body Tessera_Thrift_Read_Struct_Tests is

   use AUnit.Test_Cases.Registration;

   --  The test struct: field 1 an i32 it reads; every other field
   --  skipped.  Reads counts how often Read_Field was called.
   type Pair is record
      Value : Integer_32 := 0;
      Reads : Natural := 0;
   end record;

   function Known (H : Field_Header) return Boolean
   is (H.Id = 1 and then H.Kind = I32);

   procedure Read_Field
     (Input : Bytes; C : in out Cursor; Into : in out Pair; H : Field_Header)
   is
      pragma Unreferenced (H);
   begin
      Read_I32 (Input, C, Into.Value);
      Into.Reads := Into.Reads + 1;
   end Read_Field;

   procedure Read_Pair is new Read_Struct (Pair, Known, Read_Field);

   function Read (Input : Bytes; C : in out Cursor) return Pair is
      P : Pair;
   begin
      Read_Pair (Input, C, P);
      return P;
   end Read;

   procedure Test_Known_And_Unknown
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Field 2 binary "ab", field 1 i32 (by long form) 7, field 3 a
      --  nested struct holding a true, stop, then a byte past it.
      Input : constant Bytes :=
        [16#28#, 2, 97, 98, 16#05#, 16#02#, 16#0E#, 16#2C#, 16#11#, 0, 0, 99];
      C     : Cursor;
      P     : Pair;
   begin
      P := Read (Input, C);
      Assert (C.Ok and then C.Pos = 11, "the struct and nothing after");
      Assert (P.Value = 7 and then P.Reads = 1, "field 1 read once, as 7");
   end Test_Known_And_Unknown;

   procedure Test_Refused (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      C : Cursor;
      P : Pair;
   begin
      P := Read ([16#15#, 16#0E#], C);
      Assert (not C.Ok and then P.Value = 7, "no stop: refused after field 1");
      C := (others => <>);
      P := Read ([16#15#, 16#80#], C);
      Assert (not C.Ok and then P.Value = 0, "a field that cannot be read");
      C := (others => <>);
      P := Read ([16#1D#, 0], C);
      Assert (not C.Ok and then P.Reads = 0, "a header that is no header");
      C := (Pos => 0, Ok => False);
      P := Read ([0], C);
      Assert
        (not C.Ok and then C.Pos = 0 and then P.Reads = 0,
         "a failed cursor reads nothing");
   end Test_Refused;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine
        (T, Test_Known_And_Unknown'Access, "known and unknown fields");
      Register_Routine (T, Test_Refused'Access, "refused structs");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Thrift.Read_Struct");
   end Name;

end Tessera_Thrift_Read_Struct_Tests;
