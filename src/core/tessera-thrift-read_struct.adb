with Sml.Simple_Machines;

procedure Tessera.Thrift.Read_Struct
  (Input : Bytes; C : in out Cursor; Into : in out Target)
with SPARK_Mode
is

   --  Between fields, inside one (its value due), at the stop, or
   --  broken.
   type State is (Between, In_Field, Stopped, Broken);

   type Event is (E_Field, E_Stop, E_Fault, E_Value_Taken);

   type Guard_Kind is (Always, Is_Known);

   type Action_Kind is (Nothing, Want_Read, Want_Skip);

   --  What the driver does with the field due: read it, or skip it.
   type Command is (None, Read, Skip_It);

   type Context is record
      Header  : Field_Header;
      Pending : Command := None;
   end record;

   function Evaluate
     (G : Guard_Kind; Ctx : Context; Evt : Event) return Boolean
   is (case G is
         when Always   => True,
         when Is_Known => Evt = E_Field and then Known (Ctx.Header));

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event);

   procedure Execute (A : Action_Kind; Ctx : in out Context; Evt : Event) is
      pragma Unreferenced (Evt);
   begin
      Ctx.Pending :=
        (case A is
           when Nothing   => None,
           when Want_Read => Read,
           when Want_Skip => Skip_It);
   end Execute;

   package Machines is new
     Sml.Simple_Machines
       (State       => State,
        Event       => Event,
        Context     => Context,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Action_Kind,
        Evaluate    => Evaluate,
        Execute     => Execute);
   use Machines;

   --!format off
   Table : constant Transition_Table :=
     [(Between,  E_Field,       Is_Known, Want_Read, In_Field),
      (Between,  E_Field,       Always,   Want_Skip, In_Field),
      (Between,  E_Stop,        Always,   Nothing,   Stopped),
      (Between,  E_Fault,       Always,   Nothing,   Broken),
      (In_Field, E_Value_Taken, Always,   Nothing,   Between),
      (In_Field, E_Fault,       Always,   Nothing,   Broken)];
   --!format on

   --  The event a header read gives.
   function Header_Event (Ok : Boolean; H : Field_Header) return Event
   is (if not Ok then E_Fault elsif H.Stop then E_Stop else E_Field);

   --  Every field takes at least its header byte, and two steps.
   function Step_Bound return Positive
   is (2 * Input'Length + 1);

   M       : Machine := Make (Table, Initial => Between);
   Ctx     : Context;
   Last_Id : Integer_16 := 0;
   Handled : Boolean;
begin
   if not C.Ok then
      return;
   end if;
   for Step in 1 .. Step_Bound loop
      exit when State_Of (M) in Stopped | Broken;
      if State_Of (M) = Between then
         Read_Field_Header (Input, C, Last_Id, Ctx.Header);
         Process_Event (M, Ctx, Header_Event (C.Ok, Ctx.Header), Handled);
      else
         if Ctx.Pending = Read then
            Read_Field (Input, C, Into, Ctx.Header);
         else
            Skip (Input, C, Ctx.Header.Kind);
         end if;
         Process_Event
           (M, Ctx, (if C.Ok then E_Value_Taken else E_Fault), Handled);
      end if;
      exit when not Handled;
   end loop;
   if State_Of (M) /= Stopped or else not Within (C, Input) then
      C.Ok := False;
   end if;
end Tessera.Thrift.Read_Struct;
