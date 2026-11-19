(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Signed32 = GenSignedN(Signed32Rep).
   It imports the compiler's builtin Signed32 for its type T. *)

INTERFACE Signed32Rep;

IMPORT Signed32;

TYPE T = Signed32.T;

CONST Brand = "Signed32";

END Signed32Rep.
