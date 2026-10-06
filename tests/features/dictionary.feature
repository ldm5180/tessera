Feature: A string column is codes and a dictionary

  A string column is handed over as one code per row and a dictionary
  of the distinct strings the codes stand for, so a caller compares and
  groups rows by code without touching a byte.  A writer that finds its
  dictionary growing too large stops using it partway through a column
  and writes the rest as plain strings; the column still reads every
  value, and still as codes.

  Scenario: A column that outgrows its dictionary still reads every value
    Given the file fallback.parquet
    When the file is opened
    And the column word is read
    Then every value of word is as written
    And word has 300 distinct codes

  Scenario: Equal strings share a code, and a null has none
    Given the file nulls.parquet
    When the file is opened
    And the column name is read
    Then every value of name is as written
    And name has 3 distinct codes
