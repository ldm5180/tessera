--  Reading a column of the open file, and what it reads back as: every
--  value as written, and how many distinct codes a string column holds
--  (read.feature, dictionary.feature, nulls.feature, types.feature).
--  A region of the registry: Offer takes these steps, Reset starts a
--  scenario, Phase names its state.

package Tessera_Steps.Reading is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Tessera_Steps.Reading;
