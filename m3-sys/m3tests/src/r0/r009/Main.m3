(* This fork: VAL of a negative INTEGER to Word32.T is range checked. *)

MODULE Main;
IMPORT Word32;
VAR i := -1;  w: Word32.T;
BEGIN
  w := VAL (i, Word32.T);
END Main.
