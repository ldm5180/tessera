--  Reads one struct: each field header in turn, each field the caller
--  knows handed to Read_Field, each other field skipped, up to the stop.
--  Read_Field reads the field's value through the cursor (a nested
--  struct is another instance's call); whatever it leaves, the cursor
--  comes back sound.  A struct that never stops, or a field that cannot
--  be read, turns the cursor's Ok off.

generic
   type Target is limited private;
   --  True when Read_Field reads the field Header names.
   with function Known (Header : Field_Header) return Boolean;
   with
     procedure Read_Field
       (Input  : Bytes;
        C      : in out Cursor;
        Into   : in out Target;
        Header : Field_Header);
procedure Tessera.Thrift.Read_Struct
  (Input : Bytes; C : in out Cursor; Into : in out Target)
with SPARK_Mode, Post => Sound (C, Input) and then (if C.Ok then C'Old.Ok);
