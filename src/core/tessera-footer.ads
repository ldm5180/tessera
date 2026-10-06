with Interfaces; use Interfaces;

--  The file's two ends and its footer.  A Parquet file is the magic
--  "PAR1", the column chunks, the footer (a Thrift FileMetaData), the
--  footer's length in four little-endian bytes, and "PAR1" again.  The
--  footer is decoded into bounded tables: the schema's columns, the row
--  groups, and per row group each column chunk's codec, value count,
--  sizes and where its pages start.  Everything decoded is checked
--  before it is believed: a chunk must lie between the leading magic and
--  the footer, a count must fit its table, and a feature outside the
--  subset (a nested schema, a codec other than Snappy, an encoding
--  outside PLAIN, RLE and the dictionary) is refused by name.

package Tessera.Footer
  with SPARK_Mode
is

   --  The magic at each end, and the eight bytes that end a file: the
   --  footer's length and the magic.
   Magic_Size : constant := 4;
   Tail_Size  : constant := 8;

   --  The fewest bytes a file can have: both magics and the length.
   Min_File : constant := Magic_Size + Tail_Size;

   subtype File_Offset is Integer_64 range 0 .. Integer_64'Last;

   Max_Row_Groups : constant := 128;
   Max_Name       : constant := 128;

   --  The most rows one row group may have: a column of it is an array.
   Max_Group_Rows : constant := 2**27;

   subtype Row_Count is Natural range 0 .. Max_Group_Rows;

   --  The physical types, in the order of their codes 0 .. 7.
   type Physical_Type is
     (Bool,
      Int32,
      Int64,
      Int96,
      Float32,
      Float64,
      Byte_Array,
      Fixed_Len_Byte_Array);

   --  How a column's physical values are to be read: the logical (or
   --  older converted) annotations tessera knows, and Other for any it
   --  does not, which a read of the column refuses.
   type Annotation is
     (None,
      Text,
      Date,
      Time_Micros,
      Timestamp_Micros,
      Int_8,
      Int_16,
      Int_32,
      Int_64,
      Uint_8,
      Uint_16,
      Uint_32,
      Uint_64,
      Other);

   subtype Name_Length is Natural range 0 .. Max_Name;

   --  One column of the schema: its name, physical type, annotation, and
   --  whether it may hold nulls (an optional field).
   type Column_Info is record
      Name     : String (1 .. Max_Name) := [others => ' '];
      Length   : Name_Length := 0;
      Kind     : Physical_Type := Bool;
      Note     : Annotation := None;
      Optional : Boolean := False;
   end record;

   function Name_Of (Column : Column_Info) return String
   is (Column.Name (1 .. Column.Length));

   --  No encoding outside the subset was listed.
   No_Encoding : constant Integer_32 := -1;

   --  One column chunk as the footer states it.  Start is where its first
   --  page (the dictionary page when there is one) begins in the file.
   type Chunk_Info is record
      Type_Code         : Integer_32 := -1;
      Codec_Code        : Integer_32 := 0;
      Bad_Encoding      : Integer_32 := No_Encoding;
      Values            : File_Offset := 0;
      Start             : File_Offset := 0;
      Compressed_Size   : File_Offset := 0;
      Uncompressed_Size : File_Offset := 0;
      Has_Dictionary    : Boolean := False;
      Data_Offset       : File_Offset := 0;
   end record;

   --  The codes of the two codecs read: none, and Snappy.
   Uncompressed_Code : constant := 0;
   Snappy_Code       : constant := 1;

   type Chunk_Array is array (Column_Number) of Chunk_Info;

   type Group_Info is record
      Rows   : File_Offset := 0;
      Count  : Column_Count := 0;
      Chunks : Chunk_Array;
   end record;

   subtype Group_Count is Natural range 0 .. Max_Row_Groups;
   subtype Group_Number is Group_Count range 1 .. Max_Row_Groups;

   type Column_Array is array (Column_Number) of Column_Info;
   type Group_Array is array (Group_Number) of Group_Info;

   --  A decoded footer.  Fault is what decoding itself refused, before the
   --  tables were checked; a caller reads Decode's Result instead.
   type Metadata is record
      Rows    : File_Offset := 0;
      Columns : Column_Count := 0;
      Schema  : Column_Array;
      Groups  : Group_Count := 0;
      Group   : Group_Array;
      Fault   : Outcome := Done;
   end record;

   --  The footer's length, from a file of Size bytes whose first bytes
   --  are Head and whose last eight are Tail.  Refuses a file that does
   --  not begin with the magic (Not_Parquet), one that does but does not
   --  end with it (Truncated), one that ends with "PARE" (Encrypted), and
   --  a length that does not fit between the two magics.
   procedure Locate
     (Head   : Bytes;
      Tail   : Bytes;
      Size   : File_Offset;
      Length : out Buffer_Count;
      Result : out Outcome)
   with
     Post =>
       (if Result.Ok
        then Size >= Min_File and then Integer_64 (Length) <= Size - Min_File);

   --  The footer's bytes decoded into Into, then checked: every chunk
   --  must end at or before Data_End, the offset where the footer begins.
   procedure Decode
     (Input    : Bytes;
      Data_End : File_Offset;
      Into     : in out Metadata;
      Result   : out Outcome)
   with
     Post =>
       (if Result.Ok
        then
          Valid (Into)
          and then (for all G in 1 .. Into.Groups =>
                      Fits (Into.Group (G), Into.Columns, Data_End)));

   --  The checked shape every decoded footer has: each row group's rows
   --  fit a column, and it has a chunk for every column.
   function Valid (Meta : Metadata) return Boolean
   is (for all G in 1 .. Meta.Groups =>
         Meta.Group (G).Rows <= Max_Group_Rows
         and then Meta.Group (G).Count = Meta.Columns);

   --  True when Chunk lies inside the file, after the leading magic and
   --  before Data_End, and its sizes fit a buffer.
   function Fits_One
     (Chunk : Chunk_Info; Data_End : File_Offset) return Boolean
   is (Chunk.Start >= Magic_Size
       and then Chunk.Compressed_Size <= Max_Buffer
       and then Chunk.Uncompressed_Size <= Max_Buffer
       and then Chunk.Start <= Data_End - Chunk.Compressed_Size);

   --  True when every chunk of Group fits (Fits_One).
   function Fits
     (Group : Group_Info; Columns : Column_Count; Data_End : File_Offset)
      return Boolean
   is (for all K in 1 .. Columns => Fits_One (Group.Chunks (K), Data_End));

   --  The column named Name, or 0 when there is none.
   function Find (Meta : Metadata; Name : String) return Column_Count
   with
     Post =>
       Find'Result <= Meta.Columns
       and then (if Find'Result > 0
                 then Name_Of (Meta.Schema (Find'Result)) = Name);

end Tessera.Footer;
