(* This fork: an uncaught Signed8 * overflow is a runtime error. *)

MODULE Main;
IMPORT Signed8;
VAR a := Signed8.Wrap (16);  b := Signed8.Wrap (8);
BEGIN
  a := a * b;
END Main.
