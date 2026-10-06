# tessera plan

**Status (2026-10-06):** planned, nothing built.  Three iterations
done (see Revision notes).

tessera reads Apache Parquet files in Ada 2022, with a SPARK core:
the subset of the format that flat tables written by pyarrow use,
and nothing else.  Anything outside the subset is refused with a
name, never misread.  It has no C dependency and no floating-point
type.  Its first consumer is statera
(`~/git/statera/docs/statera-plan.md`, the master plan).

The name is the small tile a mosaic is laid from; a parquet is laid
from columns of them.

## How to use this plan

Work T0-T9 in order.  T0 produces the fixtures every later item
tests against, so it cannot be skipped.  Each item is one or more
TDD cycles (RED first), logged in `docs/tdd-log.md`, one commit per
cycle, `make ci` after each, `make prove` when `src/core` changed.

Each item has five parts: **Where**, **What is wrong** (what is
missing), **Why**, **Fix**, **RED first**.

The format is defined by the Apache Parquet specification and its
`parquet.thrift`.  Section 1 states the part of it this crate
reads, in enough detail to type from; where the specification says
more, it is out of scope and section 1.5 says so.

### Do not

- Do not read a feature that is not in section 1.  Refuse it, by
  name (T8).
- Do not trust a length, a count or an offset from the file.  Every
  one is checked against the buffer it indexes before use; the
  proofs depend on it.
- Do not declare or name a floating-point type.  `FLOAT` and
  `DOUBLE` columns are handed over as 32-bit and 64-bit patterns.
- Do not bind a C library.  Snappy is written here.
- Do not raise from the library.  Every failure is an outcome.
- Do not commit a real data file.  Fixtures come from
  `tools/make_fixtures.py` and are a few kilobytes each.
- Do not read a whole file into memory.  Read the footer, then the
  column chunks asked for.
- Do not start tasks inside the library.  Decoding a column chunk
  is a pure function of its bytes; the consumer runs them in
  parallel.

## 1. The subset

Measured on the two files this crate exists for (2026-10-06): 66
columns, 4,109,090 and 988,291 rows, 4 and 3 row groups, written by
`parquet-cpp-arrow version 24.0.0`, format version 2.6.

### 1.1 File layout

```
"PAR1"  column chunks ...  FileMetaData  <4-byte length, little-endian>  "PAR1"
```

`FileMetaData` is a Thrift compact struct: the schema (a flat list
of elements), the row count, and the row groups; each row group
lists its column chunks; each chunk's metadata gives its type,
encodings, codec, value count, sizes, and the offsets of its
dictionary page and first data page.

### 1.2 Thrift compact protocol

- A varint is 7 bits per byte, low bits first, high bit meaning
  "more".
- Integers are zigzag varints.
- A field header is one byte: the high four bits are the delta from
  the last field id (0 means the id follows as a zigzag varint), the
  low four bits are the type.  A byte of 0 ends the struct.
- Types: 1 and 2 are the booleans true and false (the value is the
  type), 3 byte, 4 i16, 5 i32, 6 i64, 7 double, 8 binary (a varint
  length, then bytes), 9 list, 12 struct.
- A list header is one byte: the high four bits are the size (15
  means the size follows as a varint), the low four the element
  type.
- An unknown field is skipped by its type.

### 1.3 Pages

A column chunk is a dictionary page followed by data pages.  Each
page is a Thrift `PageHeader` (type, uncompressed size, compressed
size, and a type-specific header) followed by its bytes, Snappy
compressed.

- **Dictionary page:** `num_values` values, PLAIN encoded.
- **Data page (version 1):** for a column that may hold nulls, the
  definition levels come first: a 4-byte length, then that many
  bytes of RLE/bit-packed hybrid at bit width 1.  A level of 1 is a
  value, 0 is a null.  Then the values, for the non-null rows only:
  - `RLE_DICTIONARY` (or its old name `PLAIN_DICTIONARY`): one byte
    of bit width, then RLE/bit-packed hybrid indices into the
    dictionary.
  - `PLAIN`: the values themselves.  A writer falls back to this
    partway through a chunk when a dictionary grows too large.

### 1.4 Encodings

- **PLAIN:** `INT32` and `FLOAT` are 4 bytes little-endian, `INT64`
  and `DOUBLE` are 8, `BYTE_ARRAY` is a 4-byte length then bytes,
  `BOOLEAN` is one bit, low bit first.
