(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Word16 = GenWordN(Word16Rep).
   It imports the compiler's builtin Word16 for its type T. *)

INTERFACE Word16Rep;

IMPORT Word16;

TYPE T = Word16.T;

CONST Brand = "Word16";

END Word16Rep.
