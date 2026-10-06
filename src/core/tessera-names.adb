package body Tessera.Names
  with SPARK_Mode
is

   --  A code with no name: its number, without the blank an image gives
   --  a number that is not negative.
   function Number (Code : Integer_64) return String
   with Post => Number'Result'Length <= Max_Name;

   function Number (Code : Integer_64) return String is
      Image : constant String := Integer_64'Image (Code);
   begin
      if Code >= 0 and then Image'Length > 1 then
         return Image (Image'First + 1 .. Image'Last);
      end if;
      return Image;
   end Number;

   function Codec_Name (Code : Integer_64) return String
   is (case Code is
         when 0      => "UNCOMPRESSED",
         when 1      => "SNAPPY",
         when 2      => "GZIP",
         when 3      => "LZO",
         when 4      => "BROTLI",
         when 5      => "LZ4",
         when 6      => "ZSTD",
         when 7      => "LZ4_RAW",
         when others => Number (Code));

   function Encoding_Name (Code : Integer_64) return String
   is (case Code is
         when 0      => "PLAIN",
         when 1      => "GROUP_VAR_INT",
         when 2      => "PLAIN_DICTIONARY",
         when 3      => "RLE",
         when 4      => "BIT_PACKED",
         when 5      => "DELTA_BINARY_PACKED",
         when 6      => "DELTA_LENGTH_BYTE_ARRAY",
         when 7      => "DELTA_BYTE_ARRAY",
         when 8      => "RLE_DICTIONARY",
         when 9      => "BYTE_STREAM_SPLIT",
         when others => Number (Code));

   function Page_Name (Code : Integer_64) return String
   is (case Code is
         when 0      => "DATA_PAGE",
         when 1      => "INDEX_PAGE",
         when 2      => "DICTIONARY_PAGE",
         when 3      => "DATA_PAGE_V2",
         when others => Number (Code));

   function Physical_Name (Code : Integer_64) return String
   is (case Code is
         when 0      => "BOOLEAN",
         when 1      => "INT32",
         when 2      => "INT64",
         when 3      => "INT96",
         when 4      => "FLOAT",
         when 5      => "DOUBLE",
         when 6      => "BYTE_ARRAY",
         when 7      => "FIXED_LEN_BYTE_ARRAY",
         when others => Number (Code));

   --  The phrase for a refusal, before any value.
   function Phrase (Why : Refusal; Valued : Boolean) return String
   is (case Why is
         when Not_Parquet              => "not Parquet",
         when Truncated                => "truncated",
         when Corrupt_Footer           => "a corrupt footer",
         when Corrupt_Page             => "a corrupt page",
         when Nested_Schema            => "a nested schema",
         when Unsupported_Codec        => "an unsupported codec",
         when Unsupported_Encoding     => "an unsupported encoding",
         when Unsupported_Page_Version => "an unsupported page",
         when Unsupported_Type         =>
           (if Valued
            then "an unsupported type"
            else "an unsupported annotation"),
         when Encrypted                => "encrypted",
         when No_Such_Row_Group        => "no such row group",
         when No_Such_Column           => "no such column",
         when Wrong_Type               => "the wrong type",
         when Too_Large                => "too large",
         when Cannot_Read              => "unreadable");

   --  The value of a refusal, named as what it is a code of.
   function Value_Name (Why : Refusal; Value : Integer_64) return String
   is (case Why is
         when Unsupported_Codec             => Codec_Name (Value),
         when Unsupported_Encoding          => Encoding_Name (Value),
         when Unsupported_Page_Version      => Page_Name (Value),
         when Unsupported_Type | Wrong_Type => Physical_Name (Value),
         when others                        => Number (Value));

   function Describe (R : Outcome) return String
   is (if R.Ok
       then ""
       elsif R.Valued
       then Phrase (R.Why, True) & ", " & Value_Name (R.Why, R.Value)
       else Phrase (R.Why, False));

end Tessera.Names;
