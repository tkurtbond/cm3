(* See the file COPYRIGHT for a full description. *)

(* This fork: the procedures of the builtin interfaces Word8 .. Word64.
   Each interface offers the Word procedures at its width (in the order
   of m3core's GenWord.ig), then Wrap, FromWord, ToWord, FromLong,
   ToLong, Brand, Equal, Hash and Compare (in the order of m3core's
   GenWordN.ig; the orders must match, or the version stamps won't).
   Calls compile inline, operating in the stack type of the fixed
   type and masking the result to its width.  m3core's WordN modules
   wrap them, so they can also be used as procedure values.

   Signed8 .. Signed64 offer only Wrap, Brand, Equal, Hash and Compare
   (in the order of m3core's GenSignedN.ig).  Their Wrap sign-extends
   the low N bits. *)

INTERFACE FixedWord;

IMPORT Type;

PROCEDURE Define (t: Type.T;  name: TEXT);
(* Declare the procedures and constants that follow T and Size in
   the interface 'name' for the fixed type 't', in the current
   scope. *)

END FixedWord.
