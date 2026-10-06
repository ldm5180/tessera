with Tessera.Thrift; use Tessera.Thrift;
with Tessera.Thrift.Read_Struct;

package body Tessera.Pages
  with SPARK_Mode
is

   ---------------------------------------------------------------------
   --  PageHeader
   ---------------------------------------------------------------------

   --  A DataPageHeader or DictionaryPageHeader as read: field 1 the
   --  values, 2 their encoding, and (data pages) 3 the levels' encoding.
   type Sub_Header is record
      Values         : Integer_32 := -1;
      Encoding       : Integer_32 := Plain_Encoding;
      Level_Encoding : Integer_32 := Rle_Encoding;
   end record;

   function Sub_Known (H : Field_Header) return Boolean
   is (H.Id in 1 .. 3 and then H.Kind = I32);

   procedure Read_Sub_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Sub_Header;
      H     : Field_Header);

   procedure Read_Sub_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Sub_Header;
      H     : Field_Header) is
   begin
      case H.Id is
         when 1      =>
            Read_I32 (Input, C, Into.Values);

         when 2      =>
            Read_I32 (Input, C, Into.Encoding);

         when others =>
            Read_I32 (Input, C, Into.Level_Encoding);
      end case;
   end Read_Sub_Field;

   procedure Read_Sub is new
     Read_Struct (Sub_Header, Sub_Known, Read_Sub_Field);

   --  A PageHeader as read: 1 type, 2 and 3 the sizes, 5 the data page
   --  header, 7 the dictionary page header.  The CRC, the index header
   --  and the version 2 header are skipped; the type says which it is.
   type Header_Read is record
      Type_Code    : Integer_32 := -1;
      Uncompressed : Integer_32 := -1;
      Compressed   : Integer_32 := -1;
      Sub          : Sub_Header;
      Has_Sub      : Boolean := False;
   end record;

   Data_Header_Field       : constant := 5;
   Dictionary_Header_Field : constant := 7;

   function Header_Known (H : Field_Header) return Boolean
   is ((H.Id in 1 .. 3 and then H.Kind = I32)
       or else (H.Id in Data_Header_Field | Dictionary_Header_Field
                and then H.Kind = Struct));

   procedure Read_Header_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Header_Read;
      H     : Field_Header);

   procedure Read_Header_Field
     (Input : Bytes;
      C     : in out Cursor;
      Into  : in out Header_Read;
      H     : Field_Header) is
   begin
      case H.Id is
         when 1      =>
            Read_I32 (Input, C, Into.Type_Code);

         when 2      =>
            Read_I32 (Input, C, Into.Uncompressed);

         when 3      =>
            Read_I32 (Input, C, Into.Compressed);

         when others =>
            Read_Sub (Input, C, Into.Sub);
            Into.Has_Sub := True;
      end case;
   end Read_Header_Field;

   procedure Read_Page_Header is new
     Read_Struct (Header_Read, Header_Known, Read_Header_Field);

   --  True when a header as read is whole: a known type, sizes and a
   --  value count that are not negative, and the sub-header its type
   --  needs.
   function Whole (R : Header_Read) return Boolean
   is (R.Type_Code in 0 .. 3
       and then R.Uncompressed in 0 .. Max_Buffer
       and then R.Compressed in 0 .. Max_Buffer
       and then (R.Has_Sub
                 or else Page_Kind'Val (R.Type_Code)
                         in Index_Page | Data_Page_V2)
       and then (if R.Has_Sub then R.Sub.Values in 0 .. Max_Buffer));

   procedure Read_Header
     (Input  : Bytes;
      C      : in out Thrift.Cursor;
      H      : out Header;
      Result : out Outcome)
   is
      R : Header_Read;
   begin
      H := (others => <>);
      Read_Page_Header (Input, C, R);
      if not C.Ok
        or else not Whole (R)
        or else Natural (R.Compressed) > Left (C, Input)
      then
         C.Ok := False;
         Result := Refused (Corrupt_Page);
         return;
      end if;
      H :=
        (Kind           => Page_Kind'Val (R.Type_Code),
         Uncompressed   => Natural (R.Uncompressed),
         Compressed     => Natural (R.Compressed),
         Values         =>
           (if R.Sub.Values in 1 .. Max_Buffer
            then Natural (R.Sub.Values)
            else 0),
         Encoding       => R.Sub.Encoding,
         Level_Encoding => R.Sub.Level_Encoding);
      Result := Done;
   end Read_Header;

   ---------------------------------------------------------------------
   --  Levels
   ---------------------------------------------------------------------

   Length_Size : constant := 4;

   --  The four little-endian bytes at offset At of Page, as a count; Ok
   --  False when they are not all there or name more than a buffer.
   procedure Read_Length
     (Page    : Bytes;
      At_Byte : Natural;
      Length  : out Buffer_Count;
      Ok      : out Boolean)
   with Post => (if Ok then At_Byte <= Page'Length - Length_Size);

   procedure Read_Length
     (Page    : Bytes;
      At_Byte : Natural;
      Length  : out Buffer_Count;
      Ok      : out Boolean)
   is
      Value : Unsigned_64 := 0;
   begin
      Length := 0;
      Ok :=
        Page'Length >= Length_Size
        and then At_Byte <= Page'Length - Length_Size;
      if not Ok then
         return;
      end if;
      for K in 0 .. Length_Size - 1 loop
         Value :=
           Value
           or Shift_Left (Unsigned_64 (Byte_At (Page, At_Byte + K)), 8 * K);
      end loop;
      Ok := Value <= Max_Buffer;
      if Ok then
         Length := Buffer_Count (Value);
      end if;
   end Read_Length;

   --  Where a data page's values start, and how many of its rows hold one.
   type Level_Read is record
      Values_At : Buffer_Count := 0;
      Present   : Buffer_Count := 0;
   end record;

   --  A data page as laid out: how it is read, and where its values are.
   type Layout is record
      Plan   : Page_Plan;
      Levels : Level_Read;
   end record;

   function Rows_Of (L : Layout) return Buffer_Count
   is (L.Plan.H.Values);

   --  The levels at the start of Page into Scratch, one per row, and
   --  where the values start; every row valid when the plan has no levels.
   procedure Read_Levels
     (Page    : Bytes;
      Plan    : Page_Plan;
      Scratch : in out Codes;
      Levels  : out Level_Read;
      Result  : out Outcome)
   with
     Pre  => Plan.H.Values <= Scratch'Length,
     Post => (if Result.Ok then Levels.Present <= Plan.H.Values);

   procedure Read_Levels
     (Page    : Bytes;
      Plan    : Page_Plan;
      Scratch : in out Codes;
      Levels  : out Level_Read;
      Result  : out Outcome)
   is
      Count  : constant Buffer_Count := Plan.H.Values;
      Length : Buffer_Count;
      Ok     : Boolean;
   begin
      Levels := (Values_At => 0, Present => Count);
      Result := Done;
      if not Plan.Optional then
         return;
      elsif Plan.H.Level_Encoding /= Rle_Encoding then
         Result :=
           Refused_With
             (Unsupported_Encoding, 0, Integer_64 (Plan.H.Level_Encoding));
         return;
      end if;
      Read_Length (Page, 0, Length, Ok);
      if not Ok or else Length > Page'Length - Length_Size then
         Result := Refused (Corrupt_Page);
         return;
      end if;
      Decode
        (Page
           (Page'First + Length_Size .. Page'First + Length_Size + Length - 1),
         1,
         Count,
         Scratch,
         Result);
      Levels := (Values_At => Length_Size + Length, Present => 0);
      for K in 0 .. Count - 1 loop
         if Scratch (Scratch'First + K) = 1 then
            Levels.Present := Levels.Present + 1;
         end if;
         pragma Loop_Invariant (Levels.Present <= K + 1);
      end loop;
   end Read_Levels;

   --  Marks the page's rows, Valid, from the levels in Scratch, or all
   --  valid when the plan has none.
   procedure Mark_Valid
     (Plan : Page_Plan; Scratch : Codes; Valid : in out Flags)
   with
     Pre =>
       Plan.H.Values <= Scratch'Length and then Valid'Length = Plan.H.Values;

   procedure Mark_Valid
     (Plan : Page_Plan; Scratch : Codes; Valid : in out Flags) is
   begin
      for K in 0 .. Valid'Length - 1 loop
         Valid (Valid'First + K) :=
           not Plan.Optional or else Scratch (Scratch'First + K) = 1;
      end loop;
   end Mark_Valid;

   --  Lays out a data page: its levels read, and Valid, its rows, marked.
   procedure Lay_Out
     (Page    : Bytes;
      L       : in out Layout;
      Valid   : in out Flags;
      Scratch : in out Codes;
      Result  : out Outcome)
   with
     Pre  => Rows_Of (L) <= Scratch'Length and then Valid'Length = Rows_Of (L),
     Post =>
       L.Plan = L.Plan'Old
       and then (if Result.Ok then L.Levels.Present <= Rows_Of (L));

   procedure Lay_Out
     (Page    : Bytes;
      L       : in out Layout;
      Valid   : in out Flags;
      Scratch : in out Codes;
      Result  : out Outcome) is
   begin
      Read_Levels (Page, L.Plan, Scratch, L.Levels, Result);
      if Result.Ok then
         Mark_Valid (L.Plan, Scratch, Valid);
      end if;
   end Lay_Out;

   --  The refusal a data page's value encoding earns, if it is neither
   --  PLAIN nor a dictionary's.
   function Encoding_Verdict (Plan : Page_Plan) return Outcome
   is (if Plan.H.Encoding
          in Plain_Encoding
           | Plain_Dictionary_Encoding
           | Rle_Dictionary_Encoding
       then Done
       else
         Refused_With (Unsupported_Encoding, 0, Integer_64 (Plan.H.Encoding)));

   --  The rows a data page fills: Rows rows after row First, Present of
   --  them valid.
   type Row_Span is record
      First   : Natural := 0;
      Rows    : Natural := 0;
      Present : Natural := 0;
   end record;

   function Span_Of (L : Layout; First : Natural) return Row_Span
   is ((First => First, Rows => Rows_Of (L), Present => L.Levels.Present));

   --  True when S lies within N rows and holds no more values than rows.
   function Fits (S : Row_Span; N : Natural) return Boolean
   is (S.First <= N
       and then S.Rows <= N - S.First
       and then S.Present <= S.Rows);

   --  Moves S.Present values, packed at the start of S's rows, out to the
   --  valid rows, last first so that none is overwritten before it moves;
   --  a null row gets Null_Value.  Ok False when the valid rows and the
   --  values do not agree in number.
   generic
      type Element is private;
      type Element_Array is array (Buffer_Index range <>) of Element;
      Null_Value : Element;
   procedure Spread_Back
     (Valid  : Flags;
      Values : in out Element_Array;
      S      : Row_Span;
      Ok     : out Boolean)
   with
     Pre =>
       Valid'First = 1
       and then Values'First = 1
       and then Fits (S, Valid'Length)
       and then Fits (S, Values'Length);

   procedure Spread_Back
     (Valid  : Flags;
      Values : in out Element_Array;
      S      : Row_Span;
      Ok     : out Boolean)
   is
      J : Natural := S.Present;
   begin
      Ok := True;
      for R in reverse S.First + 1 .. S.First + S.Rows loop
         if Valid (R) and then J > 0 then
            Values (R) := Values (S.First + J);
            J := J - 1;
         elsif Valid (R) then
            Ok := False;
         else
            Values (R) := Null_Value;
         end if;
         pragma Loop_Invariant (J <= S.Present);
      end loop;
      Ok := Ok and then J = 0;
   end Spread_Back;

   procedure Spread_Words is new Spread_Back (Unsigned_64, Words, 0);
   procedure Spread_Codes is new Spread_Back (Buffer_Count, Counts, 0);

   ---------------------------------------------------------------------
   --  Fixed-width values
   ---------------------------------------------------------------------

   function Byte_Count (Width : Plain_Width) return Positive
   is (case Width is
         when One_Bit     => 1,
         when Four_Bytes  => 4,
         when Eight_Bytes => 8);

   --  The bytes Count plain values of Width take.
   function Plain_Size
     (Width : Plain_Width; Count : Buffer_Count) return Integer_64
   is (if Width = One_Bit
       then Integer_64 ((Count + 7) / 8)
       else Integer_64 (Count) * Integer_64 (Byte_Count (Width)));

   --  Value J (from 0) of the plain values at At_Byte of Page.
   function Plain_Word
     (Page : Bytes; At_Byte : Natural; Width : Plain_Width; J : Natural)
      return Unsigned_64
   with
     Pre =>
       J < Max_Buffer
       and then At_Byte <= Page'Length
       and then Plain_Size (Width, J + 1)
                <= Integer_64 (Page'Length - At_Byte);

   function Plain_Word
     (Page : Bytes; At_Byte : Natural; Width : Plain_Width; J : Natural)
      return Unsigned_64
   is
      Value : Unsigned_64 := 0;
      Base  : constant Natural :=
        (if Width = One_Bit
         then At_Byte + J / 8
         else At_Byte + J * Byte_Count (Width));
   begin
      if Width = One_Bit then
         return
           Shift_Right (Unsigned_64 (Byte_At (Page, Base)), J mod 8) and 1;
      end if;
      for K in 0 .. Byte_Count (Width) - 1 loop
         Value :=
           Value or Shift_Left (Unsigned_64 (Byte_At (Page, Base + K)), 8 * K);
      end loop;
      return Value;
   end Plain_Word;

   procedure Dictionary_Words
     (Page   : Bytes;
      Plan   : Page_Plan;
      Into   : in out Word_Column;
      Result : out Outcome)
   is
      Count : constant Buffer_Count := Plan.H.Values;
   begin
      Into.Dictionary_Size := 0;
      if Plan.Width = One_Bit
        or else Plan.H.Encoding
                not in Plain_Encoding | Plain_Dictionary_Encoding
      then
         Result :=
           Refused_With
             (Unsupported_Encoding, 0, Integer_64 (Plan.H.Encoding));
      elsif Count > Into.Capacity
        or else Plain_Size (Plan.Width, Count) > Integer_64 (Page'Length)
      then
         Result := Refused (Corrupt_Page);
      else
         for J in 0 .. Count - 1 loop
            Into.Dictionary (J + 1) := Plain_Word (Page, 0, Plan.Width, J);
         end loop;
         Into.Dictionary_Size := Count;
         Result := Done;
      end if;
   end Dictionary_Words;

   --  True when Present plain values of Width fit Page after At_Byte.
   function Plain_Fits
     (Page : Bytes; At_Byte : Natural; Width : Plain_Width; Present : Natural)
      return Boolean
   is (Present <= Max_Buffer
       and then At_Byte <= Page'Length
       and then Plain_Size (Width, Present)
                <= Integer_64 (Page'Length - At_Byte));

   --  A data page's plain values, packed into its rows, then spread.
   procedure Plain_Words
     (Page   : Bytes;
      L      : Layout;
      Into   : in out Word_Column;
      Result : out Outcome)
   with
     Pre  => Fits (Span_Of (L, Into.Filled), Into.Rows),
     Post => Into.Filled = Into.Filled'Old;

   procedure Plain_Words
     (Page   : Bytes;
      L      : Layout;
      Into   : in out Word_Column;
      Result : out Outcome)
   is
      At_Byte : constant Natural := L.Levels.Values_At;
      S       : constant Row_Span := Span_Of (L, Into.Filled);
      Ok      : Boolean;
   begin
      if not Plain_Fits (Page, At_Byte, L.Plan.Width, S.Present) then
         Result := Refused (Corrupt_Page);
         return;
      end if;
      for J in 0 .. S.Present - 1 loop
         Into.Value (S.First + 1 + J) :=
           Plain_Word (Page, At_Byte, L.Plan.Width, J);
      end loop;
      Spread_Words (Into.Valid, Into.Value, S, Ok);
      Result := (if Ok then Done else Refused (Corrupt_Page));
   end Plain_Words;

   --  The dictionary indices of a data page's Present values, into
   --  Scratch: a byte of bit width, then the hybrid.  Corrupt_Page when an
   --  index is past the Size entries of the dictionary.
   procedure Read_Indices
     (Page    : Bytes;
      Levels  : Level_Read;
      Size    : Buffer_Count;
      Scratch : in out Codes;
      Result  : out Outcome)
   with Pre => Levels.Present <= Scratch'Length;

   procedure Read_Indices
     (Page    : Bytes;
      Levels  : Level_Read;
      Size    : Buffer_Count;
      Scratch : in out Codes;
      Result  : out Outcome)
   is
      At_Byte : constant Natural := Levels.Values_At;
   begin
      if Levels.Present = 0 then
         Result := Done;
         return;
      elsif At_Byte >= Page'Length
        or else Natural (Byte_At (Page, At_Byte)) > Bit_Width'Last
      then
         Result := Refused (Corrupt_Page);
         return;
      end if;
      Decode
        (Page (Page'First + At_Byte + 1 .. Page'Last),
         Bit_Width (Byte_At (Page, At_Byte)),
         Levels.Present,
         Scratch,
         Result);
      for J in 0 .. Levels.Present - 1 loop
         exit when not Result.Ok;
         if Scratch (Scratch'First + J) >= Unsigned_32 (Size) then
            Result := Refused (Corrupt_Page);
         end if;
      end loop;
   end Read_Indices;

   --  The dictionary's value for index J of Scratch; 0 for none.
   function Looked_Up
     (Into : Word_Column; Scratch : Codes; J : Natural) return Unsigned_64
   is (if J < Scratch'Length
         and then Scratch (Scratch'First + J)
                  < Unsigned_32
                      (Natural'Min (Into.Dictionary_Size, Into.Capacity))
       then Into.Dictionary (Natural (Scratch (Scratch'First + J)) + 1)
       else 0);

   --  A data page's dictionary indices, looked up and packed into its
   --  rows, then spread.
   procedure Coded_Words
     (Page    : Bytes;
      L       : Layout;
      Into    : in out Word_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   with
     Pre  =>
       Fits (Span_Of (L, Into.Filled), Into.Rows)
       and then L.Levels.Present <= Scratch'Length,
     Post => Into.Filled = Into.Filled'Old;

   procedure Coded_Words
     (Page    : Bytes;
      L       : Layout;
      Into    : in out Word_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   is
      S  : constant Row_Span := Span_Of (L, Into.Filled);
      Ok : Boolean;
   begin
      Read_Indices (Page, L.Levels, Into.Dictionary_Size, Scratch, Result);
      if not Result.Ok then
         return;
      end if;
      for J in 0 .. S.Present - 1 loop
         Into.Value (S.First + 1 + J) := Looked_Up (Into, Scratch, J);
      end loop;
      Spread_Words (Into.Valid, Into.Value, S, Ok);
      Result := (if Ok then Done else Refused (Corrupt_Page));
   end Coded_Words;

   procedure Data_Words
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Word_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   is
      L : Layout := (Plan => Plan, Levels => <>);
   begin
      Result := Encoding_Verdict (Plan);
      if Result.Ok and then Plan.H.Values > Into.Rows - Into.Filled then
         Result := Refused (Corrupt_Page);
      end if;
      if Result.Ok then
         Lay_Out
           (Page,
            L,
            Into.Valid (Into.Filled + 1 .. Into.Filled + Plan.H.Values),
            Scratch,
            Result);
      end if;
      if not Result.Ok then
         return;
      elsif Plan.H.Encoding = Plain_Encoding then
         Plain_Words (Page, L, Into, Result);
      else
         Coded_Words (Page, L, Into, Scratch, Result);
      end if;
      if Result.Ok then
         Into.Filled := Into.Filled + Plan.H.Values;
      end if;
   end Data_Words;

   ---------------------------------------------------------------------
   --  Byte arrays
   ---------------------------------------------------------------------

   --  A run of bytes of a page: Length bytes from offset Start.
   type Piece is record
      Start  : Buffer_Count := 0;
      Length : Buffer_Count := 0;
   end record;

   function Inside (P : Piece; Page : Bytes) return Boolean
   is (P.Start <= Page'Length and then P.Length <= Page'Length - P.Start);

   function Piece_Bytes (Page : Bytes; P : Piece) return Bytes
   is (if P.Length > 0
       then Page (Page'First + P.Start .. Page'First + P.Start + P.Length - 1)
       else Page (Page'First .. Page'First - 1))
   with Pre => Inside (P, Page);

   FNV_Offset : constant Unsigned_32 := 2_166_136_261;
   FNV_Prime  : constant Unsigned_32 := 16_777_619;

   --  The FNV-1a hash of P's bytes.
   function Hash (Page : Bytes; P : Piece) return Unsigned_32
   with Pre => Inside (P, Page);

   function Hash (Page : Bytes; P : Piece) return Unsigned_32 is
      H : Unsigned_32 := FNV_Offset;
   begin
      for K in 0 .. P.Length - 1 loop
         H := (H xor Unsigned_32 (Byte_At (Page, P.Start + K))) * FNV_Prime;
      end loop;
      return H;
   end Hash;

   --  Slot Probe places after where Key hashes, from 1.
   function Slot_Of
     (Into : Text_Column; Key : Unsigned_32; Probe : Natural) return Positive
   is (Natural
         ((Unsigned_64 (Key) + Unsigned_64 (Probe))
          mod Unsigned_64 (Into.Slot_Count))
       + 1)
   with
     Pre  => Into.Slot_Count > 0 and then Probe < Into.Slot_Count,
     Post => Slot_Of'Result <= Into.Slot_Count;

   --  P's bytes as a new entry; Code is its number, 0 when there is no
   --  room.
   procedure Append_Entry
     (Page : Bytes; P : Piece; Into : in out Text_Column; Code : out Natural)
   with
     Pre  => Inside (P, Page),
     Post => Into.Filled = Into.Filled'Old and then Code <= Into.Max_Entries;

   procedure Append_Entry
     (Page : Bytes; P : Piece; Into : in out Text_Column; Code : out Natural)
   is
      E : constant Natural := Into.Entries + 1;
   begin
      Code := 0;
      if Into.Entries >= Into.Max_Entries
        or else Into.Used > Into.Max_Bytes
        or else P.Length > Into.Max_Bytes - Into.Used
      then
         return;
      end if;
      Into.Start (E) := Into.Used;
      Into.Length (E) := P.Length;
      if P.Length > 0 then
         Into.Text (Into.Used + 1 .. Into.Used + P.Length) :=
           Piece_Bytes (Page, P);
      end if;
      Into.Used := Into.Used + P.Length;
      Into.Entries := E;
      Code := E;
   end Append_Entry;

   --  The entry whose bytes are P's, entered (when new) in Slots too; 0
   --  when there is no room.  With Always_New, P becomes a new entry even
   --  when its bytes are there already: a dictionary keeps its order.
   procedure Enter
     (Page       : Bytes;
      P          : Piece;
      Into       : in out Text_Column;
      Always_New : Boolean;
      Code       : out Natural)
   with
     Pre  => Inside (P, Page),
     Post => Into.Filled = Into.Filled'Old and then Code <= Into.Max_Entries;

   procedure Enter
     (Page       : Bytes;
      P          : Piece;
      Into       : in out Text_Column;
      Always_New : Boolean;
      Code       : out Natural)
   is
      Key  : constant Unsigned_32 := Hash (Page, P);
      Slot : Positive;
      E    : Natural;
   begin
      for Probe in 0 .. Into.Slot_Count - 1 loop
         Slot := Slot_Of (Into, Key, Probe);
         E := Into.Slots (Slot);
         if E = 0 then
            Append_Entry (Page, P, Into, Code);
            Into.Slots (Slot) := Code;
            return;
         elsif E <= Into.Max_Entries
           and then not Always_New
           and then Entry_Bytes (Into, E) = Piece_Bytes (Page, P)
         then
            Code := E;
            return;
         end if;
      end loop;
      Append_Entry (Page, P, Into, Code);
   end Enter;

   --  The byte array at offset At_Byte of Page: a 4-byte length, then
   --  that many bytes.  Ok False when either runs past the page.
   procedure Read_Piece
     (Page : Bytes; At_Byte : Natural; P : out Piece; Ok : out Boolean)
   with Post => (if Ok then Inside (P, Page) and then P.Start >= At_Byte);

   procedure Read_Piece
     (Page : Bytes; At_Byte : Natural; P : out Piece; Ok : out Boolean)
   is
      Length : Buffer_Count;
   begin
      Read_Length (Page, At_Byte, Length, Ok);
      if Ok and then Length <= Page'Length - At_Byte - Length_Size then
         P := (Start => At_Byte + Length_Size, Length => Length);
      else
         P := (others => <>);
         Ok := False;
      end if;
   end Read_Piece;

   --  A run of plain byte arrays: Count of them from offset From, each to
   --  be a new entry (Fresh) or the entry its bytes already are.
   type Value_Run is record
      From  : Buffer_Count := 0;
      Count : Buffer_Count := 0;
      Fresh : Boolean := False;
   end record;

   --  The byte arrays of Run, each entered in Into, the code of the J-th
   --  (from 0) kept in Kept while there is room.
   procedure Enter_All
     (Page   : Bytes;
      Run    : Value_Run;
      Into   : in out Text_Column;
      Kept   : in out Codes;
      Result : out Outcome)
   with Post => Into.Filled = Into.Filled'Old;

   procedure Enter_All
     (Page   : Bytes;
      Run    : Value_Run;
      Into   : in out Text_Column;
      Kept   : in out Codes;
      Result : out Outcome)
   is
      Next : Natural := Run.From;
      P    : Piece;
      Ok   : Boolean := True;
      Code : Natural := 0;
   begin
      for J in 0 .. Run.Count - 1 loop
         Read_Piece (Page, Next, P, Ok);
         if Ok then
            Enter (Page, P, Into, Run.Fresh, Code);
            Ok := Code > 0;
         end if;
         exit when not Ok;
         if J < Kept'Length then
            Kept (Kept'First + J) := Unsigned_32 (Code);
         end if;
         Next := P.Start + P.Length;
         pragma Loop_Invariant (Into.Filled = Into.Filled'Loop_Entry);
      end loop;
      Result := (if Ok then Done else Refused (Corrupt_Page));
   end Enter_All;

   procedure Dictionary_Text
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   is
      Encoding : constant Integer_32 := Plan.H.Encoding;
   begin
      if Encoding not in Plain_Encoding | Plain_Dictionary_Encoding then
         Result :=
           Refused_With (Unsupported_Encoding, 0, Integer_64 (Encoding));
      elsif Into.Entries /= 0 then
         Result := Refused (Corrupt_Page);
      else
         Enter_All
           (Page,
            (From => 0, Count => Plan.H.Values, Fresh => True),
            Into,
            Scratch,
            Result);
         Into.Dictionary_Entries := Into.Entries;
      end if;
   end Dictionary_Text;

   --  The code of index J of Scratch read as a dictionary index: index I
   --  is entry I + 1; 0 for none.
   function Index_Code (Scratch : Codes; J : Natural) return Buffer_Count
   is (if J < Scratch'Length and then Scratch (Scratch'First + J) < Max_Buffer
       then Buffer_Count (Scratch (Scratch'First + J)) + 1
       else 0);

   --  The code kept at J of Scratch; 0 for none.
   function Kept_Code (Scratch : Codes; J : Natural) return Buffer_Count
   is (if J < Scratch'Length and then Scratch (Scratch'First + J) <= Max_Buffer
       then Buffer_Count (Scratch (Scratch'First + J))
       else 0);

   --  A data page's codes, packed into its rows from Scratch (as indices
   --  when Indexed, as codes when not), then spread.
   procedure Place_Codes
     (L       : Layout;
      Into    : in out Text_Column;
      Scratch : Codes;
      Indexed : Boolean;
      Result  : out Outcome)
   with
     Pre  => Fits (Span_Of (L, Into.Filled), Into.Rows),
     Post => Into.Filled = Into.Filled'Old;

   procedure Place_Codes
     (L       : Layout;
      Into    : in out Text_Column;
      Scratch : Codes;
      Indexed : Boolean;
      Result  : out Outcome)
   is
      S  : constant Row_Span := Span_Of (L, Into.Filled);
      Ok : Boolean;
   begin
      for J in 0 .. S.Present - 1 loop
         Into.Code (S.First + 1 + J) :=
           (if Indexed
            then Index_Code (Scratch, J)
            else Kept_Code (Scratch, J));
      end loop;
      Spread_Codes (Into.Valid, Into.Code, S, Ok);
      Result := (if Ok then Done else Refused (Corrupt_Page));
   end Place_Codes;

   --  A data page's values as codes in Scratch: dictionary indices read,
   --  or plain byte arrays entered (or found) in Into.
   procedure Text_Codes
     (Page    : Bytes;
      L       : Layout;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   with
     Pre  => L.Levels.Present <= Scratch'Length,
     Post => Into.Filled = Into.Filled'Old;

   procedure Text_Codes
     (Page    : Bytes;
      L       : Layout;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome) is
   begin
      if L.Plan.H.Encoding = Plain_Encoding then
         Enter_All
           (Page,
            (From  => L.Levels.Values_At,
             Count => L.Levels.Present,
             Fresh => False),
            Into,
            Scratch,
            Result);
      else
         Read_Indices
           (Page, L.Levels, Into.Dictionary_Entries, Scratch, Result);
      end if;
   end Text_Codes;

   procedure Data_Text
     (Page    : Bytes;
      Plan    : Page_Plan;
      Into    : in out Text_Column;
      Scratch : in out Codes;
      Result  : out Outcome)
   is
      L : Layout := (Plan => Plan, Levels => <>);
   begin
      Result := Encoding_Verdict (Plan);
      if Result.Ok
        and then (Into.Filled > Into.Rows
                  or else Plan.H.Values > Into.Rows - Into.Filled)
      then
         Result := Refused (Corrupt_Page);
      end if;
      if Result.Ok then
         Lay_Out
           (Page,
            L,
            Into.Valid (Into.Filled + 1 .. Into.Filled + Plan.H.Values),
            Scratch,
            Result);
      end if;
      if Result.Ok then
         Text_Codes (Page, L, Into, Scratch, Result);
      end if;
      if Result.Ok then
         Place_Codes
           (L, Into, Scratch, Plan.H.Encoding /= Plain_Encoding, Result);
      end if;
      if Result.Ok then
         Into.Filled := Into.Filled + Plan.H.Values;
      end if;
   end Data_Text;

end Tessera.Pages;
