with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Args;
with Fabula.Check;
with Fabula.Frames;
with Fabula.Registry;

--  The step registry the feature runner dispatches on: one Step_Kind
--  per pattern, one table that reads like the features, and one Execute
--  that offers each step to every feature's state machine.

package Tessera_Steps is

   --  The steps.  Each is an event of one feature's state machine, in
   --  its own child package.
   type Step_Kind is
     (E_Hold_File,
      E_Open,
      E_Check_Opens,
      E_Check_Columns,
      E_Check_Counts,
      E_Check_Group_Rows,
      E_Check_Nullable,
      E_Read_Column,
      E_Check_Values,
      E_Check_Codes,
      E_Read_Every,
      E_Check_Every,
      E_Read_Full,
      E_Check_Refused,
      E_Check_Refused_Column,
      --  An event no pattern names: an open posts it, and the next row's
      --  guard reads whether the file opened.
      E_Open_Settled,
      --  Posted by a read, as E_Open_Settled is by an open.
      E_Read_Settled);

   type Hook_Kind is (Fresh_World);

   --  What one scenario holds: the path of the file in hand.  fabula
   --  copies it per step, so it holds small values only; what is read
   --  out of the file lives in Tessera_World.
   type World is record
      Path : Unbounded_String;
   end record;

   --  One step as a machine sees it: the scenario, the step's arguments,
   --  frame and outcome, and the event an action asks to be taken next
   --  (Then_Take), which the runner posts before the step returns.
   type Step_Context is record
      W        : World;
      A        : Fabula.Args.List;
      Info     : Fabula.Frames.Frame;
      R        : Fabula.Check.Outcome;
      Has_Next : Boolean := False;
      Next     : Step_Kind := Step_Kind'First;
   end record;

   procedure Then_Take (Ctx : in out Step_Context; Evt : Step_Kind);

   package Steps is new
     Fabula.Registry
       (Step_Kind => Step_Kind,
        Hook_Kind => Hook_Kind,
        Context   => World);
   use Steps;

   --!format off
   Step_Defs : constant Steps.Step_Table :=
     [Step ("the file {word}")               >= E_Hold_File,
      Step ("the file is opened")            >= E_Open,
      Step ("the file is open")              >= E_Check_Opens,
      Step ("its columns are:")              >= E_Check_Columns,
      Step ("it has {int} rows in {int} row group(s)")
                                             >= E_Check_Counts,
      Step ("row group {int} has {int} rows")
                                             >= E_Check_Group_Rows,
      Step ("the column {word} may hold nulls")
                                             >= E_Check_Nullable,
      Step ("the column {word} is read")     >= E_Read_Column,
      Step ("every value of {word} is as written")
                                             >= E_Check_Values,
      Step ("{word} has {int} distinct codes")
                                             >= E_Check_Codes,
      Step ("every column is read")          >= E_Read_Every,
      Step ("every value of every column is as written")
                                             >= E_Check_Every,
      Step ("the file is read in full")      >= E_Read_Full,
      Step ("it is refused as {}")           >= E_Check_Refused,
      Step ("the refusal names the column {word}")
                                             >= E_Check_Refused_Column];
   --!format on

   Hook_Defs : constant Steps.Hook_Table := [Before >= Fresh_World];

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out World;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out World;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome);

end Tessera_Steps;
