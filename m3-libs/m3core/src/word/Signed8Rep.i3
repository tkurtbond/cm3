(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Signed8 = GenSignedN(Signed8Rep).
   It imports the compiler's builtin Signed8 for its type T. *)

INTERFACE Signed8Rep;

IMPORT Signed8;

TYPE T = Signed8.T;

CONST Brand = "Signed8";

END Signed8Rep.
