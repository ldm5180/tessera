with AUnit.Test_Cases; use AUnit.Test_Cases;

with Tessera_Footer_Tests;
with Tessera_Snappy_Tests;
with Tessera_Thrift_Read_Struct_Tests;
with Tessera_Thrift_Tests;

package body Tessera_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        AUnit.Test_Suites.New_Suite;
   begin
      Result.Add_Test (Test_Case_Access'(new Tessera_Thrift_Tests.Test));
      Result.Add_Test
        (Test_Case_Access'(new Tessera_Thrift_Read_Struct_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Tessera_Footer_Tests.Test));
      Result.Add_Test (Test_Case_Access'(new Tessera_Snappy_Tests.Test));
      return Result;
   end Suite;

end Tessera_Suite;
