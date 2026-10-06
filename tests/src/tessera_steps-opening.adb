with Interfaces; use Interfaces;

with Fabula.Numbers;

with Tessera;        use Tessera;
with Tessera.Footer; use Tessera.Footer;
with Tessera.Files;  use Tessera.Files;
with Tessera_World;  use Tessera_World;

with Tessera_Steps.Flows;
with Tessera_Steps.Holding;

package body Tessera_Steps.Opening is

   --  Shut until an open is asked for; Settling while its verdict is
   --  read; then Open, or Refused.
   type State is (Shut, Settling, Open, Refused);

   type Guard_Kind is
     (Always,
      File_Held,
      Opened_Ok,
      Columns_Match,
      Counts_Match,
      Group_Rows_Match,
      May_Be_Null);

   type Action_Kind is
     (A_Nothing,
      A_Open,
      A_Refuse_No_File,
      A_Refuse_Refused,
      A_Refuse_Columns,
      A_Refuse_Counts,
      A_Refuse_Group_Rows,
      A_Refuse_Not_Null);

   --  The captures: the first number a step names, then the second.
   First_Number  : constant := 1;
   Second_Number : constant := 2;

   function Number (Ctx : Step_Context; N : Positive) return Integer
   is (Fabula.Numbers.Integer_Reads.Value_Or (Fabula.Args.Int (Ctx.A, N), -1));

   function Columns return Column_Count
   is (Column_Total (Open_File));

   function Schema (K : Column_Number) return Column_Info
   is (Tessera.Files.Column (Open_File, K));

   --  The table's row R as the footer would state it.
   function Row_Text (Ctx : Step_Context; R : Positive) return String
   is (Fabula.Args.Hash_Value (Ctx.A, R, "name")
       & "|"
       & Fabula.Args.Hash_Value (Ctx.A, R, "type")
       & "|"
       & Fabula.Args.Hash_Value (Ctx.A, R, "annotation"));

   function Column_Text (K : Column_Number) return String
   is (Name_Of (Schema (K))
       & "|"
       & Type_Name (Schema (K).Kind)
       & "|"
       & Note_Name (Schema (K).Note));

   --  The first column whose name, type or annotation differs from the
   --  table's row; 0 when every one agrees and there are as many.
   function First_Difference (Ctx : Step_Context) return Natural is
      Rows : constant Natural := Fabula.Args.Row_Count (Ctx.A) - 1;
   begin
      for K in 1 .. Natural'Min (Rows, Columns) loop
         if Row_Text (Ctx, K) /= Column_Text (K) then
            return K;
         end if;
      end loop;
      return (if Rows = Columns then 0 else Natural'Min (Rows, Columns) + 1);
   end First_Difference;

   function Group_Asked (Ctx : Step_Context) return Integer
   is (Number (Ctx, First_Number));

   function Group_Rows_Ok (Ctx : Step_Context) return Boolean
   is (Group_Asked (Ctx) in 1 .. Row_Groups (Open_File)
       and then Group_Rows (Open_File, Group_Asked (Ctx))
                = Number (Ctx, Second_Number));

   function Column_Asked (Ctx : Step_Context) return Column_Count
   is (Tessera.Files.Find (Open_File, Fabula.Args.Word (Ctx.A, 1)));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always           => True,
           when File_Held        => Holding.Held,
           when Opened_Ok        => Opened.Ok,
           when Columns_Match    => First_Difference (Ctx) = 0,
           when Counts_Match     =>
             Rows (Open_File) = Integer_64 (Number (Ctx, First_Number))
             and then Row_Groups (Open_File) = Number (Ctx, Second_Number),
           when Group_Rows_Match => Group_Rows_Ok (Ctx),
           when May_Be_Null      =>
             Column_Asked (Ctx) > 0
             and then Schema (Column_Asked (Ctx)).Optional);
   end Evaluate;

   function Refusal_Text return String
   is (Opened.Why'Image
       & " (column"
       & Opened.Column'Image
       & ", value"
       & Opened.Value'Image
       & ")");

   function Column_Difference (Ctx : Step_Context) return String is
      K : constant Natural := First_Difference (Ctx);
   begin
      return
        (if K > Columns
         then "the table lists more columns than the file's" & Columns'Image
         elsif K >= Fabula.Args.Row_Count (Ctx.A)
         then "the file has more columns than the table's"
         else
           "column"
           & K'Image
           & " is "
           & Column_Text (K)
           & ", not "
           & Row_Text (Ctx, K));
   end Column_Difference;

   function Counts_Text return String
   is ("the file has"
       & Rows (Open_File)'Image
       & " rows in"
       & Row_Groups (Open_File)'Image
       & " row groups");

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
         when A_Nothing           =>
            null;

         when A_Open              =>
            Tessera_World.Open (To_String (Ctx.W.Path));
            Then_Take (Ctx, E_Open_Settled);

         when A_Refuse_No_File    =>
            Fail (Ctx, "no file is in hand to open");

         when A_Refuse_Refused    =>
            Fail (Ctx, "the file was refused: " & Refusal_Text);

         when A_Refuse_Columns    =>
            Fail (Ctx, Column_Difference (Ctx));

         when A_Refuse_Counts     =>
            Fail (Ctx, Counts_Text);

         when A_Refuse_Group_Rows =>
            Fail (Ctx, "no such row group, or not that many rows");

         when A_Refuse_Not_Null   =>
            Fail (Ctx, "no such column, or it holds no nulls");
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

   Open_File     : constant Ev := (Kind => E_Open);
   Open_Settled  : constant Ev := (Kind => E_Open_Settled);
   Check_Opens   : constant Ev := (Kind => E_Check_Opens);
   Check_Columns : constant Ev := (Kind => E_Check_Columns);
   Check_Counts  : constant Ev := (Kind => E_Check_Counts);
   Check_Group   : constant Ev := (Kind => E_Check_Group_Rows);
   Check_Null    : constant Ev := (Kind => E_Check_Nullable);

   --!format off
   Table : constant Transition_Table :=
     [Shut     + Open_File     (File_Held)        / A_Open              >= Settling,
      Shut     + Open_File                        / A_Refuse_No_File    >= Shut,
      Settling + Open_Settled  (Opened_Ok)                              >= Open,
      Settling + Open_Settled                                           >= Refused,
      Open     + Open_File     (File_Held)        / A_Open              >= Settling,
      Refused  + Open_File     (File_Held)        / A_Open              >= Settling,
      Open     + Check_Opens                                            >= Open,
      Refused  + Check_Opens                      / A_Refuse_Refused    >= Refused,
      Open     + Check_Columns (Columns_Match)                          >= Open,
      Open     + Check_Columns                    / A_Refuse_Columns    >= Open,
      Open     + Check_Counts  (Counts_Match)                           >= Open,
      Open     + Check_Counts                     / A_Refuse_Counts     >= Open,
      Open     + Check_Group   (Group_Rows_Match)                       >= Open,
      Open     + Check_Group                      / A_Refuse_Group_Rows >= Open,
      Open     + Check_Null    (May_Be_Null)                            >= Open,
      Open     + Check_Null                       / A_Refuse_Not_Null   >= Open];
   --!format on

   Current : State := Shut;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Shut;
   end Reset;

   function Phase return String
   is (Current'Image);

   function Is_Open return Boolean
   is (Current = Open);

end Tessera_Steps.Opening;
