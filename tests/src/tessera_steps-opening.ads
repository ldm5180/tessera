--  Opening the file in hand, and what its footer says: whether it
--  opened, its columns, its rows and its row groups (schema.feature).
--  A region of the registry: Offer takes these steps, Reset starts a
--  scenario, Phase names its state.

package Tessera_Steps.Opening is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

   --  True once the file in hand opened.
   function Is_Open return Boolean;

end Tessera_Steps.Opening;
