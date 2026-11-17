(* Operations that are easy to lower subtly wrongly: shifts and
   rotates, DIV and MOD, bit fields, sets and CASE. *)

INTERFACE Ops;

IMPORT Word, Long;

TYPE
  SmallSet = SET OF [0..31];        (* one word *)
  BigSet   = SET OF [0..199];       (* several words, not a multiple *)
  Packed   = RECORD
    a: BITS 3 FOR [-4..3];
    b: BITS 5 FOR [0..31];
    c: BITS 7 FOR [-64..63];
    d: BITS 13 FOR [0..8191];
  END;

PROCEDURE Shift (x: Word.T; n: INTEGER): Word.T;
PROCEDURE Rotate (x: Word.T; n: INTEGER): Word.T;
PROCEDURE LeftShift (x: Word.T; n: [0..Word.Size-1]): Word.T;
PROCEDURE RightShift (x: Word.T; n: [0..Word.Size-1]): Word.T;
PROCEDURE LongShift (x: Long.T; n: INTEGER): Long.T;

PROCEDURE Div (a, b: INTEGER): INTEGER;
PROCEDURE Mod (a, b: INTEGER): INTEGER;
PROCEDURE Div8 (a: INTEGER): INTEGER;
PROCEDURE Mod8 (a: INTEGER): INTEGER;
PROCEDURE LongDiv (a, b: LONGINT): LONGINT;
PROCEDURE LongMod (a, b: LONGINT): LONGINT;
PROCEDURE UDiv (a, b: Word.T): Word.T;
PROCEDURE UMod (a, b: Word.T): Word.T;
PROCEDURE ULess (a, b: Word.T): BOOLEAN;

PROCEDURE Extract (x: Word.T; i, n: CARDINAL): Word.T;
PROCEDURE Extract3_5 (x: Word.T): Word.T;
PROCEDURE Insert (x, y: Word.T; i, n: CARDINAL): Word.T;
PROCEDURE Insert60_4 (x, y: Word.T): Word.T;
PROCEDURE GetA (READONLY p: Packed): INTEGER;
PROCEDURE GetC (READONLY p: Packed): INTEGER;
PROCEDURE SetC (VAR p: Packed; v: [-64..63]);
PROCEDURE SetD (VAR p: Packed; v: [0..8191]);

PROCEDURE Union (a, b: BigSet): BigSet;
PROCEDURE Difference (a, b: BigSet): BigSet;
PROCEDURE Intersection (a, b: BigSet): BigSet;
PROCEDURE SymDifference (a, b: BigSet): BigSet;
PROCEDURE Range (lo, hi: [0..199]): BigSet;
PROCEDURE Singleton (i: [0..199]): BigSet;
PROCEDURE Member (READONLY s: BigSet; i: [0..199]): BOOLEAN;
PROCEDURE Subset (READONLY a, b: BigSet): BOOLEAN;
PROCEDURE ProperSubset (READONLY a, b: BigSet): BOOLEAN;
PROCEDURE Equal (READONLY a, b: BigSet): BOOLEAN;
PROCEDURE SmallUnion (a, b: SmallSet): SmallSet;
PROCEDURE SmallRange (lo, hi: [0..31]): SmallSet;
PROCEDURE SmallMember (s: SmallSet; i: [0..31]): BOOLEAN;
PROCEDURE SmallSubset (a, b: SmallSet): BOOLEAN;

PROCEDURE Classify (i: INTEGER): INTEGER;
PROCEDURE ClassifyChar (c: CHAR): TEXT;

PROCEDURE Floor (x: LONGREAL): INTEGER;
PROCEDURE Ceiling (x: LONGREAL): INTEGER;
PROCEDURE Round (x: LONGREAL): INTEGER;
PROCEDURE Trunc (x: LONGREAL): INTEGER;
PROCEDURE RealMod (x, y: REAL): REAL;
PROCEDURE ToReal (i: INTEGER): REAL;
PROCEDURE Abs (i: INTEGER): INTEGER;
PROCEDURE Min (a, b: INTEGER): INTEGER;
PROCEDURE Max (a, b: Word.T): Word.T;

END Ops.
