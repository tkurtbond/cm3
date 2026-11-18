MODULE Ops;

IMPORT Word, Long;

PROCEDURE Shift (x: Word.T; n: INTEGER): Word.T =
  BEGIN RETURN Word.Shift (x, n) END Shift;

PROCEDURE Rotate (x: Word.T; n: INTEGER): Word.T =
  BEGIN RETURN Word.Rotate (x, n) END Rotate;

PROCEDURE LeftShift (x: Word.T; n: [0..Word.Size-1]): Word.T =
  BEGIN RETURN Word.LeftShift (x, n) END LeftShift;

PROCEDURE RightShift (x: Word.T; n: [0..Word.Size-1]): Word.T =
  BEGIN RETURN Word.RightShift (x, n) END RightShift;

PROCEDURE LongShift (x: Long.T; n: INTEGER): Long.T =
  BEGIN RETURN Long.Shift (x, n) END LongShift;

PROCEDURE Div (a, b: INTEGER): INTEGER =
  BEGIN RETURN a DIV b END Div;

PROCEDURE Mod (a, b: INTEGER): INTEGER =
  BEGIN RETURN a MOD b END Mod;

PROCEDURE Div8 (a: INTEGER): INTEGER =
  BEGIN RETURN a DIV 8 END Div8;

PROCEDURE Mod8 (a: INTEGER): INTEGER =
  BEGIN RETURN a MOD 8 END Mod8;

PROCEDURE LongDiv (a, b: LONGINT): LONGINT =
  BEGIN RETURN a DIV b END LongDiv;

PROCEDURE LongMod (a, b: LONGINT): LONGINT =
  BEGIN RETURN a MOD b END LongMod;

PROCEDURE UDiv (a, b: Word.T): Word.T =
  BEGIN RETURN Word.Divide (a, b) END UDiv;

PROCEDURE UMod (a, b: Word.T): Word.T =
  BEGIN RETURN Word.Mod (a, b) END UMod;

PROCEDURE ULess (a, b: Word.T): BOOLEAN =
  BEGIN RETURN Word.LT (a, b) END ULess;

PROCEDURE Extract (x: Word.T; i, n: CARDINAL): Word.T =
  BEGIN RETURN Word.Extract (x, i, n) END Extract;

PROCEDURE Extract3_5 (x: Word.T): Word.T =
  BEGIN RETURN Word.Extract (x, 3, 5) END Extract3_5;

PROCEDURE Insert (x, y: Word.T; i, n: CARDINAL): Word.T =
  BEGIN RETURN Word.Insert (x, y, i, n) END Insert;

PROCEDURE Insert60_4 (x, y: Word.T): Word.T =
  BEGIN RETURN Word.Insert (x, y, 60, 4) END Insert60_4;

PROCEDURE GetA (READONLY p: Packed): INTEGER =
  BEGIN RETURN p.a END GetA;

PROCEDURE GetC (READONLY p: Packed): INTEGER =
  BEGIN RETURN p.c END GetC;

PROCEDURE SetC (VAR p: Packed; v: [-64..63]) =
  BEGIN p.c := v END SetC;

PROCEDURE SetD (VAR p: Packed; v: [0..8191]) =
  BEGIN p.d := v END SetD;

PROCEDURE Union (a, b: BigSet): BigSet =
  BEGIN RETURN a + b END Union;

PROCEDURE Difference (a, b: BigSet): BigSet =
  BEGIN RETURN a - b END Difference;

PROCEDURE Intersection (a, b: BigSet): BigSet =
  BEGIN RETURN a * b END Intersection;

PROCEDURE SymDifference (a, b: BigSet): BigSet =
  BEGIN RETURN a / b END SymDifference;

PROCEDURE Range (lo, hi: [0..199]): BigSet =
  BEGIN RETURN BigSet {lo .. hi} END Range;

PROCEDURE Singleton (i: [0..199]): BigSet =
  BEGIN RETURN BigSet {i} END Singleton;

