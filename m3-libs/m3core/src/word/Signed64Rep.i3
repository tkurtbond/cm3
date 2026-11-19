(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Signed64 = GenSignedN(Signed64Rep).
   It imports the compiler's builtin Signed64 for its type T. *)

INTERFACE Signed64Rep;

IMPORT Signed64;

TYPE T = Signed64.T;

CONST Brand = "Signed64";

END Signed64Rep.
