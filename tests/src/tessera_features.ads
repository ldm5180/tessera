with Fabula.Main;

with Tessera_Steps;

--  The feature runner: Fabula.Main over the crate's step registry,
--  run over tests/features/ by `make features` and `alr test`.

procedure Tessera_Features is new
  Fabula.Main
    (Steps     => Tessera_Steps.Steps,
     Step_Defs => Tessera_Steps.Step_Defs,
     Hook_Defs => Tessera_Steps.Hook_Defs,
     Execute   => Tessera_Steps.Execute,
     Run_Hook  => Tessera_Steps.Run_Hook);
