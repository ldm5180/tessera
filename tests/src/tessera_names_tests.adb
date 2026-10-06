with AUnit.Assertions; use AUnit.Assertions;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Interfaces; use Interfaces;

with Tessera;       use Tessera;
with Tessera.Names; use Tessera.Names;

--  Every code's name, a code with none, and every refusal in words.

package body Tessera_Names_Tests is

   use AUnit.Test_Cases.Registration;

   --  The names Name_Of gives the codes 0 .. Last, one blank apart.
   function Joined
     (Name_Of : not null access function (Code : Integer_64) return String;
      Last    : Integer_64) return String
   is
      Text : Unbounded_String;
   begin
      for Code in 0 .. Last loop
         Append (Text, (if Code = 0 then "" else " ") & Name_Of (Code));
      end loop;
      return To_String (Text);
   end Joined;

   procedure Test_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert
        (Joined (Codec_Name'Access, 7)
         = "UNCOMPRESSED SNAPPY GZIP LZO BROTLI LZ4 ZSTD LZ4_RAW",
         "the codecs");
      Assert
        (Joined (Encoding_Name'Access, 9)
         = "PLAIN GROUP_VAR_INT PLAIN_DICTIONARY RLE BIT_PACKED "
           & "DELTA_BINARY_PACKED DELTA_LENGTH_BYTE_ARRAY DELTA_BYTE_ARRAY "
           & "RLE_DICTIONARY BYTE_STREAM_SPLIT",
         "the encodings");
      Assert
        (Joined (Page_Name'Access, 3)
         = "DATA_PAGE INDEX_PAGE DICTIONARY_PAGE DATA_PAGE_V2",
         "the page types");
      Assert
        (Joined (Physical_Name'Access, 7)
         = "BOOLEAN INT32 INT64 INT96 FLOAT DOUBLE BYTE_ARRAY "
           & "FIXED_LEN_BYTE_ARRAY",
         "the physical types");
      Assert (Codec_Name (42) = "42", "a code with no name is its number");
      Assert (Encoding_Name (-1) = "-1", "and a negative one too");
      Assert (Page_Name (4) = "4" and then Physical_Name (8) = "8", "past");
   end Test_Codes;

   procedure Test_Describe (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Describe (Done) = "", "Ok is not a refusal");
      Assert
        (Describe (Refused_With (Unsupported_Codec, 1, 6))
         = "an unsupported codec, ZSTD",
         "a codec, named");
      Assert
        (Describe (Refused_With (Unsupported_Encoding, 1, 5))
         = "an unsupported encoding, DELTA_BINARY_PACKED",
         "an encoding, named");
      Assert
        (Describe (Refused_With (Unsupported_Page_Version, 1, 3))
         = "an unsupported page, DATA_PAGE_V2",
         "a page type, named");
      Assert
        (Describe (Refused_With (Unsupported_Type, 1, 3))
         = "an unsupported type, INT96",
         "a physical type, named");
      Assert
        (Describe (Refused (Unsupported_Type, 1))
         = "an unsupported annotation",
         "an annotation has no value");
      Assert
        (Describe (Refused_With (Wrong_Type, 1, 4)) = "the wrong type, FLOAT",
         "the type a column is");
      Assert
        (Describe (Refused_With (No_Such_Row_Group, 0, 9))
         = "no such row group, 9",
         "a number is a number");
      for Why in Refusal loop
         Assert
           (Describe (Refused (Why))'Length > 0, Why'Image & " has words");
      end loop;
   end Test_Describe;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Codes'Access, "codes");
      Register_Routine (T, Test_Describe'Access, "refusals in words");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Names");
   end Name;

end Tessera_Names_Tests;
