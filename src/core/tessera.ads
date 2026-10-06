with Interfaces;

--  Tessera: reads the flat-table subset of Apache Parquet that pyarrow
--  writes.  The root holds what every decoder shares: the byte buffer a
--  decoder reads, indexed by offset from its first element so a slice of
--  any buffer reads the same way.  The decoders are its children under
--  src/core, the file reader under src/app.

package Tessera
  with Pure, SPARK_Mode
is

   subtype Byte is Interfaces.Unsigned_8;

   --  The largest buffer a decoder indexes, 256 MiB: past any column
   --  chunk or footer a flat table carries, and small enough that a few
   --  multiples of it still fit an Integer.
   Max_Buffer : constant := 2**28;

   subtype Buffer_Index is Positive range 1 .. Max_Buffer;
   subtype Buffer_Count is Natural range 0 .. Max_Buffer;

   type Bytes is array (Buffer_Index range <>) of Byte;

   --  The byte Offset places past Input's first.
   function Byte_At (Input : Bytes; Offset : Buffer_Count) return Byte
   is (Input (Input'First + Offset))
   with Pre => Offset < Input'Length;

end Tessera;
