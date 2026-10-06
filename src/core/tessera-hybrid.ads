with Interfaces; use Interfaces;

--  The RLE/bit-packed hybrid: definition levels and dictionary indices
--  are written as a sequence of runs.  Each run begins with a varint
--  header.  An even header is a repeated run: header / 2 copies of one
--  value, which follows in the fewest whole bytes that hold Width bits.
--  An odd header is a bit-packed run of (header / 2) * 8 values, Width
--  bits each, packed low bit first.  The last packed run may hold more
--  values than are asked for; the spare ones are dropped.

package Tessera.Hybrid
  with SPARK_Mode
is

   subtype Bit_Width is Natural range 0 .. 32;

   type Codes is array (Buffer_Index range <>) of Unsigned_32;

   --  Decodes Count values of Width bits from Input into the first Count
   --  elements of Values.  A run past the input, a repeated value wider
   --  than Width, or input that ends before Count values is the refusal
   --  Corrupt_Page.
   procedure Decode
     (Input  : Bytes;
      Width  : Bit_Width;
      Count  : Buffer_Count;
      Values : in out Codes;
      Result : out Outcome)
   with Pre => Count <= Values'Length;

end Tessera.Hybrid;
