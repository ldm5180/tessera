Feature: A null is a null, and its neighbours keep their places

  A column that may hold nulls says, row by row, whether there is a
  value; the values that are there stay in the rows they were written
  to, however many nulls fall between them.

  Background:
    Given the file nulls.parquet
    When the file is opened

  Scenario: Nulls among integers
    When the column count is read
    Then row 1 of count reads "938"
    And row 2 of count is null
    And every value of count is as written

  Scenario: Nulls among bit patterns and strings
    When the column price is read
    Then row 2 of price is null
    And every value of price is as written
    When the column name is read
    Then row 2 of name is null
    And every value of name is as written

  Scenario: A column of nothing but nulls
    When the column empty is read
    Then every row of empty is null