- **RLE/bit-packed hybrid:** a sequence of runs.  Each starts with
  a varint header.  If its low bit is 0 it is a repeated run: the
  count is the header shifted right by one, and the value follows
  in `ceil(width / 8)` bytes.  If its low bit is 1 it is a
  bit-packed run of `(header >> 1) * 8` values at `width` bits
  each, packed low bit first.
- **Snappy (raw block):** a varint uncompressed length, then
  elements.  The low two bits of each tag byte: 0 is a literal
  (length in the tag, or in the next 1-4 bytes), 1 is a copy with
  a 3-bit length and an 11-bit offset, 2 a copy with a 2-byte
  offset, 3 a copy with a 4-byte offset.  A copy may overlap its
  own output.

### 1.5 Types

| physical | logical annotations read | handed over as |
|---|---|---|
| `BOOLEAN` | | `Boolean` |
| `INT32` | signed, unsigned 8/16/32, `DATE` | `Integer_32`, or days since 1970-01-01 |
| `INT64` | signed, unsigned 64, `TIME` and `TIMESTAMP` in microseconds | `Integer_64` |
| `FLOAT` | | `Unsigned_32`, the bit pattern |
| `DOUBLE` | | `Unsigned_64`, the bit pattern |
| `BYTE_ARRAY` | `STRING` | dictionary codes and a dictionary, or bytes |

### 1.6 Refused, by name

Compression other than Snappy or none; any other encoding
(`DELTA_BINARY_PACKED`, `DELTA_LENGTH_BYTE_ARRAY`,
`DELTA_BYTE_ARRAY`, `BYTE_STREAM_SPLIT`, `RLE` for values);
version 2 data pages; a schema with a repeated or nested element;
`INT96`; `FIXED_LEN_BYTE_ARRAY`; encrypted files.  Ignored:
statistics, the page index, bloom filters, key-value metadata,
page checksums.

## 2. Shape

| unit | layer | holds |
|---|---|---|
| `Tessera` | core | byte types, `Outcome`, `Refusal` |
| `Tessera.Thrift` | core | the compact decoder over a byte slice |
| `Tessera.Footer` | core | `FileMetaData` to a schema and chunk list |
| `Tessera.Snappy` | core | decompress a block |
| `Tessera.Hybrid` | core | RLE/bit-packed runs |
| `Tessera.Pages` | core | page headers; one page to levels and values |
| `Tessera.Columns` | core | a chunk's pages to a typed column |
| `Tessera.Files` | app | open, read a byte range, read a column |

Decoders that walk a format with states (the Thrift struct reader,
the Snappy element reader, the page sequence of a chunk) are sml
machines; the inner loops are plain.

The consumer's view:

```ada
declare
   F : Tessera.Files.File;
   R : Tessera.Outcome;
begin
   Tessera.Files.Open (Path, F, R);
   --  R = Opened, or a refusal that names the feature or the fault
   for G in 1 .. Tessera.Files.Row_Groups (F) loop
      declare
         Profit : constant Tessera.Columns.Bits_64 :=
           Tessera.Files.Read_Bits_64 (F, G, "Profit");
         Names  : constant Tessera.Columns.Coded :=
           Tessera.Files.Read_Coded (F, G, "Position_Name");
      begin
         ...  --  Profit.Valid (I), Profit.Value (I); Names.Code (I),
              --  Tessera.Columns.Text (Names, Code)
      end;
   end loop;
end;
```

## 3. Items

### T0 -- The skeleton and the fixtures

- **Where:** `~/git/tessera`.  Template: `~/git/lector` at
  `dd92622`.  `tools/make_fixtures.py`, `tests/data/`.
