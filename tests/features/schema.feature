Feature: A file lists its columns, their types, its rows and row groups

  Before any column is read, a file says what it holds: each column's
  name, its physical type and the annotation that says how to read it,
  whether it may hold nulls, how many rows there are and how they are
  split into row groups.

  Scenario: A file lists its columns and their types
    Given the file flat.parquet
    When the file is opened
    Then the file is open
    And its columns are:
      | name   | type       | annotation          |
      | flag   | BOOLEAN    |                     |
      | i32    | INT32      |                     |
      | u8     | INT32      | UNSIGNED 8          |
      | u16    | INT32      | UNSIGNED 16         |
      | u32    | INT32      | UNSIGNED 32         |
      | day    | INT32      | DATE                |
      | i64    | INT64      |                     |
      | u64    | INT64      | UNSIGNED 64         |
      | clock  | INT64      | TIME MICROS         |
      | stamp  | INT64      | TIMESTAMP MICROS    |
      | single | FLOAT      |                     |
      | double | DOUBLE     |                     |
      | text   | BYTE_ARRAY | STRING              |

  Scenario: A file counts its rows and its row groups
    Given the file groups.parquet
    When the file is opened
    Then it has 30 rows in 3 row groups
    And row group 1 has 10 rows
    And row group 3 has 10 rows

  Scenario: A column pyarrow writes may hold nulls
    Given the file nulls.parquet
    When the file is opened
    Then the column count may hold nulls
