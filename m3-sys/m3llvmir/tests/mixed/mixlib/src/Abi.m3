MODULE Abi;

IMPORT Fmt, Text;

PROCEDURE SwapPair (p: Pair): Pair =
  BEGIN RETURN Pair {p.b, p.a} END SwapPair;

PROCEDURE NextTiny (t: Tiny): Tiny =
  BEGIN
    RETURN Tiny {VAL (ORD (t.c1) + 1, CHAR), VAL (ORD (t.c2) + 1, CHAR),
                 VAL (ORD (t.c3) + 1, CHAR)};
  END NextTiny;

PROCEDURE MixedSum (READONLY m: Mixed; x: REAL; y: LONGREAL; z: EXTENDED): LONGREAL =
  BEGIN
    RETURN FLOAT (m.r, LONGREAL) + FLOAT (m.i, LONGREAL) + m.d
           + FLOAT (x, LONGREAL) + y + FLOAT (z, LONGREAL);
  END MixedSum;

PROCEDURE MakeMixed (r: REAL; i: [0..255]; d: LONGREAL): Mixed =
  BEGIN RETURN Mixed {r, i, d} END MakeMixed;

PROCEDURE SumBig (b: Big): INTEGER =
  VAR s := 0;
  BEGIN
    FOR i := FIRST (b) TO LAST (b) DO INC (s, b[i]) END;
    RETURN s;
  END SumBig;

PROCEDURE Reverse (b: Big): Big =
  VAR r: Big;
  BEGIN
    FOR i := FIRST (b) TO LAST (b) DO r[LAST (b) - i] := b[i] END;
    RETURN r;
  END Reverse;

PROCEDURE SumOpen (READONLY a: ARRAY OF INTEGER): INTEGER =
  VAR s := 0;
  BEGIN
    FOR i := FIRST (a) TO LAST (a) DO INC (s, a[i]) END;
    RETURN s;
  END SumOpen;

PROCEDURE Fill (VAR a: ARRAY OF INTEGER; v: INTEGER) =
  BEGIN
    FOR i := FIRST (a) TO LAST (a) DO a[i] := v + i END;
  END Fill;

PROCEDURE Scalars (a: BOOLEAN; c: CHAR; w: WIDECHAR; l: LONGINT;
                   i8: [-128..127]; u16: [0..65535]; r: REAL): LONGINT =
  BEGIN
    RETURN VAL (ORD (a), LONGINT) + VAL (ORD (c), LONGINT) * 10L
           + VAL (ORD (w), LONGINT) * 1000L + l
           + VAL (i8, LONGINT) + VAL (u16, LONGINT) + VAL (ROUND (r), LONGINT);
  END Scalars;

PROCEDURE Many (a, b, c, d, e, f, g, h, i, j: INTEGER;
                x1, x2, x3, x4, x5, x6, x7, x8, x9, x10: LONGREAL): LONGREAL =
  BEGIN
    RETURN FLOAT (a + 2*b + 3*c + 4*d + 5*e + 6*f + 7*g + 8*h + 9*i + 10*j,
                  LONGREAL)
           + x1 + 2.0d0*x2 + 3.0d0*x3 + 4.0d0*x4 + 5.0d0*x5 + 6.0d0*x6
           + 7.0d0*x7 + 8.0d0*x8 + 9.0d0*x9 + 10.0d0*x10;
  END Many;

PROCEDURE NextColor (c: Color): Color =
  BEGIN
    IF c = LAST (Color) THEN RETURN FIRST (Color) END;
    RETURN VAL (ORD (c) + 1, Color);
  END NextColor;

PROCEDURE Complement (s: Colors): Colors =
  BEGIN RETURN Colors {FIRST (Color) .. LAST (Color)} - s END Complement;

PROCEDURE Apply (f: Fn; x: INTEGER): INTEGER RAISES {Fail, Plain} =
  BEGIN RETURN f (x) END Apply;

PROCEDURE Sq (x: INTEGER): INTEGER =
  BEGIN RETURN x * x END Sq;

PROCEDURE Square (): Fn =
  BEGIN RETURN Sq END Square;

PROCEDURE ApplyLocal (n: INTEGER; f: Fn): INTEGER RAISES {Fail, Plain} =
  VAR k := 3;
  PROCEDURE Local (x: INTEGER): INTEGER RAISES {Fail, Plain} =
    BEGIN RETURN f (x * k + n) END Local;
  BEGIN
    RETURN Apply (Local, 2);
  END ApplyLocal;

PROCEDURE Raise (code: INTEGER) RAISES {Fail, Plain} =
  BEGIN
    IF code = 0 THEN RAISE Plain END;
    RAISE Fail (code);
  END Raise;

PROCEDURE Catch (f: Fn; x: INTEGER): TEXT =
  BEGIN
    TRY
      RETURN "returned " & Fmt.Int (f (x));
    EXCEPT
    | Fail (code) => RETURN "Fail(" & Fmt.Int (code) & ")";
    | Plain => RETURN "Plain";
    END;
  END Catch;

PROCEDURE Finally (VAR log: TEXT; code: INTEGER) RAISES {Fail, Plain} =
  BEGIN
    TRY
      log := log & "try ";
      IF code >= 0 THEN Raise (code) END;
      log := log & "body ";
    FINALLY
      log := log & "finally";
    END;
  END Finally;

TYPE
  Sq_ = Shape OBJECT side: LONGREAL OVERRIDES area := SquareArea END;

PROCEDURE SquareArea (s: Sq_): LONGREAL =
  BEGIN RETURN s.side * s.side END SquareArea;

PROCEDURE NewSquare (side: LONGREAL): Shape =
  BEGIN RETURN NEW (Sq_, name := "square", side := side) END NewSquare;

PROCEDURE Area (s: Shape): LONGREAL =
  BEGIN RETURN s.area () END Area;

PROCEDURE Describe (s: Shape): TEXT =
  BEGIN
    RETURN s.name & " of area " & Fmt.LongReal (s.area (), Fmt.Style.Fix, 2);
  END Describe;

PROCEDURE Concat (a, b: TEXT): TEXT =
  BEGIN RETURN a & "+" & b & "=" & Fmt.Int (Text.Length (a & b)) END Concat;

BEGIN
END Abi.
