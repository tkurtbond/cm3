(* This fork: VAL of a Word64.T above LAST (INTEGER) to INTEGER is
   range checked. *)

MODULE Main;
IMPORT Word64;
VAR w := Word64.LeftShift (VAL (1, Word64.T), 63);  i: INTEGER;
BEGIN
  i := VAL (w, INTEGER);
END Main.
