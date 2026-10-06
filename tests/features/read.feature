Feature: A flat file reads back what was written

  A table pyarrow wrote is read back column by column: every value in
  the row it was written to, in every row group, nothing invented and
  nothing lost.

  Scenario: A flat file reads back the rows that were written
    Given the file flat.parquet
