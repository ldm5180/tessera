--  Snappy's raw block format, the codec pyarrow compresses every page
--  with: a varint length, then elements, each a literal run of bytes or
--  a copy of bytes already written (which may overlap its own output).
--  The element reader is an sml machine; the copies are plain loops.
--  Every length and offset is checked against both buffers first: a
--  copy reaching before the output's start, an element past the input's
--  end or the declared length, or a block that ends short of it, is the
--  refusal Corrupt_Page.

package Tessera.Snappy
  with SPARK_Mode
is

   --  The length Input declares it decompresses to; Ok False when its
   --  leading varint is broken or past a buffer.
   procedure Declared_Length
     (Input : Bytes; Length : out Buffer_Count; Ok : out Boolean);

   --  Decompresses Input into Output.  Last is how many bytes of Output
   --  were written: all of the declared length, when Result is Ok.
   --  Output must have room for the declared length.
   procedure Decompress
     (Input  : Bytes;
      Output : in out Bytes;
      Last   : out Buffer_Count;
      Result : out Outcome)
   with Post => Last <= Output'Length;

end Tessera.Snappy;
