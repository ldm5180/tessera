with Fabula.Numbers;

with Tessera;        use Tessera;
with Tessera.Footer; use Tessera.Footer;
with Tessera_World;  use Tessera_World;

with Tessera_Steps.Flows;
with Tessera_Steps.Opening;

package body Tessera_Steps.Reading is

   --  Unread until a read is asked for; Settling while its verdict is
   --  read; then Read, or Refused.
   type State is (Unread, Settling, Read, Refused);

   type Guard_Kind is (Always, Can_Read, Read_Ok, Values_Match, Codes_Match);

   type Action_Kind is
     (A_Nothing,
      A_Read,
      A_Refuse_No_Column,
      A_Refuse_Refused,
      A_Refuse_Values,
      A_Refuse_Codes);

   Name_Capture  : constant := 1;
   Count_Capture : constant := 2;

   function Name (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, Name_Capture));

   function Count_Asked (Ctx : Step_Context) return Integer
   is (Fabula.Numbers.Integer_Reads.Value_Or
         (Fabula.Args.Int (Ctx.A, Count_Capture), -1));

   function Has_Column (Ctx : Step_Context) return Boolean
   is (Opening.Is_Open and then Find (Opened.Meta.all, Name (Ctx)) > 0);

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always       => True,
           when Can_Read     => Has_Column (Ctx),
           when Read_Ok      => Last_Read.Result.Ok,
           when Values_Match => First_Difference (Name (Ctx)) = 0,
           when Codes_Match  => Distinct_Codes = Count_Asked (Ctx));
   end Evaluate;

   function Refusal_Text return String
   is (Last_Read.Result.Why'Image
       & " (column"
       & Last_Read.Result.Column'Image
       & ", value"
       & Last_Read.Result.Value'Image
       & ")");

   function Difference_Text (Ctx : Step_Context) return String
   is ("row"
       & First_Difference (Name (Ctx))'Image
       & " of "
       & Name (Ctx)
       & " is not as written");

   procedure Fail (Ctx : in out Step_Context; Why : String) is
   begin
      Fabula.Check.Fail_Step (Ctx.R, Why);
   end Fail;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing          =>
            null;

         when A_Read             =>
            Read_Column (Name (Ctx));
            Then_Take (Ctx, E_Read_Settled);

         when A_Refuse_No_Column =>
            Fail (Ctx, "no open file has a column " & Name (Ctx));

         when A_Refuse_Refused   =>
            Fail (Ctx, "the column was refused: " & Refusal_Text);

         when A_Refuse_Values    =>
            Fail (Ctx, Difference_Text (Ctx));

         when A_Refuse_Codes     =>
            Fail (Ctx, "it holds" & Distinct_Codes'Image & " distinct codes");
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

   Read_Column  : constant Ev := (Kind => E_Read_Column);
   Read_Settled : constant Ev := (Kind => E_Read_Settled);
   Check_Values : constant Ev := (Kind => E_Check_Values);
   Check_Codes  : constant Ev := (Kind => E_Check_Codes);

   --!format off
   Table : constant Transition_Table :=
     [Unread   + Read_Column  (Can_Read)     / A_Read             >= Settling,
      Unread   + Read_Column                 / A_Refuse_No_Column >= Unread,
      Read     + Read_Column  (Can_Read)     / A_Read             >= Settling,
      Read     + Read_Column                 / A_Refuse_No_Column >= Read,
      Refused  + Read_Column  (Can_Read)     / A_Read             >= Settling,
      Refused  + Read_Column                 / A_Refuse_No_Column >= Refused,
      Settling + Read_Settled (Read_Ok)                           >= Read,
      Settling + Read_Settled                                     >= Refused,
      Read     + Check_Values (Values_Match)                      >= Read,
      Read     + Check_Values                / A_Refuse_Values    >= Read,
      Refused  + Check_Values                / A_Refuse_Refused   >= Refused,
      Read     + Check_Codes  (Codes_Match)                       >= Read,
      Read     + Check_Codes                 / A_Refuse_Codes     >= Read,
      Refused  + Check_Codes                 / A_Refuse_Refused   >= Refused];
   --!format on

   Current : State := Unread;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Unread;
   end Reset;

   function Phase return String
   is (Current'Image);

end Tessera_Steps.Reading;
