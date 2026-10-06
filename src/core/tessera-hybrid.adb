with Tessera.Thrift; use Tessera.Thrift;

package body Tessera.Hybrid
  with SPARK_Mode
is

   --  Values in one group of a packed run.
   Group_Size : constant := 8;
   Byte_Bits  : constant := 8;

   --  The whole bytes Width bits take.
   function Byte_Width (Width : Bit_Width) return Natural
   is ((Width + Byte_Bits - 1) / Byte_Bits);

   --  The largest value Width bits hold.
   function Ceiling (Width : Bit_Width) return Unsigned_64
   is (Shift_Left (1, Width) - 1);

   --  A decode under way: the width of its values, how many are wanted,
   --  and how many are done, which is where the next one goes.
   type Progress is record
      Width : Bit_Width := 0;
      Done  : Buffer_Count := 0;
      Count : Buffer_Count := 0;
   end record;

   function Wanted (P : Progress) return Buffer_Count
   is (P.Count - P.Done)
   with Pre => P.Done <= P.Count;

   --  A repeated run: Length copies of the value that follows.
   procedure Repeated
     (Input  : Bytes;
      C      : in out Cursor;
      Length : Unsigned_64;
      Values : in out Codes;
      P      : in out Progress)
   with
     Pre  =>
       P.Done <= P.Count
       and then P.Count <= Values'Length
       and then Sound (C, Input),
     Post =>
       Sound (C, Input)
       and then P.Count = P.Count'Old
       and then P.Width = P.Width'Old
       and then P.Done in P.Done'Old .. P.Count;

   procedure Repeated
     (Input  : Bytes;
      C      : in out Cursor;
      Length : Unsigned_64;
      Values : in out Codes;
      P      : in out Progress)
   is
      Value : Unsigned_64 := 0;
      B     : Byte;
      Take  : Buffer_Count;
   begin
      for K in 0 .. Byte_Width (P.Width) - 1 loop
         Read_Byte (Input, C, B);
         Value := Value or Shift_Left (Unsigned_64 (B), Byte_Bits * K);
         pragma Loop_Invariant (Sound (C, Input) and then Value < 2**32);
      end loop;
      if not C.Ok or else Value > Ceiling (P.Width) then
         C.Ok := False;
         return;
      end if;
      Take :=
        Buffer_Count (Unsigned_64'Min (Length, Unsigned_64 (Wanted (P))));
      for K in P.Done .. P.Done + Take - 1 loop
         Values (Values'First + K) := Unsigned_32 (Value);
      end loop;
      P.Done := P.Done + Take;
   end Repeated;

   --  The value Width bits wide at bit Bit of the run starting at byte
   --  Base of Input.
   function Bits_At
     (Input : Bytes; Base : Buffer_Count; Bit : Integer_64; Width : Bit_Width)
      return Unsigned_32
   with
     Pre =>
       Width > 0
       and then Bit >= 0
       and then Base <= Input'Length
       and then Bit <= Integer_64 (Max_Buffer) * Byte_Bits
       and then (Bit + Integer_64 (Width) - 1) / Byte_Bits
                < Integer_64 (Input'Length - Base);

   function Bits_At
     (Input : Bytes; Base : Buffer_Count; Bit : Integer_64; Width : Bit_Width)
      return Unsigned_32
   is
      First : constant Natural := Natural (Bit / Byte_Bits);
      Last  : constant Natural :=
        Natural ((Bit + Integer_64 (Width) - 1) / Byte_Bits);
      Acc   : Unsigned_64 := 0;
   begin
      for K in First .. Last loop
         Acc :=
           Acc
           or Shift_Left
                (Unsigned_64 (Byte_At (Input, Base + K)),
                 Byte_Bits * (K - First));
      end loop;
      return
        Unsigned_32
          (Shift_Right (Acc, Natural (Bit mod Byte_Bits)) and Ceiling (Width));
   end Bits_At;

   --  A bit-packed run of Groups groups of eight; the values asked for are
   --  taken, the rest stepped over.
   procedure Packed
     (Input  : Bytes;
      C      : in out Cursor;
      Groups : Unsigned_64;
      Values : in out Codes;
      P      : in out Progress)
   with
     Pre  =>
       P.Done <= P.Count
       and then P.Count <= Values'Length
       and then Sound (C, Input),
     Post =>
       Sound (C, Input)
       and then P.Count = P.Count'Old
       and then P.Width = P.Width'Old
       and then P.Done in P.Done'Old .. P.Count;

   procedure Packed
     (Input  : Bytes;
      C      : in out Cursor;
      Groups : Unsigned_64;
      Values : in out Codes;
      P      : in out Progress)
   is
      Run   : constant Unsigned_64 :=
        Unsigned_64'Min (Groups, Max_Buffer) * Group_Size;
      Take  : constant Buffer_Count :=
        Buffer_Count (Unsigned_64'Min (Run, Unsigned_64 (Wanted (P))));
      Needs : constant Integer_64 :=
        (Integer_64 (Take) * Integer_64 (P.Width) + Byte_Bits - 1) / Byte_Bits;
      Base  : constant Buffer_Count := C.Pos;
   begin
      if not C.Ok or else Needs > Integer_64 (Left (C, Input)) then
         C.Ok := False;
         return;
      end if;
      for K in 0 .. Take - 1 loop
         Values (Values'First + P.Done + K) :=
           (if P.Width = 0
            then 0
            else
              Bits_At
                (Input, Base, Integer_64 (K) * Integer_64 (P.Width), P.Width));
      end loop;
      P.Done := P.Done + Take;
      C.Pos :=
        C.Pos
        + Natural
            (Integer_64'Min
               (Integer_64 (Left (C, Input)),
                Integer_64 (Unsigned_64'Min (Groups, Max_Buffer))
                * Integer_64 (P.Width)));
   end Packed;

   procedure Decode
     (Input  : Bytes;
      Width  : Bit_Width;
      Count  : Buffer_Count;
      Values : in out Codes;
      Result : out Outcome)
   is
      C      : Cursor;
      P      : Progress := (Width => Width, Done => 0, Count => Count);
      Header : Unsigned_64;
   begin
      for Run in 1 .. Input'Length loop
         exit when P.Done = Count or else not C.Ok;
         Read_Varint (Input, C, Header);
         exit when not C.Ok;
         if Header mod 2 = 0 then
            Repeated (Input, C, Header / 2, Values, P);
         else
            Packed (Input, C, Header / 2, Values, P);
         end if;
         pragma
           Loop_Invariant
             (Sound (C, Input)
                and then P.Count = Count
                and then P.Done <= Count);
      end loop;
      Result :=
        (if C.Ok and then P.Done = Count
         then Done
         else Refused (Corrupt_Page));
   end Decode;

end Tessera.Hybrid;
