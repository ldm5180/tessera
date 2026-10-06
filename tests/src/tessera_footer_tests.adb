with AUnit.Assertions; use AUnit.Assertions;

with Interfaces; use Interfaces;

with Tessera;          use Tessera;
with Tessera.Footer;   use Tessera.Footer;
with Tessera_Fixtures; use Tessera_Fixtures;

--  The two ends and the footer: what Locate refuses, what Decode reads
--  out of the fixtures pyarrow wrote, and what it refuses in footers
--  built byte by byte.

package body Tessera_Footer_Tests is

   use AUnit.Test_Cases.Registration;

   Par1 : constant Bytes := [80, 65, 82, 49];
   Pare : constant Bytes := [80, 65, 82, 69];

   --  A tail: the footer length Length, little-endian, then M.
   function Tail (Length : Byte; M : Bytes) return Bytes
   is ([Length, 0, 0, 0] & M);

   function Located
     (Head : Bytes; Tail_Bytes : Bytes; Size : File_Offset) return Outcome
   is
      Length : Buffer_Count;
      Result : Outcome;
   begin
      Locate (Head, Tail_Bytes, Size, Length, Result);
      return Result;
   end Located;

   procedure Test_Locate (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Length : Buffer_Count;
      Result : Outcome;
   begin
      Locate (Par1, Tail (20, Par1), 40, Length, Result);
      Assert (Result.Ok and then Length = 20, "a footer of 20 bytes");
      Locate (Par1, Tail (28, Par1), 40, Length, Result);
      Assert (Result.Ok and then Length = 28, "the footer fills the file");
      Assert
        (Located ([80, 65, 82, 48], Tail (20, Par1), 40).Why = Not_Parquet,
         "a head without the magic is not Parquet");
      Assert
        (Located ([80, 65], Tail (20, Par1), 40).Why = Not_Parquet,
         "a head too short for the magic");
      Assert
        (Located (Par1, Tail (20, Pare), 40).Why = Encrypted,
         "PARE at the end is an encrypted footer");
      Assert
        (Located (Par1, Tail (20, [1, 2, 3, 4]), 40).Why = Truncated,
         "the magic at the head and not the end");
      Assert
        (Located (Par1, Par1, 10).Why = Truncated,
         "fewer bytes than the two magics and a length");
      Result := Located (Par1, Tail (29, Par1), 40);
      Assert
        (Result.Why = Corrupt_Footer and then Result.Value = 29,
         "a length past the file, named");
   end Test_Locate;

   procedure Test_Flat_Schema (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opened : constant Opened_File := Open ("flat.parquet");
      Meta   : constant Metadata_Access := Opened.Meta;
      Result : constant Outcome := Opened.Result;
   begin
      Assert (Result.Ok, "flat.parquet decodes");
      Assert
        (Meta.Columns = 13 and then Meta.Rows = 10, "13 columns, 10 rows");
      Assert (Name_Of (Meta.Schema (1)) = "flag", "the first column's name");
      Assert (Meta.Schema (1).Kind = Bool, "flag is BOOLEAN");
      Assert (Meta.Schema (3).Note = Uint_8, "u8 is unsigned 8");
      Assert (Meta.Schema (6).Note = Date, "day is a date");
      Assert (Meta.Schema (9).Note = Time_Micros, "clock is a time");
      Assert
        (Meta.Schema (10).Note = Timestamp_Micros,
         "stamp is a timestamp, from the logical type alone");
      Assert (Meta.Schema (11).Kind = Float32, "single is FLOAT");
      Assert
        (Meta.Schema (13).Kind = Byte_Array
         and then Meta.Schema (13).Note = Text,
         "text is a string");
      Assert (Meta.Schema (2).Optional, "pyarrow's columns may hold nulls");
      Assert (Find (Meta.all, "double") = 12, "double is column 12");
      Assert (Find (Meta.all, "nothing") = 0, "no column named nothing");
   end Test_Flat_Schema;

   procedure Test_Flat_Chunks (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opened : constant Opened_File := Open ("flat.parquet");
      Meta   : constant Metadata_Access := Opened.Meta;
   begin
      Assert (Meta.Groups = 1 and then Meta.Group (1).Rows = 10, "one group");
      Assert
        (not Meta.Group (1).Chunks (1).Has_Dictionary,
         "the boolean chunk has no dictionary");
      Assert
        (Meta.Group (1).Chunks (1).Start = 4,
         "the first chunk starts after the magic");
      Assert
        (Meta.Group (1).Chunks (2).Has_Dictionary
         and then Meta.Group (1).Chunks (2).Start
                  < Meta.Group (1).Chunks (2).Data_Offset,
         "a dictionary page comes before the data");
      Assert (Meta.Group (1).Chunks (2).Codec_Code = Snappy_Code, "Snappy");
      Assert (Meta.Group (1).Chunks (2).Values = 10, "one value a row");
   end Test_Flat_Chunks;

   procedure Test_Groups (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Opened : constant Opened_File := Open ("groups.parquet");
      Meta   : constant Metadata_Access := Opened.Meta;
      Result : constant Outcome := Opened.Result;
   begin
      Assert (Result.Ok and then Meta.Groups = 3, "three row groups");
      Assert
        ((for all G in 1 .. 3 => Meta.Group (G).Rows = 10),
         "ten rows in each");
      Assert
        (Meta.Group (2).Chunks (1).Start > Meta.Group (1).Chunks (2).Start,
         "the groups' chunks follow each other");
   end Test_Groups;

   --  The refusal Name's footer earns.
   function Refusal_Of (Name : String) return Outcome is
      Opened : constant Opened_File := Open (Name);
      Result : constant Outcome := Opened.Result;
   begin
      return Result;
   end Refusal_Of;

   procedure Test_Refused_Fixtures
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Result : Outcome;
   begin
      Result := Refusal_Of ("nested.parquet");
      Assert
        (Result.Why = Nested_Schema and then Result.Column = 1,
         "a list column is nested");
      Result := Refusal_Of ("zstd.parquet");
      Assert
        (Result.Why = Unsupported_Codec and then Result.Value = 6,
         "ZSTD is codec 6");
      Result := Refusal_Of ("delta.parquet");
      Assert
        (Result.Why = Unsupported_Encoding and then Result.Value = 5,
         "DELTA_BINARY_PACKED is encoding 5");
      Assert (Refusal_Of ("truncated.parquet").Why = Truncated, "cut in half");
      Assert (Refusal_Of ("badmagic.parquet").Why = Not_Parquet, "no magic");
      Assert (Refusal_Of ("v2pages.parquet").Ok, "v2 pages are in the pages");
   end Test_Refused_Fixtures;

   function Decoded (Input : Bytes; Data_End : File_Offset) return Outcome is
      Meta   : constant Metadata_Access := new Metadata;
      Result : Outcome;
   begin
      Decode (Input, Data_End, Meta.all, Result);
      return Result;
   end Decoded;

   procedure Test_Refused_Footers (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      --  Field 2 (schema), a list of 300 structs, each empty.
      Wide   : constant Bytes :=
        [16#29#, 16#FC#, 16#AC#, 16#02#] & [1 .. 301 => 0];
      --  A root claiming five children, and one leaf: an INT32 named a.
      Liar   : constant Bytes :=
        [16#29#,
         16#2C#,
         16#55#,
         16#0A#,
         0,
         16#15#,
         16#02#,
         16#38#,
         16#01#,
         97,
         0,
         0];
      Result : Outcome;
   begin
      Assert
        (Decoded ([16#8C#, 0, 0], 100).Why = Encrypted,
         "an encryption algorithm in a plain footer");
      Assert (Decoded ([16#15#], 100).Why = Corrupt_Footer, "cut short");
      Assert (Decoded ([0], 100).Why = Corrupt_Footer, "no schema at all");
      Result := Decoded (Wide, 100);
      Assert
        (Result.Why = Too_Large and then Result.Value = 300,
         "more columns than a table holds");
      Assert (Decoded (Liar, 100).Why = Nested_Schema, "a root that lies");
   end Test_Refused_Footers;

   procedure Test_Chunk_Outside (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
      Opened : constant Opened_File := Open ("flat.parquet");
      File   : constant Bytes_Access := Opened.File;
      Meta   : constant Metadata_Access := Opened.Meta;
      Result : Outcome := Opened.Result;
      Length : Buffer_Count;
   begin
      Locate
        (File.all,
         File (File'Last - 7 .. File'Last),
         File'Length,
         Length,
         Result);
      --  The same footer, as if the data ended where the last chunk
      --  begins.
      Result :=
        Decoded
          (File (File'Last - 8 - Length + 1 .. File'Last - 8),
           Meta.Group (1).Chunks (13).Start);
      Assert
        (Result.Why = Corrupt_Footer and then Result.Column = 13,
         "a chunk past the end of the data, named");
   end Test_Chunk_Outside;

   overriding
   procedure Register_Tests (T : in out Test) is
   begin
      Register_Routine (T, Test_Locate'Access, "locate");
      Register_Routine (T, Test_Flat_Schema'Access, "flat schema");
      Register_Routine (T, Test_Flat_Chunks'Access, "flat chunks");
      Register_Routine (T, Test_Groups'Access, "row groups");
      Register_Routine (T, Test_Refused_Fixtures'Access, "refused fixtures");
      Register_Routine (T, Test_Refused_Footers'Access, "refused footers");
      Register_Routine (T, Test_Chunk_Outside'Access, "chunk outside");
   end Register_Tests;

   overriding
   function Name (T : Test) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Tessera.Footer");
   end Name;

end Tessera_Footer_Tests;
