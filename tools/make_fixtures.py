#!/usr/bin/env python3
"""Write the Parquet fixtures tessera is tested against, under tests/data/.

Each fixture is written by pyarrow, the writer tessera reads, from seeded
values, so a re-run writes the same rows.  Beside each readable fixture
goes NAME.expected.csv: one line per row, one field per column, every
value rendered the way tessera hands it over --

  BOOLEAN         true / false
  INT32, INT64    the integer, decimal (DATE as days since 1970-01-01,
                  TIME and TIMESTAMP as microseconds)
  FLOAT, DOUBLE   the bit pattern, 0x and 8 or 16 lowercase hex digits
  BYTE_ARRAY      the text
  a null          <null>

The refused and damaged fixtures get a .expected.csv that names the
refusal instead.  Run with the interpreter that has pyarrow:

  python tools/make_fixtures.py [OUT_DIR]

CI never runs this; the fixtures are committed.  tools/requirements.txt
pins the versions they were written with.
"""

import csv
import datetime
import os
import random
import struct
import sys

import pyarrow as pa
import pyarrow.parquet as pq

SEED = 20261006
NULL = "<null>"


def bits32(x):
    return "0x%08x" % struct.unpack("<I", struct.pack("<f", x))[0]


def bits64(x):
    return "0x%016x" % struct.unpack("<Q", struct.pack("<d", x))[0]


EPOCH = datetime.date(1970, 1, 1)
MIDNIGHT = datetime.datetime(1970, 1, 1)


def render(value, kind):
    """One value as tessera hands it over."""
    if value is None:
        return NULL
    if kind == "bool":
        return "true" if value else "false"
    if kind == "float32":
        return bits32(value)
    if kind == "float64":
        return bits64(value)
    if kind == "date":
        return str((value - EPOCH).days)
    if kind == "time":
        return str(
            ((value.hour * 60 + value.minute) * 60 + value.second) * 1_000_000
            + value.microsecond
        )
    if kind == "timestamp":
        delta = value - MIDNIGHT
        return str(
            (delta.days * 86_400 + delta.seconds) * 1_000_000
            + delta.microseconds
        )
    return str(value)


def write_expected(path, table, kinds):
    with open(path, "w", newline="") as out:
        w = csv.writer(out, lineterminator="\n")
        w.writerow(table.column_names)
        columns = [table.column(n).to_pylist() for n in table.column_names]
        for row in zip(*columns):
            w.writerow(render(v, k) for v, k in zip(row, kinds))


def write_refusal(path, refusal):
    with open(path, "w", newline="") as out:
        out.write("refused\n%s\n" % refusal)


def flat(rng):
    """Ten rows, one column of each type tessera reads."""
    n = 10
    f32 = [rng.uniform(-100, 100) for _ in range(n)]
    f32 = [struct.unpack("<f", struct.pack("<f", x))[0] for x in f32]
    cols = {
        "flag": (pa.bool_(), [rng.random() < 0.5 for _ in range(n)], "bool"),
        "i32": (
            pa.int32(),
            [rng.randint(-(2**31), 2**31 - 1) for _ in range(n)],
            "int",
        ),
        "u8": (pa.uint8(), [rng.randint(0, 255) for _ in range(n)], "int"),
        "u16": (pa.uint16(), [rng.randint(0, 65535) for _ in range(n)], "int"),
        "u32": (
            pa.uint32(),
            [rng.randint(0, 2**31 - 1) for _ in range(n)],
            "int",
        ),
        "day": (
            pa.date32(),
            [
                EPOCH + datetime.timedelta(days=rng.randint(-1000, 30000))
                for _ in range(n)
            ],
            "date",
        ),
        "i64": (
            pa.int64(),
            [rng.randint(-(2**63), 2**63 - 1) for _ in range(n)],
            "int",
        ),
        "u64": (
            pa.uint64(),
            [rng.randint(0, 2**63 - 1) for _ in range(n)],
            "int",
        ),
        "clock": (
            pa.time64("us"),
            [
                datetime.time(
                    rng.randint(0, 23),
                    rng.randint(0, 59),
                    rng.randint(0, 59),
                    rng.randint(0, 999_999),
                )
                for _ in range(n)
            ],
            "time",
        ),
        "stamp": (
            pa.timestamp("us"),
            [
                MIDNIGHT
                + datetime.timedelta(microseconds=rng.randint(0, 2**50))
                for _ in range(n)
            ],
            "timestamp",
        ),
        "single": (pa.float32(), f32, "float32"),
        "double": (
            pa.float64(),
            [rng.uniform(-1e6, 1e6) for _ in range(n)],
            "float64",
        ),
        "text": (
            pa.string(),
            ["w%d" % rng.randint(0, 999) for _ in range(n)],
            "text",
        ),
    }
    return cols


def table_of(cols):
    names = list(cols)
    arrays = [pa.array(cols[k][1], type=cols[k][0]) for k in names]
    return pa.table(arrays, names=names), [cols[k][2] for k in names]


