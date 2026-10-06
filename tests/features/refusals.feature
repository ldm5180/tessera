Feature: What tessera does not read, it refuses by name

  A reader that meets a feature it does not know and carries on hands
  back wrong numbers.  tessera reads one subset of Parquet -- flat
  columns, Snappy or no compression, PLAIN and dictionary encodings,
  version 1 data pages -- and refuses everything else, naming the
  feature and the value the file gave.  A damaged file is refused by
  what is wrong with it.

  Scenario Outline: A file outside the subset is refused by its name
    Given the file <file>
    When the file is read in full
    Then it is refused as <refusal>

    Examples:
      | file            | refusal                                     |
      | zstd.parquet    | an unsupported codec, ZSTD                  |
      | v2pages.parquet | an unsupported page, DATA_PAGE_V2           |
      | nested.parquet  | a nested schema                             |
      | delta.parquet   | an unsupported encoding, DELTA_BINARY_PACKED |
      | decimal.parquet | an unsupported type, FIXED_LEN_BYTE_ARRAY   |
      | int96.parquet   | an unsupported type, INT96                  |
      | millis.parquet  | an unsupported annotation                   |

  Scenario Outline: A damaged file is refused by what is wrong with it
    Given the file <file>
    When the file is read in full
    Then it is refused as <refusal>

    Examples:
      | file              | refusal     |
      | truncated.parquet | truncated   |
      | badmagic.parquet  | not Parquet |

  Scenario: A column is refused with the column named
    Given the file v2pages.parquet
    When the file is read in full
    Then the refusal names the column x