- **What is wrong:** nothing exists, and there is nothing to read.
- **Why:** new.
- **Fix:** crate `tessera` with `src/core` and `src/app`, the house
  Makefile (`build test features features-report prove format
  validation no-float bench ci`), the `Flows` runner, MIT license.
  `tools/make_fixtures.py` (pyarrow, seeded) writes, each with a
  `.expected.csv` beside it:

  | fixture | what it holds |
  |---|---|
  | `flat.parquet` | 10 rows, one column of each type in 1.5 |
  | `nulls.parquet` | a column with nulls among values |
  | `groups.parquet` | 3 row groups |
  | `fallback.parquet` | a string column that outgrows its dictionary |
  | `runs.parquet` | long repeated runs and packed runs at several bit widths |
  | `zstd.parquet`, `v2pages.parquet`, `nested.parquet`, `delta.parquet` | one refused feature each |
  | `truncated.parquet`, `badmagic.parquet` | a damaged file each |

  The script and its lock file are committed; the fixtures are
  committed; CI does not run Python.
- **RED first:** `make features` has no rule; then one undefined
  step in `read.feature`.
- **Gates:** `make ci`.

### T1 -- Thrift compact

- **Where:** `src/core/tessera-thrift.ads/.adb`.
- **What is wrong:** the footer cannot be read.
- **Why:** new.
- **Fix:** a cursor over a byte slice with `Read_Varint`,
  `Read_Zigzag`, `Read_Field_Header`, `Read_Binary`,
  `Read_List_Header`, `Skip (Kind)`.  Every read returns an outcome
  and never moves past the slice.  Nesting depth is bounded.
- **RED first:** `Tessera_Thrift_Tests.Test_Varint_300`: the bytes
  `AC 02` read as 300 and leave the cursor at 2.
- **Gates:** `make ci`, `make prove`.

### T2 -- The footer

- **Where:** `src/core/tessera-footer.ads/.adb`.
- **What is wrong:** the schema and the chunk offsets are unknown.
- **Why:** new.
- **Fix:** check both magics and the footer length; decode
  `FileMetaData` into bounded tables: schema elements (name,
  physical type, logical annotation, whether it may hold nulls),
  row groups, and per chunk its codec, encodings, value count,
  sizes and page offsets.  A schema element with children below the
  root, or a repeated one, is the refusal `Nested_Schema`.
- **RED first:** `schema.feature`, "A file lists its columns and
  their types".
- **Gates:** `make ci`, `make prove`.

### T3 -- Snappy

- **Where:** `src/core/tessera-snappy.ads/.adb`.
- **What is wrong:** every page is compressed.
- **Why:** pyarrow's default.
- **Fix:** `Decompress (Input; Output : out; Last : out; Result :
  out)`.  The element reader is a machine: `Tag`, `Literal`,
  `Copy`, `Done`, `Corrupt`.  A copy whose offset reaches before
  the start of the output, or a length past the declared size, is
  `Corrupt`.
- **RED first:** `Tessera_Snappy_Tests.Test_Overlapping_Copy`: a
  literal `ab` and a copy of length 6 at offset 2 give `abababab`.
- **Gates:** `make ci`, `make prove`.

### T4 -- RLE and bit-packed runs

- **Where:** `src/core/tessera-hybrid.ads/.adb`.
- **What is wrong:** levels and dictionary indices cannot be read.
- **Why:** new.
- **Fix:** `Decode (Input, Width, Count; Values : out; Result :
  out)` for widths 0 through 32.  The last bit-packed run may hold
  more values than remain; the extra are dropped.
- **RED first:** `Tessera_Hybrid_Tests.Test_Packed_Width_3`: the
  specification's own example, the values 0 through 7 at width 3,
  from the bytes `03 88 C6 FA`.
- **Gates:** `make ci`, `make prove`.

### T5 -- Pages

- **Where:** `src/core/tessera-pages.ads/.adb`.
- **What is wrong:** a chunk's bytes are not yet values.
- **Why:** new.
- **Fix:** `Read_Header` decodes a `PageHeader`; `Dictionary`
  decodes a dictionary page; `Data_V1` decodes levels and values of
  one data page, by dictionary or plain.  A version 2 page, an index
  page, or an encoding outside 1.4 is refused by name.
- **RED first:** `Tessera_Pages_Tests.Test_Null_Among_Values`: a
  page with levels 1, 0, 1 and two values yields value, null,
  value.
- **Gates:** `make ci`, `make prove`.

### T6 -- Columns

- **Where:** `src/core/tessera-columns.ads/.adb`.
- **What is wrong:** pages are not yet a column.
- **Why:** new.
- **Fix:** the chunk machine: `Start`, `Have_Dictionary`,
  `In_Data`, `Done`, `Refused`.  It yields a typed column of the
  chunk's row count with a validity flag per row.  A string column
  is codes plus the dictionary while every page is dictionary
  encoded; after a fallback page the plain values are added to the
  dictionary so the column stays coded.
