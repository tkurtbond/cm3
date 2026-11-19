(* See the file COPYRIGHT for a full description. *)

(* This fork: the interfaces Signed8, Signed16, Signed32 and Signed64,
   of signed fixed-width integers that are checked.  A T is a number
   in [-2^(Size-1) .. 2^(Size-1)-1].  The ordinary operators work on
   it, and a result outside that range is a checked runtime error
   (RuntimeError.IntegerOverflow).

   The compiler predefines these interfaces and compiles calls on
   their procedures inline.  This source must declare the same names,
   in the same order and with the same types and formal names, as
   the compiler (m3front's FixedType.InitializeInterfaces and
   FixedWord.Define), or the version stamps won't match. *)

GENERIC INTERFACE GenSignedN(Rep);

IMPORT Word;

TYPE
  T = Rep.T;

CONST
  Size : INTEGER = BITSIZE (T);

PROCEDURE Wrap (x: LONGINT): T;
(* The low Size bits of x, read as a two's complement number: x
   modulo 2^Size, in the range of T.  Never fails.  A call accepts
   INTEGER, LONGINT or any of the WordN.T or SignedN.T types, not only
   LONGINT; so Signed32.Wrap (w) reinterprets a Word32.T. *)

CONST Brand = Rep.Brand;

PROCEDURE Equal (a, b: T): BOOLEAN;  (* a = b *)
PROCEDURE Hash (a: T): Word.T;       (* a, as a Word.T *)
PROCEDURE Compare (a, b: T): [-1..1];
(* -1, 0 or 1 when a < b, a = b or a > b. *)

END GenSignedN.
