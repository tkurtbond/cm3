(* This fork: an uncaught Signed64 + overflow is a runtime error. *)

MODULE Main;
IMPORT Signed64;
VAR a := LAST (Signed64.T);  b := Signed64.Wrap (1);
BEGIN
  a := a + b;
END Main.
