with Ada.Command_Line; use Ada.Command_Line;
with Ada.Text_IO;      use Ada.Text_IO;

with Tessera;        use Tessera;
with Tessera.Files;  use Tessera.Files;
with Tessera.Footer; use Tessera.Footer;
with Tessera.Names;

with Bench_Columns;

--  tessera_bench FILE [COLUMN ...]: opens FILE and benches each COLUMN
--  named, or every column when none is (Bench_Columns.Bench); the last
--  line says whether every one read all the footer's rows.

procedure Tessera_Bench is
   F      : File;
   Result : Outcome;
   Ok     : Boolean;
   All_Ok : Boolean := True;
begin
   if Argument_Count < 1 then
      Put_Line ("usage: tessera_bench FILE [COLUMN ...]");
      Set_Exit_Status (Failure);
      return;
   end if;
   Open (Argument (1), F, Result);
   if not Result.Ok then
      Put_Line ("refused: " & Tessera.Names.Describe (Result));
      Set_Exit_Status (Failure);
      return;
   end if;
   Put_Line
     (Argument (1)
      & ":"
      & Rows (F)'Image
      & " rows,"
      & Row_Groups (F)'Image
      & " row groups,"
      & Column_Total (F)'Image
      & " columns");
   for A in
     1 .. (if Argument_Count = 1 then Column_Total (F) else Argument_Count - 1)
   loop
      Bench_Columns.Bench
        (F,
         (if Argument_Count = 1
          then Name_Of (Column (F, A))
          else Argument (A + 1)),
         Ok);
      All_Ok := All_Ok and then Ok;
   end loop;
   Put_Line
     (if All_Ok
      then "every column read all" & Rows (F)'Image & " rows"
      else "NOT every column read all the footer's rows");
   Set_Exit_Status (if All_Ok then Success else Failure);
end Tessera_Bench;
