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

   --  The most columns a file may have, and a column's number in it.
   Max_Columns : constant := 256;

   subtype Column_Count is Natural range 0 .. Max_Columns;
   subtype Column_Number is Column_Count range 1 .. Max_Columns;

   --  Why a file, or a column of it, is not read: a fault in the file, or
   --  a feature outside the subset tessera reads.
   type Refusal is
     (Not_Parquet,
      Truncated,
      Corrupt_Footer,
      Nested_Schema,
      Unsupported_Codec,
      Unsupported_Encoding,
      Unsupported_Type,
      Encrypted,
      Too_Large);

   --  What a decoder made of its input: Ok, or the refusal, the column it
   --  concerns (0 for the whole file) and the offending value from the
   --  file when there is one (Valued).
   type Outcome is record
      Ok     : Boolean := True;
      Why    : Refusal := Refusal'First;
      Column : Column_Count := 0;
      Value  : Interfaces.Integer_64 := 0;
      Valued : Boolean := False;
   end record;

   Done : constant Outcome := (others => <>);

   function Refused (Why : Refusal; Column : Column_Count := 0) return Outcome
   is ((Ok => False, Why => Why, Column => Column, others => <>));

   function Refused_With
     (Why : Refusal; Column : Column_Count; Value : Interfaces.Integer_64)
      return Outcome
   is ((False, Why, Column, Value, Valued => True));

   --  The byte Offset places past Input's first.
   function Byte_At (Input : Bytes; Offset : Buffer_Count) return Byte
   is (Input (Input'First + Offset))
   with Pre => Offset < Input'Length;

end Tessera;
