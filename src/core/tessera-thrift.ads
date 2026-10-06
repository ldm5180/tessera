with Interfaces; use Interfaces;

--  The Thrift compact protocol, read from a byte buffer through a cursor.
--  Parquet's footer and page headers are compact-protocol structs.  Every
--  read is total: it either moves the cursor forward within the buffer
--  and gives a value, or turns the cursor's Ok off and leaves the value
--  at its default.  A cursor that is not Ok stays so, and every later
--  read through it gives nothing, so a caller checks once at the end.

package Tessera.Thrift
  with SPARK_Mode
is

   --  The wire types a field header or a list header names, in the order
   --  of their codes 1 .. 12.  The two booleans carry the value itself.
   type Wire_Kind is
     (Bool_True,
      Bool_False,
      I8,
      I16,
      I32,
      I64,
      Double,
      Binary,
      List,
      Set,
      Map,
      Struct);

   --  Where the next read starts, as an offset past the buffer's first
   --  byte, and whether every read so far succeeded.
   type Cursor is record
      Pos : Buffer_Count := 0;
      Ok  : Boolean := True;
   end record;

   --  True when C points at a byte of Input or just past its last.
   function Within (C : Cursor; Input : Bytes) return Boolean
   is (C.Pos <= Input'Length);

   --  True when C may be read from: Ok, and within Input.  A cursor that
   --  is not Ok is sound too; nothing is read through it.
   function Sound (C : Cursor; Input : Bytes) return Boolean
   is (not C.Ok or else Within (C, Input));

   --  How many bytes of Input are past C.
   function Left (C : Cursor; Input : Bytes) return Buffer_Count
   is (Input'Length - C.Pos)
   with Pre => Within (C, Input);

   --  A run of bytes inside a buffer: Length bytes from offset Start.
   type Span is record
      Start  : Buffer_Count := 0;
      Length : Buffer_Count := 0;
   end record;

   --  True when every byte of S is inside Input.
   function Inside (S : Span; Input : Bytes) return Boolean
   is (S.Start <= Input'Length and then S.Length <= Input'Length - S.Start);

   --  One field header: the end of a struct, or a field's id and type.
   type Field_Header is record
      Stop : Boolean := True;
      Id   : Integer_16 := 0;
      Kind : Wire_Kind := Struct;
   end record;

   --  One list (or set) header: how many elements, of which type.
   type List_Header is record
      Count   : Buffer_Count := 0;
      Element : Wire_Kind := Struct;
   end record;

   --  The deepest nesting of structs, lists and maps a skip walks through.
   Max_Depth : constant := 32;

   --  The postcondition every read carries: a failed cursor stays
   --  failed, and a cursor that is still Ok moved forward within Input.
   function Advanced (Before, After : Cursor; Input : Bytes) return Boolean
   is (Sound (After, Input)
       and then (if After.Ok then Before.Ok and then After.Pos > Before.Pos));

   procedure Read_Byte (Input : Bytes; C : in out Cursor; Value : out Byte)
   with Post => Advanced (C'Old, C, Input);

   --  An unsigned varint: 7 bits a byte, low bits first, high bit "more";
   --  at most ten bytes, and nothing past 64 bits.
   procedure Read_Varint
     (Input : Bytes; C : in out Cursor; Value : out Unsigned_64)
   with Post => Advanced (C'Old, C, Input);

   --  A zigzag varint: 0, -1, 1, -2, ... as 0, 1, 2, 3, ...
   procedure Read_Zigzag
     (Input : Bytes; C : in out Cursor; Value : out Integer_64)
   with Post => Advanced (C'Old, C, Input);

   --  A zigzag varint that must fit 32 bits.
   procedure Read_I32
     (Input : Bytes; C : in out Cursor; Value : out Integer_32)
   with Post => Advanced (C'Old, C, Input);

   --  A field header.  Last_Id is the id of the field before it in the
   --  same struct (0 at the start), and becomes this field's id.
   procedure Read_Field_Header
     (Input   : Bytes;
      C       : in out Cursor;
      Last_Id : in out Integer_16;
      Header  : out Field_Header)
   with Post => Advanced (C'Old, C, Input);

   --  A binary (or string): a varint length, then that many bytes, which
   --  Value spans and the cursor steps over.
   procedure Read_Binary (Input : Bytes; C : in out Cursor; Value : out Span)
   with Post => Advanced (C'Old, C, Input) and then Inside (Value, Input);

   --  A list or set header.  Every element takes at least one byte, so a
   --  count past the bytes left is refused here.
   procedure Read_List_Header
     (Input : Bytes; C : in out Cursor; Header : out List_Header)
   with
     Post =>
       Advanced (C'Old, C, Input)
       and then (if C.Ok then Header.Count <= Left (C, Input));

   --  Steps over one value of type Kind, whatever it holds, down to
   --  Max_Depth levels of nesting.
   procedure Skip (Input : Bytes; C : in out Cursor; Kind : Wire_Kind)
   with Post => Sound (C, Input) and then (if C.Ok then C'Old.Ok);

end Tessera.Thrift;
