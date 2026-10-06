with Ada.Directories;

package body Tessera_World is

   function Data_Dir (Info : Fabula.Frames.Frame) return String is
      use Ada.Directories;
      File     : constant String := Fabula.Frames.Value (Info.File);
      Features : constant String := Containing_Directory (File);
   begin
      return Containing_Directory (Features) & "/data";
   end Data_Dir;

   procedure Open (Path : String) is
      Name : constant String := Ada.Directories.Simple_Name (Path);
   begin
      Tessera_Fixtures.Open (Name, Opened.File, Opened.Meta, Opened.Result);
   end Open;

   function Type_Name (Kind : Physical_Type) return String
   is (case Kind is
         when Bool                 => "BOOLEAN",
         when Int32                => "INT32",
         when Int64                => "INT64",
         when Int96                => "INT96",
         when Float32              => "FLOAT",
         when Float64              => "DOUBLE",
         when Byte_Array           => "BYTE_ARRAY",
         when Fixed_Len_Byte_Array => "FIXED_LEN_BYTE_ARRAY");

   --  The bit width an integer annotation names.
   function Width (Note : Annotation) return String
   is (case Note is
         when Int_8 | Uint_8   => "8",
         when Int_16 | Uint_16 => "16",
         when Int_32 | Uint_32 => "32",
         when others           => "64");

   function Note_Name (Note : Annotation) return String
   is (case Note is
         when None              => "",
         when Text              => "STRING",
         when Date              => "DATE",
         when Time_Micros       => "TIME MICROS",
         when Timestamp_Micros  => "TIMESTAMP MICROS",
         when Int_8 .. Int_64   => "SIGNED " & Width (Note),
         when Uint_8 .. Uint_64 => "UNSIGNED " & Width (Note),
         when Other             => "OTHER");

end Tessera_World;
