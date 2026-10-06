--  The file in hand: which fixture a scenario reads.  A region of the
--  registry: Offer takes these steps, Reset starts a scenario, Phase
--  names its state.

package Tessera_Steps.Holding is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

   --  True once a scenario holds a file that is on disk.
   function Held return Boolean;

end Tessera_Steps.Holding;
