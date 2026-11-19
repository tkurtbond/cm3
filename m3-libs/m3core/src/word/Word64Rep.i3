(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Word64 = GenWordN(Word64Rep).
   It imports the compiler's builtin Word64 for its type T. *)

INTERFACE Word64Rep;

IMPORT Word64;

TYPE T = Word64.T;

CONST Brand = "Word64";

END Word64Rep.