PROCEDURE Member (READONLY s: BigSet; i: [0..199]): BOOLEAN =
  BEGIN RETURN i IN s END Member;

PROCEDURE Subset (READONLY a, b: BigSet): BOOLEAN =
  BEGIN RETURN a <= b END Subset;

PROCEDURE ProperSubset (READONLY a, b: BigSet): BOOLEAN =
  BEGIN RETURN a < b END ProperSubset;

PROCEDURE Equal (READONLY a, b: BigSet): BOOLEAN =
  BEGIN RETURN a = b END Equal;

PROCEDURE SmallUnion (a, b: SmallSet): SmallSet =
  BEGIN RETURN a + b END SmallUnion;

PROCEDURE SmallRange (lo, hi: [0..31]): SmallSet =
  BEGIN RETURN SmallSet {lo .. hi} END SmallRange;

PROCEDURE SmallMember (s: SmallSet; i: [0..31]): BOOLEAN =
  BEGIN RETURN i IN s END SmallMember;

PROCEDURE SmallSubset (a, b: SmallSet): BOOLEAN =
  BEGIN RETURN a <= b END SmallSubset;

PROCEDURE Classify (i: INTEGER): INTEGER =
  BEGIN
    CASE i OF
    | -3 => RETURN 1;
    | 0 => RETURN 2;
    | 1 => RETURN 3;
    | 2 .. 5 => RETURN 4;
    | 10, 12 => RETURN 5;
    | 100 => RETURN 6;
    | 1000000 .. 1000002 => RETURN 7;
    ELSE RETURN 0;
    END;
  END Classify;

PROCEDURE ClassifyChar (c: CHAR): TEXT =
  BEGIN
    CASE c OF
    | 'a' .. 'z' => RETURN "lower";
    | 'A' .. 'Z' => RETURN "upper";
    | '0' .. '9' => RETURN "digit";
    | ' ', '\t', '\n' => RETURN "space";
    | '\377' => RETURN "255";
    ELSE RETURN "other";
    END;
  END ClassifyChar;

PROCEDURE Floor (x: LONGREAL): INTEGER =
  BEGIN RETURN FLOOR (x) END Floor;

PROCEDURE Ceiling (x: LONGREAL): INTEGER =
  BEGIN RETURN CEILING (x) END Ceiling;

PROCEDURE Round (x: LONGREAL): INTEGER =
  BEGIN RETURN ROUND (x) END Round;

PROCEDURE Trunc (x: LONGREAL): INTEGER =
  BEGIN RETURN TRUNC (x) END Trunc;

PROCEDURE RealMod (x, y: REAL): REAL =
  BEGIN RETURN x MOD y END RealMod;

PROCEDURE ToReal (i: INTEGER): REAL =
  BEGIN RETURN FLOAT (i) END ToReal;

PROCEDURE AddGt (x: INTEGER): BOOLEAN =
  BEGIN RETURN x + 1 > x END AddGt;

PROCEDURE LongAddGt (x: LONGINT): BOOLEAN =
  BEGIN RETURN x + 1L > x END LongAddGt;

PROCEDURE SubLt (x: INTEGER): BOOLEAN =
  BEGIN RETURN x - 1 < x END SubLt;

PROCEDURE MulGt (x: INTEGER): BOOLEAN =
  BEGIN RETURN x * 2 > x END MulGt;

PROCEDURE NegLt (x: INTEGER): BOOLEAN =
  BEGIN RETURN -x < 0 END NegLt;

PROCEDURE AbsLt (x: INTEGER): BOOLEAN =
  BEGIN RETURN ABS (x) < 0 END AbsLt;

PROCEDURE Abs (i: INTEGER): INTEGER =
  BEGIN RETURN ABS (i) END Abs;

PROCEDURE Min (a, b: INTEGER): INTEGER =
  BEGIN RETURN MIN (a, b) END Min;

PROCEDURE Max (a, b: Word.T): Word.T =
  BEGIN RETURN MAX (a, b) END Max;

BEGIN
END Ops.
