with Tessera.Thrift; use Tessera.Thrift;
with Tessera.Thrift.Read_Struct;

package body Tessera.Footer
  with SPARK_Mode
is

   ---------------------------------------------------------------------
   --  The two ends
   ---------------------------------------------------------------------

   type Magic is array (1 .. Magic_Size) of Byte;

   Plain_Magic     : constant Magic := [80, 65, 82, 49];  --  "PAR1"
   Encrypted_Magic : constant Magic := [80, 65, 82, 69];  --  "PARE"

   --  True when the Magic_Size bytes of Input from Offset are M.
   function Has (Input : Bytes; Offset : Natural; M : Magic) return Boolean
   is (Offset <= Input'Length - Magic_Size
       and then (for all K in M'Range =>
                   Byte_At (Input, Offset + K - 1) = M (K)))
   with Pre => Input'Length >= Magic_Size;

   --  The four little-endian bytes of Tail before its magic.
   function Length_Of (Tail : Bytes) return Unsigned_32
   is (Unsigned_32 (Byte_At (Tail, 0))
       or Shift_Left (Unsigned_32 (Byte_At (Tail, 1)), 8)
       or Shift_Left (Unsigned_32 (Byte_At (Tail, 2)), 16)
       or Shift_Left (Unsigned_32 (Byte_At (Tail, 3)), 24))
   with Pre => Tail'Length = Tail_Size;

   function Starts_Right (Head : Bytes) return Boolean
   is (Head'Length >= Magic_Size and then Has (Head, 0, Plain_Magic));

   procedure Locate
     (Head   : Bytes;
      Tail   : Bytes;
      Size   : File_Offset;
      Length : out Buffer_Count;
      Result : out Outcome) is
   begin
      Length := 0;
      if not Starts_Right (Head) then
         Result := Refused (Not_Parquet);
      elsif Size < Min_File or else Tail'Length /= Tail_Size then
         Result := Refused (Truncated);
      elsif Has (Tail, Magic_Size, Encrypted_Magic) then
         Result := Refused (Encrypted);
      elsif not Has (Tail, Magic_Size, Plain_Magic) then
         Result := Refused (Truncated);
      elsif Integer_64 (Length_Of (Tail)) > Size - Min_File then
         Result :=
           Refused_With (Corrupt_Footer, 0, Integer_64 (Length_Of (Tail)));
      elsif Length_Of (Tail) > Max_Buffer then
         Result := Refused_With (Too_Large, 0, Integer_64 (Length_Of (Tail)));
      else
         Length := Buffer_Count (Length_Of (Tail));
         Result := Done;
      end if;
   end Locate;

   ---------------------------------------------------------------------
   --  Small readers shared by the structs
   ---------------------------------------------------------------------

   --  Records the first refusal decoding meets, and stops the cursor.
   procedure Refuse (Into : in out Metadata; C : in out Cursor; R : Outcome)
   with Post => not C.Ok and then C.Pos = C.Pos'Old;

   procedure Refuse (Into : in out Metadata; C : in out Cursor; R : Outcome) is
   begin
      if Into.Fault.Ok then
         Into.Fault := R;
      end if;
      C.Ok := False;
   end Refuse;

   --  An i64 field that must not be negative.
   procedure Read_Offset
     (Input : Bytes; C : in out Cursor; Value : out File_Offset)
   with Post => Sound (C, Input);

   procedure Read_Offset
     (Input : Bytes; C : in out Cursor; Value : out File_Offset)
   is
      Wide : Integer_64;
   begin
      Value := 0;
      Read_Zigzag (Input, C, Wide);
      if Wide >= 0 then
         Value := Wide;
      else
         C.Ok := False;
      end if;
   end Read_Offset;

   ---------------------------------------------------------------------
   --  LogicalType, and the TimeType and IntType inside it
   ---------------------------------------------------------------------

   --  A TimeUnit union's member: 1 MILLIS, 2 MICROS, 3 NANOS; 0 none.
   subtype Time_Unit is Integer_16;

   Micros : constant Time_Unit := 2;

   function Unit_Known (H : Field_Header) return Boolean
   is (H.Id in 1 .. 3 and then H.Kind = Struct);

   procedure Read_Unit
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Time_Unit;
      H     : Field_Header);

   procedure Read_Unit
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Time_Unit;
      H     : Field_Header) is
   begin
      if H.Id in 1 .. 3 then
         Into := H.Id;
      end if;
      Skip (Input, C, H.Kind);
   end Read_Unit;

   procedure Read_Time_Unit is new
     Read_Struct (Time_Unit, Unit_Known, Read_Unit);

   --  TimeType and TimestampType: field 2 is the unit.
   function Time_Known (H : Field_Header) return Boolean
   is (H.Id = 2 and then H.Kind = Struct);

   procedure Read_Time_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Time_Unit;
      H     : Field_Header);

   procedure Read_Time_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Time_Unit;
      H     : Field_Header)
   is
      pragma Unreferenced (H);
   begin
      Read_Time_Unit (Input, C, Into);
   end Read_Time_Field;

   procedure Read_Time_Type is new
     Read_Struct (Time_Unit, Time_Known, Read_Time_Field);

   --  IntType: field 1 the bit width, field 2 whether it is signed.
   type Int_Type is record
      Bits   : Byte := 0;
      Signed : Boolean := True;
   end record;

   function Int_Known (H : Field_Header) return Boolean
   is ((H.Id = 1 and then H.Kind = I8)
       or else (H.Id = 2 and then H.Kind in Bool_True | Bool_False));

   procedure Read_Int_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Int_Type;
      H     : Field_Header);

   procedure Read_Int_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Int_Type;
      H     : Field_Header) is
   begin
      if H.Id = 1 then
         Read_Byte (Input, C, Into.Bits);
      else
         Into.Signed := H.Kind = Bool_True;
      end if;
   end Read_Int_Field;

   procedure Read_Int_Type is new
     Read_Struct (Int_Type, Int_Known, Read_Int_Field);

   function Integer_Note (T : Int_Type) return Annotation
   is (case T.Bits is
         when 8      => (if T.Signed then Int_8 else Uint_8),
         when 16     => (if T.Signed then Int_16 else Uint_16),
         when 32     => (if T.Signed then Int_32 else Uint_32),
         when 64     => (if T.Signed then Int_64 else Uint_64),
         when others => Other);

   --  The LogicalType union's members: 1 STRING, 6 DATE, 7 TIME,
   --  8 TIMESTAMP, 10 INTEGER.
   String_Member    : constant := 1;
   Date_Member      : constant := 6;
   Time_Member      : constant := 7;
   Timestamp_Member : constant := 8;
   Integer_Member   : constant := 10;

   --  Every member of the union is read, so an unknown one is Other.
   function Logical_Known (H : Field_Header) return Boolean
   is (H.Kind = Struct);

   procedure Read_Timed
     (Input  : Bytes;
      C      : in out Cursor;
      Into   : out Annotation;
      Stamps : Boolean);

   procedure Read_Timed
     (Input  : Bytes;
      C      : in out Cursor;
      Into   : out Annotation;
      Stamps : Boolean)
   is
      Unit : Time_Unit := 0;
   begin
      Read_Time_Type (Input, C, Unit);
      Into :=
        (if Unit /= Micros
         then Other
         elsif Stamps
         then Timestamp_Micros
         else Time_Micros);
   end Read_Timed;

   --  A LogicalType as read: the annotation its member names, and how
   --  many members it had.  A union has one; any more make it Other.
   type Logical_Read is record
      Note    : Annotation := None;
      Members : Natural range 0 .. 2 := 0;
   end record;

   --  The annotation of the member H, which Input holds at C.
   procedure Read_Member
     (Input : Bytes;
      C     : in out Cursor;
      H     : Field_Header;
      Note  : out Annotation);

   procedure Read_Member
     (Input : Bytes;
      C     : in out Cursor;
      H     : Field_Header;
      Note  : out Annotation)
   is
      Int : Int_Type;
   begin
      case H.Id is
         when Time_Member | Timestamp_Member =>
            Read_Timed (Input, C, Note, Stamps => H.Id = Timestamp_Member);

         when Integer_Member                 =>
            Read_Int_Type (Input, C, Int);
            Note := Integer_Note (Int);

         when others                         =>
            Skip (Input, C, H.Kind);
            Note :=
              (case H.Id is
                 when String_Member => Text,
                 when Date_Member   => Date,
                 when others        => Other);
      end case;
   end Read_Member;

   procedure Read_Logical_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Logical_Read;
      H     : Field_Header);

   procedure Read_Logical_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Logical_Read;
      H     : Field_Header)
   is
      Note : Annotation;
   begin
      Read_Member (Input, C, H, Note);
      Into.Note := (if Into.Members = 0 then Note else Other);
      Into.Members := Natural'Min (Into.Members + 1, 2);
   end Read_Logical_Field;

   procedure Read_Logical is new
     Read_Struct (Logical_Read, Logical_Known, Read_Logical_Field);

   ---------------------------------------------------------------------
   --  SchemaElement
   ---------------------------------------------------------------------

   --  The converted types an older writer gives, read when there is no
   --  logical type.
   No_Converted : constant Integer_32 := -1;

   function Converted_Note (Code : Integer_32) return Annotation
   is (case Code is
         when No_Converted => None,
         when 0            => Text,
         when 6            => Date,
         when 8            => Time_Micros,
         when 10           => Timestamp_Micros,
         when 11           => Uint_8,
         when 12           => Uint_16,
         when 13           => Uint_32,
         when 14           => Uint_64,
         when 15           => Int_8,
         when 16           => Int_16,
         when 17           => Int_32,
         when 18           => Int_64,
         when others       => Other);

   Repeated : constant := 2;
   Optional : constant := 1;

   --  One SchemaElement as written.
   type Element is record
      Type_Code  : Integer_32 := -1;
      Repetition : Integer_32 := 0;
      Name       : Span;
      Has_Name   : Boolean := False;
      Children   : Integer_32 := 0;
      Converted  : Integer_32 := No_Converted;
      Logical    : Logical_Read;
   end record;

   --  1 type, 3 repetition_type, 4 name, 5 num_children,
   --  6 converted_type, 10 logicalType.
   function Element_Known (H : Field_Header) return Boolean
   is ((H.Id in 1 | 3 | 5 | 6 and then H.Kind = I32)
       or else (H.Id = 4 and then H.Kind = Binary)
       or else (H.Id = 10 and then H.Kind = Struct));

   procedure Read_Element_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Element;
      H     : Field_Header);

   procedure Read_Element_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Element;
      H     : Field_Header) is
   begin
      case H.Id is
         when 1      =>
            Read_I32 (Input, C, Into.Type_Code);

         when 3      =>
            Read_I32 (Input, C, Into.Repetition);

         when 4      =>
            Read_Binary (Input, C, Into.Name);
            Into.Has_Name := True;

         when 5      =>
            Read_I32 (Input, C, Into.Children);

         when 6      =>
            Read_I32 (Input, C, Into.Converted);

         when others =>
            Read_Logical (Input, C, Into.Logical);
      end case;
   end Read_Element_Field;

   procedure Read_Element is new
     Read_Struct (Element, Element_Known, Read_Element_Field);

   --  The name of E, copied out of Input.
   procedure Copy_Name (Input : Bytes; E : Element; Into : in out Column_Info)
   with Pre => Inside (E.Name, Input) and then E.Name.Length <= Max_Name;

   procedure Copy_Name (Input : Bytes; E : Element; Into : in out Column_Info)
   is
   begin
      Into.Length := E.Name.Length;
      for K in 1 .. E.Name.Length loop
         Into.Name (K) :=
           Character'Val (Byte_At (Input, E.Name.Start + K - 1));
      end loop;
   end Copy_Name;

   --  The refusal a leaf element earns, if any: children or repetition
   --  make it nested, and two physical types are outside the subset.
   function Leaf_Verdict (E : Element; Column : Column_Number) return Outcome
   is (if E.Children /= 0 or else E.Repetition = Repeated
       then Refused (Nested_Schema, Column)
       elsif E.Type_Code not in 0 .. 7
         or else not E.Has_Name
         or else E.Name.Length > Max_Name
       then Refused_With (Corrupt_Footer, Column, Integer_64 (E.Type_Code))
       elsif Physical_Type'Val (E.Type_Code) in Int96 | Fixed_Len_Byte_Array
       then Refused_With (Unsupported_Type, Column, Integer_64 (E.Type_Code))
       else Done);

   --  E as column Column of Into's schema, or the refusal it earns.
   procedure Store_Leaf
     (Input  : Bytes;
      C      : in out Cursor;
      E      : Element;
      Column : Column_Number;
      Into   : in out Metadata)
   with Pre => Inside (E.Name, Input), Post => C.Pos = C.Pos'Old;

   procedure Store_Leaf
     (Input  : Bytes;
      C      : in out Cursor;
      E      : Element;
      Column : Column_Number;
      Into   : in out Metadata)
   is
      Verdict : constant Outcome := Leaf_Verdict (E, Column);
   begin
      if not Verdict.Ok then
         Refuse (Into, C, Verdict);
         return;
      end if;
      Into.Schema (Column) :=
        (Kind     => Physical_Type'Val (E.Type_Code),
         Note     =>
           (if E.Logical.Members > 0
            then E.Logical.Note
            else Converted_Note (E.Converted)),
         Optional => E.Repetition = Optional,
         others   => <>);
      Copy_Name (Input, E, Into.Schema (Column));
      Into.Columns := Column;
   end Store_Leaf;

   --  Element I of a schema: the root (whose child count is kept, to be
   --  checked once every leaf is in), or a leaf.
   procedure Take_Element
     (Input    : Bytes;
      C        : in out Cursor;
      E        : Element;
      I        : Positive;
      Children : in out Integer_32;
      Into     : in out Metadata)
   with
     Pre  => I <= Max_Columns + 1 and then Sound (C, Input),
     Post => Sound (C, Input);

   procedure Take_Element
     (Input    : Bytes;
      C        : in out Cursor;
      E        : Element;
      I        : Positive;
      Children : in out Integer_32;
      Into     : in out Metadata) is
   begin
      if not C.Ok then
         return;
      elsif I = 1 then
         Children := E.Children;
      elsif Inside (E.Name, Input) then
         Store_Leaf (Input, C, E, I - 1, Into);
      else
         Refuse (Into, C, Refused (Corrupt_Footer, I - 1));
      end if;
   end Take_Element;

   --  The schema: a root whose children are every other element, each a
   --  leaf.  Element 1 is the root.  A leaf with children of its own names
   --  the nested column; a root that has fewer children than elements
   --  without any such leaf is nested still.
   procedure Read_Schema
     (Input : Bytes; C : in out Cursor; Into : in out Metadata)
   with Post => Sound (C, Input);

   procedure Read_Schema
     (Input : Bytes; C : in out Cursor; Into : in out Metadata)
   is
      H        : List_Header;
      E        : Element;
      Children : Integer_32 := 0;
   begin
      Read_List_Header (Input, C, H);
      if not C.Ok then
         return;
      elsif H.Element /= Struct or else H.Count = 0 then
         Refuse (Into, C, Refused (Corrupt_Footer));
      elsif H.Count > Max_Columns + 1 then
         Refuse (Into, C, Refused_With (Too_Large, 0, Integer_64 (H.Count)));
      end if;
      for I in 1 .. H.Count loop
         exit when not C.Ok or else I > Max_Columns + 1;
         E := (others => <>);
         Read_Element (Input, C, E);
         Take_Element (Input, C, E, I, Children, Into);
         pragma Loop_Invariant (Sound (C, Input));
      end loop;
      if C.Ok and then Children /= Integer_32 (Into.Columns) then
         Refuse (Into, C, Refused (Nested_Schema));
      end if;
   end Read_Schema;

   ---------------------------------------------------------------------
   --  ColumnMetaData and ColumnChunk
   ---------------------------------------------------------------------

   --  The encodings tessera reads: PLAIN, PLAIN_DICTIONARY, RLE (for
   --  levels) and RLE_DICTIONARY.
   function Read_Encoding (Code : Integer_32) return Boolean
   is (Code in 0 | 2 | 3 | 8);

   --  The encodings list: the first one outside the subset is kept.
   procedure Read_Encodings
     (Input : Bytes; C : in out Cursor; Into : in out Chunk_Info)
   with Post => Sound (C, Input);

   procedure Read_Encodings
     (Input : Bytes; C : in out Cursor; Into : in out Chunk_Info)
   is
      H    : List_Header;
      Code : Integer_32;
   begin
      Read_List_Header (Input, C, H);
      if C.Ok and then H.Element /= I32 then
         C.Ok := False;
      end if;
      for I in 1 .. H.Count loop
         exit when not C.Ok;
         Read_I32 (Input, C, Code);
         if C.Ok
           and then not Read_Encoding (Code)
           and then Into.Bad_Encoding = No_Encoding
         then
            Into.Bad_Encoding := Code;
         end if;
         pragma Loop_Invariant (Sound (C, Input));
      end loop;
   end Read_Encodings;

   --  1 type, 2 encodings, 4 codec, 5 num_values, 6 and 7 the total
   --  uncompressed and compressed sizes, 9 data_page_offset,
   --  11 dictionary_page_offset.
   function Meta_Known (H : Field_Header) return Boolean
   is ((H.Id in 1 | 4 and then H.Kind = I32)
       or else (H.Id = 2 and then H.Kind = List)
       or else (H.Id in 5 | 6 | 7 | 9 | 11 and then H.Kind = I64));

   procedure Read_Meta_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Chunk_Info;
      H     : Field_Header);

   procedure Read_Meta_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Chunk_Info;
      H     : Field_Header) is
   begin
      case H.Id is
         when 1      =>
            Read_I32 (Input, C, Into.Type_Code);

         when 2      =>
            Read_Encodings (Input, C, Into);

         when 4      =>
            Read_I32 (Input, C, Into.Codec_Code);

         when 5      =>
            Read_Offset (Input, C, Into.Values);

         when 6      =>
            Read_Offset (Input, C, Into.Uncompressed_Size);

         when 7      =>
            Read_Offset (Input, C, Into.Compressed_Size);

         when 9      =>
            Read_Offset (Input, C, Into.Data_Offset);

         when others =>
            Read_Offset (Input, C, Into.Start);
            Into.Has_Dictionary := True;
      end case;
   end Read_Meta_Field;

   procedure Read_Meta is new
     Read_Struct (Chunk_Info, Meta_Known, Read_Meta_Field);

   --  A chunk as read: its metadata, and whether it is encrypted.
   type Chunk_Read is record
      Info      : Chunk_Info;
      Encrypted : Boolean := False;
   end record;

   --  3 meta_data; 8 crypto_metadata and 9 encrypted_column_metadata
   --  mark an encrypted chunk.
   function Chunk_Known (H : Field_Header) return Boolean
   is (H.Id in 3 | 8 | 9 and then H.Kind = Struct);

   procedure Read_Chunk_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Chunk_Read;
      H     : Field_Header);

   procedure Read_Chunk_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Chunk_Read;
      H     : Field_Header) is
   begin
      if H.Id = 3 then
         Read_Meta (Input, C, Into.Info);
      else
         Into.Encrypted := True;
         Skip (Input, C, H.Kind);
      end if;
   end Read_Chunk_Field;

   procedure Read_Chunk is new
     Read_Struct (Chunk_Read, Chunk_Known, Read_Chunk_Field);

   --  Where a chunk's pages begin: its dictionary page when it has one
   --  (an offset of 0 is a writer's way of saying it has none).
   function Settled (Info : Chunk_Info) return Chunk_Info
   is (if Info.Has_Dictionary and then Info.Start > 0
       then Info
       else
         (Info with delta Start => Info.Data_Offset, Has_Dictionary => False));

   ---------------------------------------------------------------------
   --  RowGroup and FileMetaData
   ---------------------------------------------------------------------

   --  A row group as read: the chunks, the rows, and the first refusal.
   type Group_Read is record
      Info  : Group_Info;
      Fault : Outcome := Done;
   end record;

   procedure Read_Chunks
     (Input : Bytes; C : in out Cursor; Into : in out Group_Read)
   with Post => Sound (C, Input);

   procedure Read_Chunks
     (Input : Bytes; C : in out Cursor; Into : in out Group_Read)
   is
      H     : List_Header;
      Chunk : Chunk_Read;
   begin
      Read_List_Header (Input, C, H);
      if C.Ok and then (H.Element /= Struct or else H.Count > Max_Columns) then
         Into.Fault := Refused_With (Too_Large, 0, Integer_64 (H.Count));
         C.Ok := False;
      end if;
      for I in 1 .. H.Count loop
         exit when not C.Ok or else I > Max_Columns;
         Chunk := (others => <>);
         Read_Chunk (Input, C, Chunk);
         if Chunk.Encrypted then
            Into.Fault := Refused (Encrypted, I);
            C.Ok := False;
         end if;
         Into.Info.Chunks (I) := Settled (Chunk.Info);
         Into.Info.Count := I;
         pragma Loop_Invariant (Sound (C, Input));
      end loop;
   end Read_Chunks;

   --  1 columns, 3 num_rows.
   function Group_Known (H : Field_Header) return Boolean
   is ((H.Id = 1 and then H.Kind = List)
       or else (H.Id = 3 and then H.Kind = I64));

   procedure Read_Group_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Group_Read;
      H     : Field_Header);

   procedure Read_Group_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Group_Read;
      H     : Field_Header) is
   begin
      if H.Id = 1 then
         Read_Chunks (Input, C, Into);
      else
         Read_Offset (Input, C, Into.Info.Rows);
      end if;
   end Read_Group_Field;

   procedure Read_Group is new
     Read_Struct (Group_Read, Group_Known, Read_Group_Field);

   procedure Read_Groups
     (Input : Bytes; C : in out Cursor; Into : in out Metadata)
   with Post => Sound (C, Input);

   procedure Read_Groups
     (Input : Bytes; C : in out Cursor; Into : in out Metadata)
   is
      H     : List_Header;
      Group : Group_Read;
   begin
      Read_List_Header (Input, C, H);
      if C.Ok and then (H.Element /= Struct or else H.Count > Max_Row_Groups)
      then
         Refuse (Into, C, Refused_With (Too_Large, 0, Integer_64 (H.Count)));
      end if;
      for I in 1 .. H.Count loop
         exit when not C.Ok or else I > Max_Row_Groups;
         Group := (others => <>);
         Read_Group (Input, C, Group);
         if not Group.Fault.Ok then
            Refuse (Into, C, Group.Fault);
         end if;
         Into.Group (I) := Group.Info;
         Into.Groups := I;
         pragma Loop_Invariant (Sound (C, Input));
      end loop;
   end Read_Groups;

   --  2 schema, 3 num_rows, 4 row_groups; 8 encryption_algorithm marks a
   --  file whose footer is plain but whose columns are encrypted.
   function File_Known (H : Field_Header) return Boolean
   is ((H.Id in 2 | 4 and then H.Kind = List)
       or else (H.Id = 3 and then H.Kind = I64)
       or else (H.Id = 8 and then H.Kind = Struct));

   procedure Read_File_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Metadata;
      H     : Field_Header);

   procedure Read_File_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Metadata;
      H     : Field_Header) is
   begin
      case H.Id is
         when 2      =>
            Read_Schema (Input, C, Into);

         when 3      =>
            Read_Offset (Input, C, Into.Rows);

         when 4      =>
            Read_Groups (Input, C, Into);

         when others =>
            Refuse (Into, C, Refused (Encrypted));
      end case;
   end Read_File_Field;

   procedure Read_File is new
     Read_Struct (Metadata, File_Known, Read_File_Field);

   ---------------------------------------------------------------------
   --  The checks on what was decoded
   ---------------------------------------------------------------------

   --  The refusal one chunk earns as column Column of a row group of
   --  Rows rows, if any.
   function Chunk_Verdict
     (Info     : Chunk_Info;
      Column   : Column_Info;
      Number   : Column_Number;
      Rows     : File_Offset;
      Data_End : File_Offset) return Outcome
   is (if Info.Type_Code /= Physical_Type'Pos (Column.Kind)
         or else Info.Values /= Rows
       then Refused (Corrupt_Footer, Number)
       elsif Info.Codec_Code not in Uncompressed_Code | Snappy_Code
       then
         Refused_With (Unsupported_Codec, Number, Integer_64 (Info.Codec_Code))
       elsif Info.Bad_Encoding /= No_Encoding
       then
         Refused_With
           (Unsupported_Encoding, Number, Integer_64 (Info.Bad_Encoding))
       elsif Info.Compressed_Size > Max_Buffer
         or else Info.Uncompressed_Size > Max_Buffer
       then Refused (Too_Large, Number)
       elsif Info.Start < Magic_Size
         or else Info.Start > Data_End - Info.Compressed_Size
       then Refused (Corrupt_Footer, Number)
       else Done);

   --  The first refusal among the chunks of row group G, if any.
   function Group_Verdict
     (Meta : Metadata; G : Group_Number; Data_End : File_Offset) return Outcome
   with
     Post =>
       (if Group_Verdict'Result.Ok
        then Fits (Meta.Group (G), Meta.Columns, Data_End));

   function Group_Verdict
     (Meta : Metadata; G : Group_Number; Data_End : File_Offset) return Outcome
   is
      Verdict : Outcome := Done;
   begin
      for K in 1 .. Meta.Columns loop
         Verdict :=
           Chunk_Verdict
             (Meta.Group (G).Chunks (K),
              Meta.Schema (K),
              K,
              Meta.Group (G).Rows,
              Data_End);
         exit when not Verdict.Ok;
         pragma
           Loop_Invariant
             (for all J in 1 .. K =>
                Fits_One (Meta.Group (G).Chunks (J), Data_End));
      end loop;
      return Verdict;
   end Group_Verdict;

   procedure Check
     (Meta : Metadata; Data_End : File_Offset; Result : out Outcome)
   with
     Post =>
       (if Result.Ok
        then
          Valid (Meta)
          and then (for all G in 1 .. Meta.Groups =>
                      Fits (Meta.Group (G), Meta.Columns, Data_End)));

   procedure Check
     (Meta : Metadata; Data_End : File_Offset; Result : out Outcome)
   is
      Total : File_Offset := 0;
   begin
      Result := (if Meta.Columns = 0 then Refused (Corrupt_Footer) else Done);
      for G in 1 .. Meta.Groups loop
         exit when not Result.Ok;
         if Meta.Group (G).Count /= Meta.Columns
           or else Meta.Group (G).Rows > File_Offset'Last - Total
         then
            Result := Refused (Corrupt_Footer);
         elsif Meta.Group (G).Rows > Max_Group_Rows then
            Result := Refused_With (Too_Large, 0, Meta.Group (G).Rows);
         else
            Total := Total + Meta.Group (G).Rows;
            Result := Group_Verdict (Meta, G, Data_End);
         end if;
         pragma
           Loop_Invariant
             (if Result.Ok
                then
                  (for all J in 1 .. G =>
                     Meta.Group (J).Rows <= Max_Group_Rows
                     and then Meta.Group (J).Count = Meta.Columns
                     and then Fits (Meta.Group (J), Meta.Columns, Data_End)));
      end loop;
      if Result.Ok and then Total /= Meta.Rows then
         Result := Refused (Corrupt_Footer);
      end if;
   end Check;

   procedure Decode
     (Input    : Bytes;
      Data_End : File_Offset;
      Into     : in out Metadata;
      Result   : out Outcome)
   is
      C : Cursor;
   begin
      Into.Rows := 0;
      Into.Columns := 0;
      Into.Groups := 0;
      Into.Fault := Done;
      Read_File (Input, C, Into);
      if not Into.Fault.Ok then
         Result := Into.Fault;
      elsif not C.Ok then
         Result := Refused (Corrupt_Footer);
      else
         Check (Into, Data_End, Result);
      end if;
   end Decode;

   function Find (Meta : Metadata; Name : String) return Column_Count is
   begin
      for K in 1 .. Meta.Columns loop
         if Name_Of (Meta.Schema (K)) = Name then
            return K;
         end if;
      end loop;
      return 0;
   end Find;

end Tessera.Footer;
