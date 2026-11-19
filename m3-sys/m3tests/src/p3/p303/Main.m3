(* This fork: the signed fixed-width integer types.  See readme. *)

MODULE Main;
IMPORT IO, Fmt, Signed8, Signed16, Signed32, Signed64;

TYPE
  S8 = Signed8.T;  S16 = Signed16.T;  S32 = Signed32.T;  S64 = Signed64.T;
  Small = [VAL (-3, S8) .. VAL (3, S8)];
  R = RECORD a: S8;  b: S16;  c: S32;  d: S64 END;
  P = RECORD a: BITS 4 FOR [VAL (-8, S8) .. VAL (7, S8)];
             b: BITS 8 FOR S8;  c: BITS 16 FOR S16;
             d: BITS 32 FOR S32 END;
  SS = SET OF [VAL (-5, S16) .. VAL (5, S16)];

CONST
  C8a = VAL (100, S8) + VAL (27, S8);
  C8b = -VAL (127, S8) - VAL (1, S8);
  C8d = VAL (-7, S8) DIV VAL (2, S8);
  C8m = VAL (-7, S8) MOD VAL (2, S8);
  C16 = VAL (-181, S16) * VAL (181, S16);
  C32 = ABS (VAL (-16_7FFFFFFF, S32));
  C64a = FIRST (S64) + LAST (S64);
  C64m = FIRST (S64) MOD VAL (-1L, S64);
  C64d = LAST (S64) DIV VAL (-1L, S64);
  C64x = VAL (-2L, S64) * VAL (16_4000000000000000L, S64);

VAR
  a, b: S8;  c, d: S16;  e, f: S32;  g, h: S64;
  s: Small;  n: INTEGER;
  r: R;  pk: P;
  arr: ARRAY Small OF INTEGER;
  arr64: ARRAY [VAL (-2L, S64) .. VAL (2L, S64)] OF INTEGER;
  st: SS;

PROCEDURE Put (name: TEXT;  x: INTEGER) =
  BEGIN IO.Put (name & " = " & Fmt.Int (x) & "\n") END Put;

PROCEDURE PutL (name: TEXT;  x: S64) =
  BEGIN IO.Put (name & " = " & Fmt.LongInt (VAL (x, LONGINT)) & "\n") END PutL;

PROCEDURE Bump (VAR x: S16;  by: INTEGER := 1) =
  BEGIN INC (x, by) END Bump;

PROCEDURE DivMod8 (x, y: INTEGER) =
  VAR a := VAL (x, S8);  b := VAL (y, S8);
  BEGIN
    Put (Fmt.Int (x) & " DIV/MOD " & Fmt.Int (y) & " (8)",
         VAL (a DIV b, INTEGER) * 1000 + VAL (a MOD b, INTEGER));
  END DivMod8;

PROCEDURE DivMod64 (x, y: LONGINT) =
  VAR a := VAL (x, S64);  b := VAL (y, S64);
  BEGIN
    PutL (Fmt.LongInt (x) & " DIV " & Fmt.LongInt (y) & " (64)", a DIV b);
    PutL (Fmt.LongInt (x) & " MOD " & Fmt.LongInt (y) & " (64)", a MOD b);
  END DivMod64;

