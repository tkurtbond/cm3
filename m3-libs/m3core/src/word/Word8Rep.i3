(* See the file COPYRIGHT for a full description. *)

(* This fork: the representation for Word8 = GenWordN(Word8Rep).
   It imports the compiler's builtin Word8 for its type T. *)

INTERFACE Word8Rep;

IMPORT Word8;

TYPE T = Word8.T;

CONST Brand = "Word8";

END Word8Rep.
