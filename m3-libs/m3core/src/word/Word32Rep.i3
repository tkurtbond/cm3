(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Word32 = GenWordN(Word32Rep).
   It imports the compiler's builtin Word32 for its type T. *)

INTERFACE Word32Rep;

IMPORT Word32;

TYPE T = Word32.T;

CONST Brand = "Word32";

END Word32Rep.
