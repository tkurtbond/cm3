(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Signed16 = GenSignedN(Signed16Rep).
   It imports the compiler's builtin Signed16 for its type T. *)

INTERFACE Signed16Rep;

IMPORT Signed16;

TYPE T = Signed16.T;

CONST Brand = "Signed16";

END Signed16Rep.