- **RED first:** `dictionary.feature`, "A column that outgrows its
  dictionary still reads every value".
- **Gates:** `make ci`, `make prove`.

### T7 -- Files

- **Where:** `src/app/tessera-files.ads/.adb`.
- **What is wrong:** nothing touches the disk.
- **Why:** new.
- **Fix:** `Open` reads the last 8 bytes, then the footer; `Read_*`
  reads one chunk's byte range and decodes it.  Buffers are on the
  heap and sized from checked metadata.  Reading two chunks of one
  file from two tasks is safe.
- **RED first:** `read.feature`, "A flat file reads back the rows
  that were written".
- **Gates:** `make ci`.

### T8 -- Refusals

- **Where:** `src/core/tessera.ads` (`Refusal`), every decoder.
- **What is wrong:** a reader that meets a feature it does not know
  and carries on returns wrong numbers.
- **Why:** it is the easy failure.
- **Fix:** one `Refusal` enumeration: `Not_Parquet`, `Truncated`,
  `Corrupt_Footer`, `Corrupt_Page`, `Nested_Schema`,
  `Unsupported_Codec`, `Unsupported_Encoding`,
  `Unsupported_Page_Version`, `Unsupported_Type`, `Encrypted`,
  `No_Such_Column`, `Wrong_Type`, `Too_Large`.  Each carries the
  column and the offending value where there is one.
- **RED first:** `refusals.feature`, an outline over the refused
  fixtures of T0: "zstd.parquet is refused as an unsupported codec,
  ZSTD".
- **Gates:** `make ci`, `make prove`.

### T9 -- A real file, a benchmark, the documents

- **Where:** `bench/`, `README.md`.
- **What is wrong:** fixtures are small; the files this is for are
  not.
- **Why:** real data is not committed.
- **Fix:** `make bench TESSERA_FILE=<path>` reads named columns of
  a local file and prints rows, megabytes and seconds per column.
  It is not part of `make ci` beyond building.  Run it once on a
  retrotester file and record, here, that 14 columns read and their
  row count matches the footer's.
- **RED first:** `make bench` has no rule.
- **Gates:** `make ci`.

## 4. Features

| file | says |
|---|---|
| `schema.feature` | a file lists its columns, their types, its rows and row groups |
| `read.feature` | each column of a flat file reads back what was written, across row groups |
| `types.feature` | dates, times, timestamps, unsigned integers, strings and bit patterns each arrive as section 1.5 says |
| `nulls.feature` | a null is a null and its neighbors keep their places |
| `dictionary.feature` | coded columns; the fallback to plain values |
| `refusals.feature` | each unsupported feature and each damaged file is refused by its name |

## Revision notes

- **Iteration 1 (draft):** units, items, fixtures.
- **Iteration 2 (as a newcomer):** a newcomer cannot write a Thrift
  or Snappy decoder from "decode the footer", so section 1 now
  states the wire rules for each layer; added the consumer's view
  (section 2), the fixture table, the Do-not list, and a byte-level
  RED assertion for each decoder.
- **Iteration 3 (against the retrotester files in
  `~/git/prov2025/input/202609-r` and retrotester's writer):**
  measured rather than assumed: codec Snappy on every one of 462
  column chunks; encodings PLAIN, RLE, RLE_DICTIONARY on every
  chunk; a dictionary page on every chunk; no nesting; maximum
  definition level 1; the first page header of a chunk begins
  `15 04` (a dictionary page) and the first data page `15 00`
  (version 1).  The writer is `pq.ParquetWriter (file, schema)`
  with defaults (`~/git/retrotester/summary_stats.py:144`).
  Corrected: the draft listed version 2 pages as supported "in
  case"; nothing writes them, so they are refused.  Corrected: the
  draft had the consumer converting dictionary strings per row;
  codes are handed over instead.  Corrected: an earlier estimate in
  the session called a native reader the largest piece of the
  project; for this subset it is the smallest of the three crates.
  Not verified: that a string column in the real files falls back
  to plain values mid-chunk (`Custom_Column` has 137,000 distinct
  values and may); `fallback.parquet` covers the case either way.
