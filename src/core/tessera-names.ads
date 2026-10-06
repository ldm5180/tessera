with Interfaces; use Interfaces;

--  The names the Parquet specification gives the codes a file holds --
--  codecs, encodings, page types, physical types -- and a refusal in
--  words, with the value that earned it named.  A code outside the
--  specification's list is named by its number.

package Tessera.Names
  with SPARK_Mode
is

   Max_Name : constant := 64;

   function Codec_Name (Code : Integer_64) return String
   with Post => Codec_Name'Result'Length <= Max_Name;

   function Encoding_Name (Code : Integer_64) return String
   with Post => Encoding_Name'Result'Length <= Max_Name;

   function Page_Name (Code : Integer_64) return String
   with Post => Page_Name'Result'Length <= Max_Name;

   function Physical_Name (Code : Integer_64) return String
   with Post => Physical_Name'Result'Length <= Max_Name;

   --  R in words: "an unsupported codec, ZSTD", "truncated", ...; empty
   --  when R is Ok.
   function Describe (R : Outcome) return String;

end Tessera.Names;
