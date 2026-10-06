with Ada.Directories;

with Tessera_World;

with Tessera_Steps.Flows;

package body Tessera_Steps.Holding is

   --  Empty-handed until a fixture on disk is named.
   type State is (Empty, Holding);

   type Guard_Kind is (Always, On_Disk);

   type Action_Kind is (A_Nothing, A_Hold, A_Refuse_Missing);

   File_Name : constant := 1;

   function Path_Of (Ctx : Step_Context) return String
   is (Tessera_World.Fixture (Ctx.Info, Fabula.Args.Word (Ctx.A, File_Name)));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always  => True,
           when On_Disk => Ada.Directories.Exists (Path_Of (Ctx)));
   end Evaluate;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing        =>
            null;

         when A_Hold           =>
            Ctx.W.Path := To_Unbounded_String (Path_Of (Ctx));

         when A_Refuse_Missing =>
            Fabula.Check.Fail_Step
              (Ctx.R, "no fixture on disk at " & Path_Of (Ctx));
      end case;
   end Execute;

   package Flow is new
     Tessera_Steps.Flows
       (State       => State,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Action_Kind,
        Evaluate    => Evaluate,
        Execute     => Execute,
        Always      => Always,
        Nothing     => A_Nothing);

   use Flow.Machines;
   use Flow.Op;

   Hold_File : constant Ev := (Kind => E_Hold_File);

   --!format off
   Table : constant Transition_Table :=
     [Empty   + Hold_File (On_Disk) / A_Hold           >= Holding,
      Empty   + Hold_File           / A_Refuse_Missing >= Empty,
      Holding + Hold_File (On_Disk) / A_Hold           >= Holding,
      Holding + Hold_File           / A_Refuse_Missing >= Empty];
   --!format on

   Current : State := Empty;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Empty;
   end Reset;

   function Phase return String
   is (Current'Image);

   function Held return Boolean
   is (Current = Holding);

end Tessera_Steps.Holding;