BEGIN
  (* constants *)
  Put ("C8a", VAL (C8a, INTEGER));
  Put ("C8b", VAL (C8b, INTEGER));
  Put ("C8d", VAL (C8d, INTEGER));
  Put ("C8m", VAL (C8m, INTEGER));
  Put ("C16", VAL (C16, INTEGER));
  Put ("C32", VAL (C32, INTEGER));
  PutL ("C64a", C64a);
  PutL ("C64m", C64m);
  PutL ("C64d", C64d);
  PutL ("C64x", C64x);
  Put ("FIRST(S8)", VAL (FIRST (S8), INTEGER));
  Put ("LAST(S8)", VAL (LAST (S8), INTEGER));
  Put ("FIRST(S16)", VAL (FIRST (S16), INTEGER));
  Put ("LAST(S16)", VAL (LAST (S16), INTEGER));
  Put ("FIRST(S32)", VAL (FIRST (S32), INTEGER));
  Put ("LAST(S32)", VAL (LAST (S32), INTEGER));
  PutL ("FIRST(S64)", FIRST (S64));
  PutL ("LAST(S64)", LAST (S64));
  Put ("NUMBER(S8)", NUMBER (S8));
  Put ("NUMBER(Small)", NUMBER (Small));
  Put ("Signed32.Size", Signed32.Size);
  Put ("BITSIZE(S16)", BITSIZE (S16));

  (* 8 bits, at the edges *)
  a := VAL (100, S8);  b := VAL (27, S8);
  Put ("a+b", VAL (a + b, INTEGER));
  Put ("-a-b-1", VAL (-a - b - VAL (1, S8), INTEGER));
  a := VAL (-128, S8);  b := VAL (-1, S8);
  Put ("FIRST MOD -1", VAL (a MOD b, INTEGER));
  Put ("FIRST DIV 1", VAL (a DIV -b, INTEGER));
  Put ("-(FIRST+1)", VAL (-(a + VAL (1, S8)), INTEGER));
  Put ("ABS(FIRST+1)", VAL (ABS (a - b), INTEGER));
  a := VAL (-16, S8);  b := VAL (8, S8);
  Put ("-16*8", VAL (a * b, INTEGER));
  a := VAL (-11, S8);  b := VAL (-11, S8);
  Put ("-11*-11", VAL (a * b, INTEGER));
  Put ("a<b", ORD (VAL (-1, S8) < VAL (1, S8)));
  Put ("MIN", VAL (MIN (VAL (-5, S8), VAL (3, S8)), INTEGER));
  Put ("MAX", VAL (MAX (VAL (-5, S8), VAL (3, S8)), INTEGER));
  FOR x := -7 TO 7 BY 14 DO
    FOR y := -2 TO 2 BY 4 DO DivMod8 (x, y) END;
  END;
  DivMod8 (-128, 1);
  DivMod8 (-128, 127);
  DivMod8 (127, -128);

  (* 16 and 32 bits *)
  c := VAL (-32768, S16);  d := VAL (32767, S16);
  Put ("c+d", VAL (c + d, INTEGER));
  Put ("d-1+1", VAL (d - VAL (1, S16) + VAL (1, S16), INTEGER));
  Put ("c DIV d", VAL (c DIV d, INTEGER));
  Put ("c MOD d", VAL (c MOD d, INTEGER));
  e := VAL (-16_80000000, S32);  f := VAL (16_7FFFFFFF, S32);
  Put ("e+f", VAL (e + f, INTEGER));
  Put ("-f", VAL (-f, INTEGER));
  Put ("ABS(-f)", VAL (ABS (-f), INTEGER));
  Put ("e MOD -1", VAL (e MOD VAL (-1, S32), INTEGER));
  f := VAL (46340, S32);
  Put ("46340^2", VAL (f * f, INTEGER));
  Put ("-46340*46340", VAL (-f * f, INTEGER));

  (* 64 bits: full width *)
  g := FIRST (S64);  h := LAST (S64);
  PutL ("g+h", g + h);
  PutL ("h-1+1", h - VAL (1L, S64) + VAL (1L, S64));
  PutL ("g+1-1", g + VAL (1L, S64) - VAL (1L, S64));
  PutL ("-h", -h);
  PutL ("-h-1", -h - VAL (1L, S64));
  PutL ("ABS(-h)", ABS (-h));
  PutL ("g-g", g - g);
  PutL ("h-h", h - h);
  PutL ("0-h", VAL (0L, S64) - h);
  PutL ("-1-h", VAL (-1L, S64) - h);
  PutL ("g MOD -1", g MOD VAL (-1L, S64));
  PutL ("g DIV 1", g DIV VAL (1L, S64));
  PutL ("h DIV -1", h DIV VAL (-1L, S64));
  PutL ("g*1", g * VAL (1L, S64));
  PutL ("1*g", VAL (1L, S64) * g);
  PutL ("0*g", VAL (0L, S64) * g);
  PutL ("g*0", g * VAL (0L, S64));
  PutL ("-1*h", VAL (-1L, S64) * h);
  PutL ("h*-1", h * VAL (-1L, S64));
  g := VAL (-2L, S64);  h := VAL (16_4000000000000000L, S64);
  PutL ("-2*2^62", g * h);
  PutL ("2^62*-2", h * g);
  g := VAL (3037000499L, S64);
  PutL ("3037000499^2", g * g);
  PutL ("-3037000499*3037000499", -g * g);
  g := VAL (-4294967296L, S64);  h := VAL (2147483648L, S64);
  PutL ("-2^32*2^31", g * h);
  DivMod64 (7L, 2L);
  DivMod64 (-7L, 2L);
  DivMod64 (7L, -2L);
  DivMod64 (-7L, -2L);
  DivMod64 (FIRST (LONGINT), 1L);
  DivMod64 (FIRST (LONGINT), LAST (LONGINT));
  DivMod64 (LAST (LONGINT), FIRST (LONGINT));
  DivMod64 (FIRST (LONGINT), 2L);

  (* INC and DEC *)
  a := VAL (120, S8);
  INC (a, 7);  Put ("INC(a,7)", VAL (a, INTEGER));
  DEC (a, 255);  Put ("DEC(a,255)", VAL (a, INTEGER));
  INC (a, VAL (127, S8));  Put ("INC(a,127)", VAL (a, INTEGER));
  DEC (a);  Put ("DEC(a)", VAL (a, INTEGER));
  c := VAL (32760, S16);
  Bump (c, 7);  Put ("Bump(c,7)", VAL (c, INTEGER));
  Bump (c, -65535);  Put ("Bump(c,-65535)", VAL (c, INTEGER));
  g := VAL (-2L, S64);
  INC (g, LAST (INTEGER));  PutL ("INC(g,LAST)", g);
  INC (g);  PutL ("INC(g)", g);
  DEC (g, LAST (INTEGER));  PutL ("DEC(g,LAST)", g);
  DEC (g, LAST (INTEGER));  PutL ("DEC(g,LAST)", g);
  h := VAL (-1L, S64);
  DEC (g, h);  PutL ("DEC(g,-1)", g);
  g := FIRST (S64);
  INC (g, VAL (1L, S64));  INC (g, h);  PutL ("INC(FIRST,1-1)", g);

  (* FOR loops *)
  n := 0;
  FOR i := LAST (S8) - VAL (3, S8) TO LAST (S8) DO
    n := n * 1000 + VAL (i, INTEGER);
  END;
  Put ("FOR to LAST(S8)", n);
  n := 0;
  FOR i := FIRST (S8) + VAL (2, S8) TO FIRST (S8) BY -1 DO
    n := n * 1000 - VAL (i, INTEGER);
  END;
  Put ("FOR down to FIRST(S8)", n);
  n := 0;
  FOR i := FIRST (S8) TO LAST (S8) BY 85 DO
    n := n * 1000 + VAL (i, INTEGER) + 500;
  END;
  Put ("FOR S8 BY 85", n);
  n := 0;
  FOR i := LAST (S8) TO FIRST (S8) BY VAL (-127, S8) DO
    n := n * 1000 + VAL (i, INTEGER) + 500;
  END;
  Put ("FOR S8 BY -127", n);
  n := 0;
  FOR i := FIRST (S64) TO LAST (S64) BY LAST (INTEGER) DO INC (n) END;
  Put ("FOR S64 BY LAST", n);
  n := 0;
  FOR i := LAST (S64) TO FIRST (S64) BY FIRST (INTEGER) DO INC (n) END;
  Put ("FOR S64 BY FIRST", n);
  n := 0;
  h := VAL (-1L, S64);
  FOR i := FIRST (S64) + VAL (2L, S64) TO FIRST (S64) BY h DO INC (n) END;
  Put ("FOR down to FIRST(S64)", n);
  n := 0;
  FOR i := LAST (S64) - VAL (2L, S64) TO LAST (S64) DO INC (n) END;
  Put ("FOR to LAST(S64)", n);
  n := 0;
  e := VAL (1, S32);  f := VAL (0, S32);
  FOR i := e TO f DO INC (n) END;
  Put ("FOR empty", n);

  (* subranges, arrays, sets, CASE, records *)
  FOR i := FIRST (Small) TO LAST (Small) DO arr[i] := VAL (i, INTEGER) * 10 END;
  s := VAL (-3, S8);
  Put ("arr[-3]", arr[s]);
  s := LAST (Small);
  Put ("arr[3]", arr[s]);
  Put ("FIRST(arr)", VAL (FIRST (arr), INTEGER));
  arr64[VAL (-2L, S64)] := 7;  arr64[VAL (2L, S64)] := 9;
  Put ("arr64", arr64[FIRST (arr64)] * 10 + arr64[LAST (arr64)]);
  st := SS {VAL (-5, S16), VAL (0, S16)};
  st := st + SS {VAL (5, S16)};
  n := 0;
  FOR i := VAL (-5, S16) TO VAL (5, S16) DO
    IF i IN st THEN n := n * 100 + VAL (i, INTEGER) + 50 END;
  END;
  Put ("set", n);
  FOR i := VAL (-2, S8) TO VAL (2, S8) DO
    CASE i OF
    | VAL (-2, S8) .. VAL (-1, S8) => IO.Put ("neg ");
    | VAL (0, S8) => IO.Put ("zero ");
    ELSE IO.Put ("pos ");
    END;
  END;
  IO.Put ("\n");
  r.a := VAL (-128, S8);  r.b := VAL (-2, S16);  r.c := VAL (-3, S32);
  r.d := VAL (-4L, S64);
  Put ("r", VAL (r.a, INTEGER) + VAL (r.b, INTEGER) + VAL (r.c, INTEGER)
              + VAL (VAL (r.d, LONGINT), INTEGER));
  pk.a := VAL (-8, S8);  pk.b := VAL (-1, S8);  pk.c := VAL (-300, S16);
  pk.d := VAL (-70000, S32);
  Put ("pk.a", VAL (pk.a, INTEGER));
  Put ("pk.b", VAL (pk.b, INTEGER));
  Put ("pk.c", VAL (pk.c, INTEGER));
  Put ("pk.d", VAL (pk.d, INTEGER));
  pk.a := pk.a + VAL (15, S8);
  Put ("pk.a+15", VAL (pk.a, INTEGER));

  (* VAL *)
  a := VAL (-1, S8);
  Put ("VAL(-1 S8, S32)", VAL (VAL (a, S32), INTEGER));
  PutL ("VAL(-1 S8, S64)", VAL (a, S64));
  Put ("ORD(-1 S8)", VAL (ORD (a), INTEGER));
  PutL ("VAL(FIRST(LONGINT))", VAL (FIRST (LONGINT), S64));
  Put ("VAL(FIRST(S64), INTEGER)", VAL (FIRST (S64), INTEGER));
END Main.
