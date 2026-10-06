with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;        use Tessera;
with Tessera.Thrift; use Tessera.Thrift;

--  The compact protocol's byte rules: what each read gives for which
--  bytes, where it leaves the cursor, and where it refuses.

package body Tessera_Thrift_Tests is

   use AUnit.Test_Cases.Registration;

   procedure Test_Varint_300 (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Bytes := [16#AC#, 16#02#];
      C     : Cursor;
      V     : Unsigned_64;
   begin
      Read_Varint (Input, C, V);
      Assert (C.Ok, "the varint reads");
      Assert (V = 300, "AC 02 is 300");
      Assert (C.Pos = 2, "the cursor is left at 2");
   end Test_Varint_300;

   procedure Test_Varint_Edges (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Max      : constant Bytes :=
        [16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#01#];
      Too_Wide : constant Bytes :=
        [16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#FF#,
         16#02#];
      Runaway  : constant Bytes := [1 .. 11 => 16#80#];
      Short    : constant Bytes := [16#80#];
      C        : Cursor;
      V        : Unsigned_64;
   begin
      Read_Varint ([16#7F#], C, V);
      Assert (C.Ok and then V = 127 and then C.Pos = 1, "one byte");
      C := (others => <>);
      Read_Varint (Max, C, V);
      Assert (C.Ok and then V = Unsigned_64'Last, "ten bytes, 64 bits");
      C := (others => <>);
      Read_Varint (Too_Wide, C, V);
      Assert (not C.Ok and then V = 0, "past 64 bits is refused");
      C := (others => <>);
      Read_Varint (Runaway, C, V);
      Assert (not C.Ok, "an eleventh byte is refused");
      C := (others => <>);
      Read_Varint (Short, C, V);
      Assert (not C.Ok and then V = 0, "a varint cut short is refused");
      Read_Varint ([16#01#], C, V);
      Assert (not C.Ok and then V = 0, "a failed cursor reads nothing");
   end Test_Varint_Edges;

   procedure Test_Zigzag (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Bytes :=
        [0, 1, 2, 3, 16#FE#, 16#FF#, 16#FF#, 16#FF#, 16#0F#];
      C     : Cursor;
      V     : Integer_64;
      I     : Integer_32;
   begin
      Read_Zigzag (Input, C, V);
      Assert (V = 0, "0 is 0");
      Read_Zigzag (Input, C, V);
      Assert (V = -1, "1 is -1");
      Read_Zigzag (Input, C, V);
      Assert (V = 1, "2 is 1");
      Read_I32 (Input, C, I);
      Assert (C.Ok and then I = -2, "3 is -2");
      Read_I32 (Input, C, I);
      Assert (C.Ok and then I = Integer_32'Last, "FE FF FF FF 0F is 2**31-1");
      C := (others => <>);
      Read_I32 ([16#80#, 16#80#, 16#80#, 16#80#, 16#10#], C, I);
      Assert (not C.Ok and then I = 0, "past 32 bits is refused");
   end Test_Zigzag;

   procedure Test_Field_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Field 1 i32, field 3 binary (delta 2), field 300 by long form
      --  (zigzag 600 = D8 04) of type struct, then a true, then stop.
      Input : constant Bytes :=
        [16#15#, 16#28#, 16#0C#, 16#D8#, 16#04#, 16#11#, 0];
      C     : Cursor;
      Last  : Integer_16 := 0;
      H     : Field_Header;
   begin
      Read_Field_Header (Input, C, Last, H);
      Assert (not H.Stop and then H.Id = 1 and then H.Kind = I32, "1 i32");
      Read_Field_Header (Input, C, Last, H);
      Assert (H.Id = 3 and then H.Kind = Binary, "delta 2 is field 3");
      Read_Field_Header (Input, C, Last, H);
      Assert
        (H.Id = 300 and then H.Kind = Struct and then Last = 300,
         "long form 300 struct");
      Read_Field_Header (Input, C, Last, H);
      Assert (H.Id = 301 and then H.Kind = Bool_True, "the type is the value");
      Read_Field_Header (Input, C, Last, H);
      Assert (C.Ok and then H.Stop and then C.Pos = 7, "0 ends the struct");
   end Test_Field_Header;

   procedure Test_Field_Header_Refused
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      C    : Cursor;
      Last : Integer_16 := 0;
      H    : Field_Header;
   begin
      Read_Field_Header ([16#1D#], C, Last, H);
      Assert (not C.Ok, "type 13 is no type");
      C := (others => <>);
      Read_Field_Header ([16#10#], C, Last, H);
      Assert (not C.Ok, "type 0 with a delta is no type");
      C := (others => <>);
      Last := Integer_16'Last;
      Read_Field_Header ([16#15#], C, Last, H);
      Assert (not C.Ok, "a delta past the largest id");
      C := (others => <>);
      Last := 0;
      Read_Field_Header ([16#05#, 16#80#, 16#80#, 16#04#], C, Last, H);
      Assert (not C.Ok, "a long-form id past 16 bits");
      C := (others => <>);
      Read_Field_Header ([1 .. 0 => 0], C, Last, H);
      Assert (not C.Ok and then H.Stop, "no byte at all");
   end Test_Field_Header_Refused;

   procedure Test_Binary (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Input : constant Bytes := [16#03#, 65, 66, 67, 16#05#, 1];
      C     : Cursor;
      S     : Span;
   begin
      Read_Binary (Input, C, S);
      Assert
        (C.Ok and then S.Start = 1 and then S.Length = 3 and then C.Pos = 4,
         "three bytes after the length");
      Assert (Byte_At (Input, S.Start) = 65, "the span starts at the text");
      Read_Binary (Input, C, S);
      Assert (not C.Ok and then S.Length = 0, "a length past the bytes left");
   end Test_Binary;

   procedure Test_List_Header (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Short : constant Bytes := [16#35#, 2, 4, 6];
      Long  : constant Bytes := [16#F8#, 16#10#] & [1 .. 16 => 0];
      C     : Cursor;
      H     : List_Header;
   begin
      Read_List_Header (Short, C, H);
      Assert (C.Ok and then H.Count = 3 and then H.Element = I32, "3 x i32");
      C := (others => <>);
      Read_List_Header (Long, C, H);
      Assert
        (C.Ok and then H.Count = 16 and then H.Element = Binary,
         "the long form's count follows as a varint");
      C := (others => <>);
      Read_List_Header ([16#35#, 2], C, H);
      Assert (not C.Ok, "more elements than bytes left");
      C := (others => <>);
      Read_List_Header ([16#F5#, 16#05#, 1], C, H);
      Assert (not C.Ok, "a long count past the bytes left");
      C := (others => <>);
      Read_List_Header ([16#0E#], C, H);
      Assert (not C.Ok, "element type 14 is no type");
   end Test_List_Header;

   --  Skips one value of Kind in Input and says where the cursor ended.
   function Skipped (Input : Bytes; Kind : Wire_Kind) return Cursor is
      C : Cursor;
   begin
      Skip (Input, C, Kind);
      return C;
   end Skipped;

   procedure Test_Skip_Scalars (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      C : Cursor;
   begin
      C := Skipped ([1 .. 0 => 0], Bool_True);
      Assert (C.Ok and then C.Pos = 0, "a field's boolean takes no byte");
      C := Skipped ([7], I8);
      Assert (C.Ok and then C.Pos = 1, "a byte is one byte");
      C := Skipped ([16#AC#, 2], I64);
      Assert (C.Ok and then C.Pos = 2, "an integer is its varint");
      C := Skipped ([1 .. 8 => 0], Double);
      Assert (C.Ok and then C.Pos = 8, "a double is eight bytes");
      C := Skipped ([1 .. 7 => 0], Double);
      Assert (not C.Ok, "a double cut short");
      C := Skipped ([2, 0, 0], Binary);
      Assert (C.Ok and then C.Pos = 3, "a binary is its length and bytes");
      C := (Pos => 5, Ok => True);
      Skip ([7], C, I8);
      Assert (not C.Ok, "a cursor past its buffer skips nothing");
   end Test_Skip_Scalars;

   procedure Test_Skip_Containers (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  struct { 1: i32 5; 2: list<struct { 1: bool true }> of 2;
      --           3: map<binary, i64> { "a" : 1 }; 4: set<bool> {t, f} }
      Nested : constant Bytes :=
        [16#15#,
         16#0A#,
         16#19#,
         16#2C#,
         16#11#,
         0,
         16#11#,
         0,
         16#1B#,
         16#01#,
         16#86#,
         16#01#,
         65,
         16#02#,
         16#1A#,
         16#21#,
         1,
         2,
         0,
         99];
      C      : Cursor;
   begin
      C := Skipped (Nested, Struct);
      Assert
        (C.Ok and then C.Pos = 19, "the whole struct, not the byte after");
      C := Skipped ([16#09#], List);
      Assert (C.Ok and then C.Pos = 1, "an empty list is its header");
      C := Skipped ([0], Map);
      Assert (C.Ok and then C.Pos = 1, "an empty map is its size");
      C := Skipped ([16#01#, 16#D6#, 0, 0], Map);
      Assert (not C.Ok, "a map's types must be types");
      C := Skipped ([16#05#, 16#88#, 0, 0], Map);
      Assert (not C.Ok, "more entries than bytes left");
      C := Skipped ([16#15#], Struct);
      Assert (not C.Ok, "a struct cut short");
   end Test_Skip_Containers;

   procedure Test_Skip_Depth (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      --  Structs nested by field 1 of type struct, each closed by a 0.
      function Nest (Levels : Positive) return Bytes
      is ([1 .. Levels - 1 => 16#1C#] & [1 .. Levels => 0]);
   begin
      Assert (Skipped (Nest (Max_Depth), Struct).Ok, "Max_Depth levels");
      Assert
        (not Skipped (Nest (Max_Depth + 1), Struct).Ok,
         "one level past Max_Depth is refused");
   end Test_Skip_Depth;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Varint_300'Access, "varint 300");
      Register_Routine (T, Test_Varint_Edges'Access, "varint edges");
      Register_Routine (T, Test_Zigzag'Access, "zigzag");
      Register_Routine (T, Test_Field_Header'Access, "field headers");
      Register_Routine
        (T, Test_Field_Header_Refused'Access, "field headers refused");
      Register_Routine (T, Test_Binary'Access, "binary");
      Register_Routine (T, Test_List_Header'Access, "list headers");
      Register_Routine (T, Test_Skip_Scalars'Access, "skip scalars");
      Register_Routine (T, Test_Skip_Containers'Access, "skip containers");
      Register_Routine (T, Test_Skip_Depth'Access, "skip depth");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Thrift");
   end Name;

end Tessera_Thrift_Tests;
