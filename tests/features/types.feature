Feature: Each type arrives as tessera hands it over

  tessera forms no number a file did not hold.  An integer arrives as
  an integer of its width; a date as the days since 1970-01-01; a time
  of day and a timestamp as microseconds; an unsigned integer as the
  value it was written as; a FLOAT or DOUBLE as its bit pattern,
  never as a number; a string as its code and the text the code stands
  for.

  Background:
    Given the file flat.parquet
    When the file is opened

  Scenario: A date arrives as the days since 1970-01-01
    When the column day is read
    Then row 1 of day reads "27720"
    And every value of day is as written

  Scenario: A time of day and a timestamp arrive as microseconds
    When the column clock is read
    Then row 1 of clock reads "16528448132"
    When the column stamp is read
    Then row 1 of stamp reads "404525427944158"
    And every value of stamp is as written

  Scenario: Unsigned integers arrive as the values written
    When the column u8 is read
    Then row 1 of u8 reads "210"
    When the column u32 is read
    Then row 1 of u32 reads "456477186"
    When the column u64 is read
    Then row 1 of u64 reads "3885910122763819422"

  Scenario: FLOAT and DOUBLE arrive as their bit patterns
    When the column single is read
    Then row 1 of single reads "0xbf85182a"
    When the column double is read
    Then row 1 of double reads "0x4118844c6682c324"
    And every value of double is as written

  Scenario: Booleans, signed integers and strings arrive as written
    When the column flag is read
    Then row 1 of flag reads "true"
    When the column i64 is read
    Then every value of i64 is as written
    When the column text is read
    Then row 1 of text reads "w517"
