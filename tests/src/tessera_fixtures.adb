with Ada.Directories;
with Ada.Streams.Stream_IO;

with Interfaces; use Interfaces;

with Tessera.Columns; use Tessera.Columns;

package body Tessera_Fixtures is

   Data_Dir : constant String := "tests/data/";

   function Load (Name : String) return Bytes_Access is
      use Ada.Streams.Stream_IO;
      Path   : constant String := Data_Dir & Name;
      Size   : constant Natural := Natural (Ada.Directories.Size (Path));
      Result : constant Bytes_Access := new Bytes (1 .. Size);
      File   : File_Type;
   begin
      Open (File, In_File, Path);
      Bytes'Read (Stream (File), Result.all);
      Close (File);
      return Result;
   end Load;

   procedure Footer_Of
     (File : Bytes; Meta : out Metadata_Access; Result : out Outcome)
   is
      Size   : constant File_Offset := File'Length;
      Length : Buffer_Count;
      Tail   : constant Bytes :=
        (if File'Length >= Tail_Size
         then File (File'Last - Tail_Size + 1 .. File'Last)
         else File);
   begin
      Meta := new Metadata;
      Locate (File, Tail, Size, Length, Result);
      if Result.Ok then
         declare
            Data_End : constant Natural := File'Length - Tail_Size - Length;
         begin
            Decode
              (File
                 (File'First + Data_End .. File'First + Data_End + Length - 1),
               Integer_64 (Data_End),
               Meta.all,
               Result);
         end;
      end if;
   end Footer_Of;

   function Open (Name : String) return Opened_File is
      Opened : Opened_File;
   begin
      Opened.File := Load (Name);
      Footer_Of (Opened.File.all, Opened.Meta, Opened.Result);
      return Opened;
   end Open;

   type Workspace_Access is access Workspace;

   function Width_Of (Kind : Physical_Type) return Plain_Width
   is (case Kind is
         when Bool            => One_Bit,
         when Int32 | Float32 => Four_Bytes,
         when others          => Eight_Bytes);

   function Read_Chunk
     (Opened : Opened_File; Group : Group_Number; Column : Column_Number)
      return Chunk_Read
   is
      Info  : constant Chunk_Info := Opened.Meta.Group (Group).Chunks (Column);
      Rows  : constant Natural := Natural (Opened.Meta.Group (Group).Rows);
      Size  : constant Natural := Natural (Info.Uncompressed_Size);
      Room  : constant Natural := Size / 4 + 1;
      Chunk : Bytes renames
        Opened.File
          (Natural (Info.Start)
           + 1
           .. Natural (Info.Start + Info.Compressed_Size));
      Space : constant Workspace_Access := new Workspace (Size, Rows);
      Read  : Chunk_Read :=
        (Number => Column,
         Rows   => Rows,
         Column => Opened.Meta.Schema (Column),
         others => <>);
      Shape : constant Chunk_Shape :=
        (Snappy   => Info.Codec_Code = Snappy_Code,
         Width    => Width_Of (Read.Column.Kind),
         Optional => Read.Column.Optional);
   begin
      if Read.Column.Kind = Byte_Array then
         Read.Text := new Text_Column (Rows, Room, Size, 2 * Room + 1);
         Read_Text (Chunk, Shape, Space.all, Read.Text.all, Read.Result);
      else
         Read.Words := new Word_Column (Rows, Room);
         Read_Words (Chunk, Shape, Space.all, Read.Words.all, Read.Result);
      end if;
      return Read;
   end Read_Chunk;

   Hex_Digits : constant String := "0123456789abcdef";

   --  0x and the Width hex figures of W.
   function Hex (W : Unsigned_64; Width : Positive) return String is
      Text : String (1 .. Width);
      V    : Unsigned_64 := W;
   begin
      for K in reverse Text'Range loop
         Text (K) := Hex_Digits (Natural (V mod 16) + 1);
         V := V / 16;
      end loop;
      return "0x" & Text;
   end Hex;

   function Trim (S : String) return String
   is (if S'Length > 0 and then S (S'First) = ' '
       then S (S'First + 1 .. S'Last)
       else S);

   function Render_Word (Column : Column_Info; W : Unsigned_64) return String
   is (case Column.Kind is
         when Bool    => (if W /= 0 then "true" else "false"),
         when Int32   =>
           (if Column.Note = Uint_32
            then Trim (W'Image)
            else Trim (Signed_32 (W)'Image)),
         when Int64   =>
           (if Column.Note = Uint_64
            then Trim (W'Image)
            else Trim (Signed_64 (W)'Image)),
         when Float32 => Hex (W, 8),
         when others  => Hex (W, 16));

   function Render (Read : Chunk_Read; Row : Positive) return String is
   begin
      if Read.Text /= null then
         return
           (if Read.Text.Valid (Row)
            then Text (Read.Text.all, Read.Text.Code (Row))
            else "<null>");
      end if;
      return
        (if Read.Words.Valid (Row)
         then Render_Word (Read.Column, Read.Words.Value (Row))
         else "<null>");
   end Render;

end Tessera_Fixtures;
