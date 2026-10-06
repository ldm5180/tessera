with Tessera; use Tessera;
with Tessera.Files;
with Tessera.Names;
with Tessera_World;

with Tessera_Steps.Flows;
with Tessera_Steps.Holding;

package body Tessera_Steps.Refusing is

   --  Idle until the file in hand is read in full; then Read_Through,
   --  with the verdict it met.
   type State is (Idle, Read_Through);

   type Guard_Kind is (Always, File_Held, Refused_As, Names_Column);

   type Action_Kind is
     (A_Nothing,
      A_Read_In_Full,
      A_Refuse_No_File,
      A_Refuse_Verdict,
      A_Refuse_Column);

   Capture : constant := 1;

   --  What reading the file in full met.
   Verdict : Outcome;

   function Said (Ctx : Step_Context) return String
   is (Fabula.Args.Text (Ctx.A, Capture));

   function Column_Named (Ctx : Step_Context) return Column_Count
   is (Tessera.Files.Find
         (Tessera_World.Open_File, Fabula.Args.Word (Ctx.A, Capture)));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always       => True,
           when File_Held    => Holding.Held,
           when Refused_As   =>
             not Verdict.Ok
             and then Tessera.Names.Describe (Verdict) = Said (Ctx),
           when Names_Column =>
             not Verdict.Ok
             and then Column_Named (Ctx) > 0
             and then Verdict.Column = Column_Named (Ctx));
   end Evaluate;

   function Verdict_Text return String
   is (if Verdict.Ok
       then "it was read in full"
       else
         "it was refused as "
         & Tessera.Names.Describe (Verdict)
         & ", column"
         & Verdict.Column'Image);

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing                          =>
            null;

         when A_Read_In_Full                     =>
            Verdict := Tessera_World.Read_In_Full (To_String (Ctx.W.Path));

         when A_Refuse_No_File                   =>
            Fabula.Check.Fail_Step (Ctx.R, "no file is in hand to read");

         when A_Refuse_Verdict | A_Refuse_Column =>
            Fabula.Check.Fail_Step (Ctx.R, Verdict_Text);
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

   Read_Full    : constant Ev := (Kind => E_Read_Full);
   Check_Refuse : constant Ev := (Kind => E_Check_Refused);
   Check_Column : constant Ev := (Kind => E_Check_Refused_Column);

   --!format off
   Table : constant Transition_Table :=
     [Idle         + Read_Full    (File_Held)    / A_Read_In_Full   >= Read_Through,
      Idle         + Read_Full                   / A_Refuse_No_File >= Idle,
      Read_Through + Check_Refuse (Refused_As)                      >= Read_Through,
      Read_Through + Check_Refuse                / A_Refuse_Verdict >= Read_Through,
      Read_Through + Check_Column (Names_Column)                    >= Read_Through,
      Read_Through + Check_Column                / A_Refuse_Column  >= Read_Through];
   --!format on

   Current : State := Idle;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Idle;
      Verdict := Done;
   end Reset;

   function Phase return String
   is (Current'Image);

end Tessera_Steps.Refusing;
