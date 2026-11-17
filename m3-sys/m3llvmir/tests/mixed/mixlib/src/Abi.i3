(* Every kind of value, passed and returned across the library
   boundary, so that a caller built with one back end and a callee built
   with the other must agree on the calling convention. *)

INTERFACE Abi;

TYPE
  Pair  = RECORD a, b: INTEGER END;
  Tiny  = RECORD c1, c2, c3: CHAR END;
  Mixed = RECORD r: REAL; i: [0..255]; d: LONGREAL END;
  Big   = ARRAY [0..9] OF INTEGER;
  Color = {Red, Green, Blue};
  Colors = SET OF Color;
  Fn    = PROCEDURE (x: INTEGER): INTEGER RAISES {Fail, Plain};

  Shape = OBJECT
    name: TEXT;
  METHODS
    area (): LONGREAL;
    describe (): TEXT := Describe;
  END;

EXCEPTION Fail (INTEGER);
EXCEPTION Plain;

PROCEDURE SwapPair (p: Pair): Pair;
PROCEDURE NextTiny (t: Tiny): Tiny;
PROCEDURE MixedSum (READONLY m: Mixed; x: REAL; y: LONGREAL; z: EXTENDED): LONGREAL;
PROCEDURE MakeMixed (r: REAL; i: [0..255]; d: LONGREAL): Mixed;
PROCEDURE SumBig (b: Big): INTEGER;
PROCEDURE Reverse (b: Big): Big;
PROCEDURE SumOpen (READONLY a: ARRAY OF INTEGER): INTEGER;
PROCEDURE Fill (VAR a: ARRAY OF INTEGER; v: INTEGER);
PROCEDURE Scalars (a: BOOLEAN; c: CHAR; w: WIDECHAR; l: LONGINT;
                   i8: [-128..127]; u16: [0..65535]; r: REAL): LONGINT;
PROCEDURE Many (a, b, c, d, e, f, g, h, i, j: INTEGER;
                x1, x2, x3, x4, x5, x6, x7, x8, x9, x10: LONGREAL): LONGREAL;
PROCEDURE NextColor (c: Color): Color;
PROCEDURE Complement (s: Colors): Colors;

PROCEDURE Apply (f: Fn; x: INTEGER): INTEGER RAISES {Fail, Plain};
PROCEDURE Square (): Fn;
PROCEDURE ApplyLocal (n: INTEGER; f: Fn): INTEGER RAISES {Fail, Plain};
(* Calls f with a nested procedure's result. *)

PROCEDURE Raise (code: INTEGER) RAISES {Fail, Plain};
PROCEDURE Catch (f: Fn; x: INTEGER): TEXT;
(* Calls f(x) and reports what it raised. *)
PROCEDURE Finally (VAR log: TEXT; code: INTEGER) RAISES {Fail, Plain};

PROCEDURE NewSquare (side: LONGREAL): Shape;
PROCEDURE Area (s: Shape): LONGREAL;
PROCEDURE Describe (s: Shape): TEXT;
PROCEDURE Concat (a, b: TEXT): TEXT;

END Abi.
