with Ada.Directories;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;

with Tessera.Pages;

package body Tessera.Files is

   use Ada.Strings.Unbounded;
   use type Interfaces.Integer_32;
   use type Interfaces.Integer_64;
   use Tessera.Footer;
   use Tessera.Pages;

   type Bytes_Access is access Bytes;
   type Workspace_Access is access Tessera.Columns.Workspace;
   type Word_Access is access Word_Column;

   procedure Free_Bytes is new
     Ada.Unchecked_Deallocation (Bytes, Bytes_Access);
   procedure Free_Space is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Workspace, Workspace_Access);
   procedure Free_Words is new
     Ada.Unchecked_Deallocation (Word_Column, Word_Access);
   procedure Free_Meta is new
     Ada.Unchecked_Deallocation (Footer.Metadata, Metadata_Access);

   ---------------------------------------------------------------------
   --  The disk
   ---------------------------------------------------------------------

   --  Length bytes of the file at Path from offset From into Into, a new
   --  buffer; null and Cannot_Read when the disk will not give them all.
   procedure Read_Range
     (Path   : String;
      From   : File_Offset;
      Length : Buffer_Count;
      Into   : out Bytes_Access;
      Result : out Outcome)
   is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;
      Handle : File_Type;
      Last   : Stream_Element_Offset;
   begin
      Into := new Bytes (1 .. Length);
      Result := Done;
      --  Separate, not shared: another task may hold the same file open,
      --  and GNAT refuses to reopen a shared one.
      Open (Handle, In_File, Path, Form => "shared=no");
      Set_Index (Handle, Positive_Count (From + 1));
      declare
         Raw : Stream_Element_Array (1 .. Stream_Element_Offset (Length))
         with Import, Address => Into.all'Address;
      begin
         Read (Handle, Raw, Last);
      end;
      Close (Handle);
      if Last /= Stream_Element_Offset (Length) then
         Free_Bytes (Into);
         Result := Refused (Cannot_Read);
      end if;
   exception
      when
        Ada.IO_Exceptions.Name_Error
        | Ada.IO_Exceptions.Use_Error
        | Ada.IO_Exceptions.Device_Error
        | Ada.IO_Exceptions.End_Error
      =>
         if Is_Open (Handle) then
            Close (Handle);
         end if;
         Free_Bytes (Into);
         Result := Refused (Cannot_Read);
      when Storage_Error =>
         Free_Bytes (Into);
         Result := Refused_With (Too_Large, 0, Interfaces.Integer_64 (Length));
   end Read_Range;

   --  The size of the file at Path; Cannot_Read when there is none.
   procedure Size_Of
     (Path : String; Size : out File_Offset; Result : out Outcome) is
   begin
      Size := File_Offset (Ada.Directories.Size (Path));
      Result := Done;
   exception
      when Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Size := 0;
         Result := Refused (Cannot_Read);
   end Size_Of;

   ---------------------------------------------------------------------
   --  Open
   ---------------------------------------------------------------------

   --  The first and last bytes of a file of Size bytes, located: the
   --  footer's length.
   procedure Locate_Footer
     (Path   : String;
      Size   : File_Offset;
      Length : out Buffer_Count;
      Result : out Outcome)
   is
      Head_Size : constant Buffer_Count :=
        Buffer_Count (File_Offset'Min (Size, Magic_Size));
      Tail_Room : constant Buffer_Count :=
        Buffer_Count (File_Offset'Min (Size, Tail_Size));
      Head      : Bytes_Access;
      Tail      : Bytes_Access;
   begin
      Length := 0;
      Read_Range (Path, 0, Head_Size, Head, Result);
      if Result.Ok then
         Read_Range
           (Path, Size - File_Offset (Tail_Room), Tail_Room, Tail, Result);
      end if;
      if Result.Ok then
         Locate (Head.all, Tail.all, Size, Length, Result);
      end if;
      Free_Bytes (Head);
      Free_Bytes (Tail);
   end Locate_Footer;

   procedure Open (Path : String; F : in out File; Result : out Outcome) is
      Size     : File_Offset;
      Length   : Buffer_Count;
      Data_End : File_Offset;
      Input    : Bytes_Access;
   begin
      Close (F);
      Size_Of (Path, Size, Result);
      if Result.Ok then
         Locate_Footer (Path, Size, Length, Result);
      end if;
      if not Result.Ok then
         return;
      end if;
      Data_End := Size - Tail_Size - File_Offset (Length);
      Read_Range (Path, Data_End, Length, Input, Result);
      if not Result.Ok then
         return;
      end if;
      F.Meta := new Footer.Metadata;
      Decode (Input.all, Data_End, F.Meta.all, Result);
      Free_Bytes (Input);
      if Result.Ok then
         F.Path := To_Unbounded_String (Path);
      else
         Free_Meta (F.Meta);
      end if;
   exception
      when Storage_Error =>
         Free_Bytes (Input);
         Free_Meta (F.Meta);
         Result := Refused (Too_Large);
   end Open;

   function Is_Open (F : File) return Boolean
   is (F.Meta /= null);

   function Rows (F : File) return Interfaces.Integer_64
   is (if F.Meta = null then 0 else F.Meta.Rows);

   function Row_Groups (F : File) return Footer.Group_Count
   is (if F.Meta = null then 0 else F.Meta.Groups);

   function Group_Rows (F : File; Group : Positive) return Natural
   is (if Group > Row_Groups (F)
       then 0
       else Natural (F.Meta.Group (Group).Rows));

   function Column_Total (F : File) return Column_Count
   is (if F.Meta = null then 0 else F.Meta.Columns);

   function Column (F : File; Number : Column_Number) return Footer.Column_Info
   is (if Number > Column_Total (F)
       then (others => <>)
       else F.Meta.Schema (Number));

   function Chunk_Bytes
     (F : File; Group : Positive; Number : Column_Number)
      return Interfaces.Integer_64
   is (if Group > Row_Groups (F) or else Number > Column_Total (F)
       then 0
       else F.Meta.Group (Group).Chunks (Number).Compressed_Size);

   function Find (F : File; Name : String) return Column_Count
   is (if F.Meta = null then 0 else Footer.Find (F.Meta.all, Name));

   procedure Close (F : in out File) is
   begin
      Free_Meta (F.Meta);
      F.Path := Null_Unbounded_String;
   end Close;

   overriding
   procedure Finalize (F : in out File) is
   begin
      Close (F);
   end Finalize;

   ---------------------------------------------------------------------
   --  Reading a chunk
   ---------------------------------------------------------------------

   --  The column a read names, and its chunk in the row group asked for;
   --  or, in Result, why there is none to read.
   type Located_Chunk is record
      Number : Column_Number := 1;
      Info   : Chunk_Info;
      Rows   : Footer.Row_Count := 0;
      Shape  : Tessera.Columns.Chunk_Shape;
      Result : Outcome;
   end record;

   function Width_Of (Kind : Physical_Type) return Plain_Width
   is (case Kind is
         when Bool            => One_Bit,
         when Int32 | Float32 => Four_Bytes,
         when others          => Eight_Bytes);

   --  The refusal reading column Number as Kind earns, if any.
   function Column_Verdict
     (F : File; Number : Column_Count; Kind : Physical_Type) return Outcome
   is (if Number = 0
       then Refused (No_Such_Column)
       elsif F.Meta.Schema (Number).Kind /= Kind
       then
         Refused_With
           (Wrong_Type,
            Number,
            Physical_Type'Pos (F.Meta.Schema (Number).Kind))
       elsif F.Meta.Schema (Number).Note = Other
       then Refused (Unsupported_Type, Number)
       else Done);

   --  The chunk of column Name in row group Group, to be read as Kind.
   function Locate_Chunk
     (F : File; Group : Positive; Name : String; Kind : Physical_Type)
      return Located_Chunk
   is
      Number : constant Column_Count := Find (F, Name);
      Chunk  : Located_Chunk;
   begin
      if Group > Row_Groups (F) then
         Chunk.Result :=
           Refused_With (No_Such_Row_Group, 0, Interfaces.Integer_64 (Group));
         return Chunk;
      end if;
      Chunk.Result := Column_Verdict (F, Number, Kind);
      if Chunk.Result.Ok then
         Chunk :=
           (Number => Number,
            Info   => F.Meta.Group (Group).Chunks (Number),
            Rows   => Natural (F.Meta.Group (Group).Rows),
            Shape  =>
              (Snappy   =>
                 F.Meta.Group (Group).Chunks (Number).Codec_Code = Snappy_Code,
               Width    => Width_Of (Kind),
               Optional => F.Meta.Schema (Number).Optional),
            Result => Done);
      end if;
      return Chunk;
   end Locate_Chunk;

   --  How many dictionary values or byte arrays a chunk of Size plain
   --  bytes can hold: each takes at least four.
   function Room (Size : Buffer_Count) return Buffer_Count
   is (Size / 4 + 1);

   --  A chunk's bytes, a workspace to read them in, and whether the disk
   --  gave them.
   type Prepared is record
      Input  : Bytes_Access;
      Space  : Workspace_Access;
      Result : Outcome;
   end record;

   function Prepare (F : File; Chunk : Located_Chunk) return Prepared is
      Ready : Prepared;
   begin
      Read_Range
        (To_String (F.Path),
         Chunk.Info.Start,
         Buffer_Count (Chunk.Info.Compressed_Size),
         Ready.Input,
         Ready.Result);
      if Ready.Result.Ok then
         Ready.Space :=
           new Tessera.Columns.Workspace
                 (Buffer_Count (Chunk.Info.Uncompressed_Size), Chunk.Rows);
      end if;
      return Ready;
   end Prepare;

   procedure Release (Ready : in out Prepared) is
   begin
      Free_Bytes (Ready.Input);
      Free_Space (Ready.Space);
   end Release;

   --  The refusal R, naming column Number.
   function Naming (R : Outcome; Number : Column_Number) return Outcome
   is (if R.Ok then R else (R with delta Column => Number));

   --  A located chunk read into a new word column.
   procedure Read_Word_Column
     (F      : File;
      Chunk  : Located_Chunk;
      Into   : out Word_Access;
      Result : out Outcome)
   is
      Ready : Prepared := Prepare (F, Chunk);
   begin
      Into := null;
      Result := Ready.Result;
      if Result.Ok then
         Into :=
           new Word_Column
                 (Chunk.Rows,
                  Room (Buffer_Count (Chunk.Info.Uncompressed_Size)));
         Tessera.Columns.Read_Words
           (Ready.Input.all, Chunk.Shape, Ready.Space.all, Into.all, Result);
         Result := Naming (Result, Chunk.Number);
      end if;
      Release (Ready);
      if not Result.Ok then
         Free_Words (Into);
      end if;
   exception
      when Storage_Error =>
         Release (Ready);
         Free_Words (Into);
         Result := Refused (Too_Large, Chunk.Number);
   end Read_Word_Column;

   --  Reads a fixed-width column of physical type Kind into a new typed
   --  column, through Convert.
   generic
      type Typed (<>) is limited private;
      type Typed_Access is access Typed;
      Kind : Physical_Type;
      with function Make (Rows : Footer.Row_Count) return Typed_Access;
      with procedure Convert (From : Word_Column; Into : in out Typed);
   procedure Read_Typed
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Typed_Access;
      Result : out Outcome);

   procedure Read_Typed
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Typed_Access;
      Result : out Outcome)
   is
      Chunk : constant Located_Chunk := Locate_Chunk (F, Group, Name, Kind);
      Words : Word_Access;
   begin
      Into := null;
      Result := Chunk.Result;
      if Result.Ok then
         Read_Word_Column (F, Chunk, Words, Result);
      end if;
      if Result.Ok then
         Into := Make (Words.Rows);
         Convert (Words.all, Into.all);
      end if;
      Free_Words (Words);
   exception
      when Storage_Error =>
         Free_Words (Words);
         Result := Refused (Too_Large);
   end Read_Typed;

   function New_Truths (Rows : Footer.Row_Count) return Truths_Access
   is (new Tessera.Columns.Truths (Rows));

   function New_Ints_32 (Rows : Footer.Row_Count) return Ints_32_Access
   is (new Tessera.Columns.Ints_32 (Rows));

   function New_Ints_64 (Rows : Footer.Row_Count) return Ints_64_Access
   is (new Tessera.Columns.Ints_64 (Rows));

   function New_Bits_32 (Rows : Footer.Row_Count) return Bits_32_Access
   is (new Tessera.Columns.Bits_32 (Rows));

   function New_Bits_64 (Rows : Footer.Row_Count) return Bits_64_Access
   is (new Tessera.Columns.Bits_64 (Rows));

   procedure Typed_Truths is new
     Read_Typed
       (Tessera.Columns.Truths,
        Truths_Access,
        Bool,
        New_Truths,
        Tessera.Columns.To_Truths);
   procedure Typed_Ints_32 is new
     Read_Typed
       (Tessera.Columns.Ints_32,
        Ints_32_Access,
        Int32,
        New_Ints_32,
        Tessera.Columns.To_Ints_32);
   procedure Typed_Ints_64 is new
     Read_Typed
       (Tessera.Columns.Ints_64,
        Ints_64_Access,
        Int64,
        New_Ints_64,
        Tessera.Columns.To_Ints_64);
   procedure Typed_Bits_32 is new
     Read_Typed
       (Tessera.Columns.Bits_32,
        Bits_32_Access,
        Float32,
        New_Bits_32,
        Tessera.Columns.To_Bits_32);
   procedure Typed_Bits_64 is new
     Read_Typed
       (Tessera.Columns.Bits_64,
        Bits_64_Access,
        Float64,
        New_Bits_64,
        Tessera.Columns.To_Bits_64);

   procedure Read_Truths
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Truths_Access;
      Result : out Outcome)
   renames Typed_Truths;

   procedure Read_Ints_32
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Ints_32_Access;
      Result : out Outcome)
   renames Typed_Ints_32;

   procedure Read_Ints_64
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Ints_64_Access;
      Result : out Outcome)
   renames Typed_Ints_64;

   procedure Read_Bits_32
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Bits_32_Access;
      Result : out Outcome)
   renames Typed_Bits_32;

   procedure Read_Bits_64
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Bits_64_Access;
      Result : out Outcome)
   renames Typed_Bits_64;

   --  A located chunk read into a new coded column.
   procedure Read_Coded_Column
     (F      : File;
      Chunk  : Located_Chunk;
      Into   : out Coded_Access;
      Result : out Outcome)
   is
      Size    : constant Buffer_Count :=
        Buffer_Count (Chunk.Info.Uncompressed_Size);
      Entries : constant Buffer_Count := Room (Size);
      Ready   : Prepared := Prepare (F, Chunk);
   begin
      Into := null;
      Result := Ready.Result;
      if Result.Ok then
         Into :=
           new Tessera.Columns.Coded
                 (Chunk.Rows, Entries, Size, 2 * Entries + 1);
         Tessera.Columns.Read_Text
           (Ready.Input.all, Chunk.Shape, Ready.Space.all, Into.all, Result);
         Result := Naming (Result, Chunk.Number);
      end if;
      Release (Ready);
      if not Result.Ok then
         Free (Into);
      end if;
   exception
      when Storage_Error =>
         Release (Ready);
         Free (Into);
         Result := Refused (Too_Large, Chunk.Number);
   end Read_Coded_Column;

   procedure Read_Coded
     (F      : File;
      Group  : Positive;
      Name   : String;
      Into   : out Coded_Access;
      Result : out Outcome)
   is
      Chunk : constant Located_Chunk :=
        Locate_Chunk (F, Group, Name, Byte_Array);
   begin
      Into := null;
      Result := Chunk.Result;
      if Result.Ok then
         Read_Coded_Column (F, Chunk, Into, Result);
      end if;
   end Read_Coded;

   procedure Free_Truths is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Truths, Truths_Access);
   procedure Free_Ints_32 is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Ints_32, Ints_32_Access);
   procedure Free_Ints_64 is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Ints_64, Ints_64_Access);
   procedure Free_Bits_32 is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Bits_32, Bits_32_Access);
   procedure Free_Bits_64 is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Bits_64, Bits_64_Access);
   procedure Free_Coded is new
     Ada.Unchecked_Deallocation (Tessera.Columns.Coded, Coded_Access);

   procedure Free (Column : in out Truths_Access) is
   begin
      Free_Truths (Column);
   end Free;
   procedure Free (Column : in out Ints_32_Access) is
   begin
      Free_Ints_32 (Column);
   end Free;
   procedure Free (Column : in out Ints_64_Access) is
   begin
      Free_Ints_64 (Column);
   end Free;
   procedure Free (Column : in out Bits_32_Access) is
   begin
      Free_Bits_32 (Column);
   end Free;
   procedure Free (Column : in out Bits_64_Access) is
   begin
      Free_Bits_64 (Column);
   end Free;
   procedure Free (Column : in out Coded_Access) is
   begin
      Free_Coded (Column);
   end Free;

end Tessera.Files;
