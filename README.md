# tessera

Reads Apache Parquet files in Ada 2022: the subset that flat tables
written by pyarrow use, and nothing else.  Anything outside the subset
is refused by name, never misread.  The decoders -- Thrift compact, the
footer, Snappy, the RLE/bit-packed hybrid, pages, column chunks -- are a
SPARK core, proved free of run-time errors; one application unit,
`Tessera.Files`, touches the disk.  No C library, and no floating-point
type: `FLOAT` and `DOUBLE` columns are handed over as their 32- and
64-bit patterns.

The name is the small tile a mosaic is laid from; a parquet is laid
from columns of them.

## Reading a file

```ada
with Tessera;         use Tessera;
with Tessera.Columns;
with Tessera.Files;   use Tessera.Files;
with Tessera.Names;

declare
   F      : File;
   Result : Outcome;
   Profit : Bits_64_Access;
   Names  : Coded_Access;
begin
   Open (Path, F, Result);
   --  Result.Ok, or Tessera.Names.Describe (Result) says why not:
   --  "an unsupported codec, ZSTD", "truncated", ...
   for G in 1 .. Row_Groups (F) loop
      Read_Bits_64 (F, G, "Profit", Profit, Result);
      Read_Coded (F, G, "Position_Name", Names, Result);
      --  Profit.Valid (I), Profit.Value (I): row I's 64-bit pattern;
      --  Names.Code (I): row I's code, equal for equal strings, and
      --  Tessera.Columns.Text (Names.all, Code) the string it stands for.
      Free (Profit);
      Free (Names);
   end loop;
end;
```

Each `Read_*` reads one row group's chunk of one column into a new
column on the heap, sized from the checked footer: `Read_Truths`
(BOOLEAN), `Read_Ints_32` (INT32: integers, unsigned annotations as
their pattern, DATE as days since 1970-01-01), `Read_Ints_64` (INT64:
TIME and TIMESTAMP in microseconds), `Read_Bits_32` (FLOAT),
`Read_Bits_64` (DOUBLE), `Read_Coded` (BYTE_ARRAY: one code a row into a
dictionary of distinct strings, which stays one code per distinct string
even when the writer fell back to plain values mid-chunk).  A read never
changes the `File` and opens the file anew, so chunks of one file may be
read from many tasks at once; tessera starts none itself.

## The subset

Read: a flat schema; codecs Snappy and none; PLAIN, PLAIN_DICTIONARY,
RLE_DICTIONARY values and RLE definition levels; version 1 data pages;
BOOLEAN, INT32, INT64, FLOAT, DOUBLE and BYTE_ARRAY, with the STRING,
DATE, TIME and TIMESTAMP (microseconds) and INTEGER annotations.
Refused, by name: every other codec, encoding and annotation; version 2
and index pages; nested or repeated schemas; INT96 and
FIXED_LEN_BYTE_ARRAY; encrypted files; and damaged ones (not Parquet,
truncated, a corrupt footer or page).  The wire rules are in
`docs/tessera-plan.md`, section 1.

## Building

```
make build        # the library
make test         # the AUnit suite, -O3 and -O0
make features     # the Gherkin features (tests/features), both modes
make prove        # the SPARK proof, level 2, checks as errors
make ci           # every gate
make bench TESSERA_FILE=<path> [TESSERA_COLUMNS="a b c"]
```

What tessera does is stated as Gherkin features in
[tests/features](tests/features), and published as living documentation
at <https://ldm5180.github.io/tessera/> from every push to main.

`make bench` reads the named columns (every column when none is named)
of a local file and prints rows, megabytes and seconds per column; it
is how tessera was measured against a real file, which stays outside
the repository.  The fixtures under `tests/data` are written by
`tools/make_fixtures.py` (pyarrow, seeded) and committed.

MIT licensed.
