with Tessera.Files;

--  Reading one column of an open file in every row group, timed, and the
--  line that reports it.

package Bench_Columns is

   --  Reads column Name of F in every row group and prints its type,
   --  the rows read, the megabytes of its chunks on disk, the seconds
   --  the reads took, and for a string column the entries its dictionary
   --  pages held and the plain values that added more (any at all means
   --  the writer fell back to plain values mid-chunk).  Ok is False when
   --  the column is not there, is refused, or reads fewer rows than the
   --  footer states.
   procedure Bench (F : Tessera.Files.File; Name : String; Ok : out Boolean);

end Bench_Columns;
