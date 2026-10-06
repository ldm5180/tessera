--  Reading a file in full, and the refusal it meets: by its name, and
--  naming its column (refusals.feature).  A region of the registry:
--  Offer takes these steps, Reset starts a scenario, Phase names its
--  state.

package Tessera_Steps.Refusing is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Tessera_Steps.Refusing;
