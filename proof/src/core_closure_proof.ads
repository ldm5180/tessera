with Tessera;
with Tessera.Thrift;

--  Withs every core unit so the whole SPARK closure is in gnatprove's
--  tree even when a unit temporarily has no other proof-side client.

package Core_Closure_Proof
  with SPARK_Mode
is

end Core_Closure_Proof;
