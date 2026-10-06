--  Tessera: reads the flat-table subset of Apache Parquet that pyarrow
--  writes.  The root holds what every decoder shares; the decoders are
--  its children under src/core, the file reader under src/app.

package Tessera
  with Pure, SPARK_Mode
is

end Tessera;
