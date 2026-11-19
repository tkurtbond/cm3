(* See the file COPYRIGHT for a full description. *)

(* This fork: the interfaces Word8, Word16, Word32 and Word64, of
   unsigned fixed-width integers that wrap around.  A T is a number
   in [0 .. 2^Size-1]; the Word operations work on it modulo 2^Size.

   The compiler predefines these interfaces and compiles calls on
   their procedures inline.  This source must declare the same names,
   in the same order and with the same types and formal names, as
   the compiler (m3front's FixedType.InitializeInterfaces and
   FixedWord.Define), or the version stamps won't match. *)

GENERIC INTERFACE GenWordN(Rep);

IMPORT Word, Long;

TYPE
  T = Rep.T;

CONST
  Size : INTEGER = BITSIZE (T);

PROCEDURE Plus (x, y: T): T;         (* (x + y) MOD 2^Size *)
PROCEDURE Times (x, y: T): T;        (* (x * y) MOD 2^Size *)
PROCEDURE Minus (x, y: T): T;        (* (x - y) MOD 2^Size *)
PROCEDURE Divide (x, y: T): T;       (* x DIV y *)
PROCEDURE Mod (x, y: T): T;          (* x MOD y *)
PROCEDURE LT (x, y: T): BOOLEAN;     (* x < y *)
PROCEDURE LE (x, y: T): BOOLEAN;     (* x <= y *)
PROCEDURE GT (x, y: T): BOOLEAN;     (* x > y *)
PROCEDURE GE (x, y: T): BOOLEAN;     (* x >= y *)
PROCEDURE And (x, y: T): T;          (* Bitwise AND of x and y *)
PROCEDURE Or (x, y: T): T;           (* Bitwise OR of x and y *)
PROCEDURE Xor (x, y: T): T;          (* Bitwise XOR of x and y *)
PROCEDURE Not (x: T): T;             (* Bitwise complement of x *)

PROCEDURE Shift (x: T; n: INTEGER): T;
(* For all i such that both i and i - n are in [0 .. Size - 1], bit i
   of the result equals bit i - n of x.  The other bits are 0. *)

PROCEDURE LeftShift (x: T; n: [0..Size-1]): T;
(* = Shift (x, n) *)

PROCEDURE RightShift (x: T; n: [0..Size-1]): T;
(* = Shift (x, -n) *)

PROCEDURE Rotate (x: T; n: INTEGER): T;
(* Bit i of the result equals bit (i - n) MOD Size of x. *)

PROCEDURE LeftRotate (x: T; n: [0..Size-1]): T;
(* = Rotate (x, n) *)

PROCEDURE RightRotate (x: T; n: [0..Size-1]): T;
(* = Rotate (x, -n) *)

PROCEDURE Extract (x: T; i, n: CARDINAL): T;
(* Take n bits from x, with bit i as the least significant bit.  A
   checked runtime error if n + i > Size. *)

PROCEDURE Insert (x, y: T; i, n: CARDINAL): T;
(* Return x with n bits, from bit i up, replaced by the least
   significant n bits of y.  A checked runtime error if n + i > Size. *)

PROCEDURE Wrap (x: LONGINT): T;
(* x MOD 2^Size.  A call accepts INTEGER, LONGINT or any of the
   WordN.T types, not only LONGINT. *)

PROCEDURE FromWord (w: Word.T): T;
(* The low Size bits of w. *)

PROCEDURE ToWord (x: T): Word.T;
(* x, as a Word.T.  When Size = Word.Size this is LOOPHOLE (x, Word.T),
   which is negative when x >= 2^(Size-1). *)

PROCEDURE FromLong (l: Long.T): T;
(* The low Size bits of l. *)

PROCEDURE ToLong (x: T): Long.T;
(* x, as a Long.T; like ToWord. *)

CONST Brand = Rep.Brand;

PROCEDURE Equal (a, b: T): BOOLEAN;  (* a = b *)
PROCEDURE Hash (a: T): Word.T;       (* = ToWord (a) *)
PROCEDURE Compare (a, b: T): [-1..1];
(* -1, 0 or 1 when a < b, a = b or a > b. *)

END GenWordN.
