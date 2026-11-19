(* This fork: VAL of a Word32.T above 255 to Word8.T is range checked. *)

MODULE Main;
IMPORT Word8, Word32;
VAR w := VAL (256, Word32.T);  b: Word8.T;
BEGIN
  b := VAL (w, Word8.T);
END Main.
