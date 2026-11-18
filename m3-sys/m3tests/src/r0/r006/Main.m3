(* This fork: VAL into a fixed-width integer type is range checked. *)

MODULE Main;
IMPORT Word64;

VAR l := -1L;  g: Word64.T;

BEGIN
  g := VAL (l, Word64.T);
END Main.