def nulls(rng):
    """A column of each kind with nulls among the values."""
    n = 12
    holes = {1, 4, 5, 11}

    def maybe(v, i):
        return None if i in holes else v

    return {
        "count": (
            pa.int64(),
            [maybe(rng.randint(-1000, 1000), i) for i in range(n)],
            "int",
        ),
        "price": (
            pa.float64(),
            [maybe(rng.uniform(0, 50), i) for i in range(n)],
            "float64",
        ),
        "name": (
            pa.string(),
            [maybe("n%d" % rng.randint(0, 3), i) for i in range(n)],
            "text",
        ),
        "empty": (pa.int32(), [None] * n, "int"),
    }


def groups(rng):
    """Thirty rows in three row groups of ten."""
    n = 30
    return {
        "row": (pa.int64(), list(range(n)), "int"),
        "label": (
            pa.string(),
            ["g%d-%d" % (i // 10, rng.randint(0, 2)) for i in range(n)],
            "text",
        ),
    }


def fallback(rng):
    """A string column whose dictionary outgrows its page limit."""
    n = 400
    distinct = ["value-%04d" % i for i in range(300)]
    vals = distinct[:]
    # Late repeats of early values: after the fallback they arrive as plain
    # values that are already in the dictionary.
    vals += [distinct[rng.randint(0, 299)] for _ in range(n - 300)]
    return {"word": (pa.string(), vals, "text")}


def runs(rng):
    """Long repeated runs, and packed runs at several bit widths."""
    n = 1200

    def cycling(k):
        # A long run of one value, then values cycling through k distinct.
        return [0] * 500 + [rng.randint(0, k - 1) for _ in range(n - 500)]

    sparse = [None] * 600 + [rng.randint(0, 9) for _ in range(n - 600)]
    return {
        "w1": (pa.int64(), cycling(2), "int"),
        "w3": (pa.int64(), cycling(6), "int"),
        "w5": (pa.int64(), cycling(20), "int"),
        "w9": (pa.int64(), cycling(300), "int"),
        "sparse": (pa.int32(), sparse, "int"),
    }


def write(out, name, table, kinds, **options):
    path = os.path.join(out, name + ".parquet")
    pq.write_table(table, path, **options)
    write_expected(os.path.join(out, name + ".expected.csv"), table, kinds)
    return path


def refused(out, name, refusal, table, **options):
    pq.write_table(table, os.path.join(out, name + ".parquet"), **options)
    write_refusal(os.path.join(out, name + ".expected.csv"), refusal)


def damaged(out, name, refusal, data):
    with open(os.path.join(out, name + ".parquet"), "wb") as f:
        f.write(data)
    write_refusal(os.path.join(out, name + ".expected.csv"), refusal)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    default = os.path.join(here, "..", "tests", "data")
    out = sys.argv[1] if len(sys.argv) > 1 else default
    os.makedirs(out, exist_ok=True)
    rng = random.Random(SEED)

    t, k = table_of(flat(rng))
    flat_path = write(out, "flat", t, k)
    t, k = table_of(nulls(rng))
    write(out, "nulls", t, k)
    t, k = table_of(groups(rng))
    write(out, "groups", t, k, row_group_size=10)
    t, k = table_of(fallback(rng))
    write(
        out,
        "fallback",
        t,
        k,
        dictionary_pagesize_limit=512,
        data_page_size=256,
        write_batch_size=50,
    )
    t, k = table_of(runs(rng))
    write(out, "runs", t, k)

    small = pa.table({"x": pa.array(list(range(20)), type=pa.int64())})
    refused(out, "zstd", "Unsupported_Codec ZSTD", small, compression="zstd")
    refused(
        out,
        "v2pages",
        "Unsupported_Page_Version DATA_PAGE_V2",
        small,
        data_page_version="2.0",
    )
    nested = pa.table(
        {"xs": pa.array([[1, 2], [3], []], type=pa.list_(pa.int64()))}
    )
    refused(out, "nested", "Nested_Schema", nested)
    refused(
        out,
        "delta",
        "Unsupported_Encoding DELTA_BINARY_PACKED",
        small,
        use_dictionary=False,
        column_encoding={"x": "DELTA_BINARY_PACKED"},
    )

    cents = pa.table(
        {"cents": pa.array([1, 2, 3], type=pa.decimal128(10, 2))}
    )
    refused(out, "decimal", "Unsupported_Type FIXED_LEN_BYTE_ARRAY", cents)
    stamps = pa.table(
        {"when": pa.array([0, 10**6], type=pa.timestamp("ns"))}
    )
    refused(
        out,
        "int96",
        "Unsupported_Type INT96",
        stamps,
        use_deprecated_int96_timestamps=True,
    )
    millis = pa.table(
        {"clock": pa.array([0, 1000], type=pa.time32("ms"))}
    )
    refused(out, "millis", "Unsupported_Type", millis)

    with open(flat_path, "rb") as f:
        whole = f.read()
    damaged(out, "truncated", "Truncated", whole[: len(whole) // 2])
    damaged(out, "badmagic", "Not_Parquet", b"PAR0" + whole[4:])


if __name__ == "__main__":
    main()
