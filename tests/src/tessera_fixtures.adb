with Ada.Directories;
with Ada.Streams.Stream_IO;

with Interfaces;

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
               Interfaces.Integer_64 (Data_End),
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

end Tessera_Fixtures;
