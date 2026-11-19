(* This fork: Word32.LeftShift checks its shift count. *)

MODULE Main;
IMPORT Word32;

VAR a := VAL (1, Word32.T);  n := 32;

BEGIN
  a := Word32.LeftShift (a, n);
END Main.
