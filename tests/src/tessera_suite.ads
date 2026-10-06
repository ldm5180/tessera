with AUnit.Test_Suites;

--  Every unit's tests, one Test_Case per library unit.

package Tessera_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Tessera_Suite;
