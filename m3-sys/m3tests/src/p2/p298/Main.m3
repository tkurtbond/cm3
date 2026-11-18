(* This fork: the unsigned fixed-width integer types.  See readme. *)

UNSAFE MODULE Main;
IMPORT IO, Fmt, Word8, Word16, Word32, Word64;

TYPE
  W8 = Word8.T;  W16 = Word16.T;  W32 = Word32.T;  W64 = Word64.T;
  Small = [VAL (3, W8) .. VAL (9, W8)];
  R = RECORD a: W8;  b: W16;  c: W32;  d: W64 END;
  P = RECORD a: BITS 3 FOR [VAL (0, W8) .. VAL (7, W8)];
             b: BITS 8 FOR W8;  c: BITS 16 FOR W16;
             d: BITS 32 FOR W32 END;
  O = OBJECT x: W64 METHODS m (y: W64): W64 := M END;

CONST
  C8a = VAL (200, W8) + VAL (100, W8);
  C8b = VAL (0, W8) - VAL (1, W8);
  C32 = VAL (16_FFFFFFFF, W32) * VAL (3, W32);
  C64 = VAL (0L, W64) - VAL (1L, W64);
  C64n = -VAL (1L, W64);

VAR
  a, b: W8;  c, d: W16;  e, f: W32;  g, h: W64;
  s: Small;  n: INTEGER;  k: CARDINAL;  one8 := VAL (1, W8);
  r: R;  pk: P;  o := NEW (O, x := VAL (5L, W64));
  arr8: ARRAY W8 OF INTEGER;
  arr: ARRAY [VAL (10, W8) .. VAL (12, W8)] OF INTEGER;
  arr64: ARRAY [VAL (10L, W64) .. VAL (12L, W64)] OF INTEGER;
  ra: REF ARRAY OF W8;
  st: SET OF W8;
  s16: SET OF [VAL (0, W16) .. VAL (1000, W16)];

PROCEDURE M (self: O;  y: W64): W64 =
  BEGIN RETURN self.x * y END M;

PROCEDURE Sum (READONLY x: ARRAY OF W8): W8 =
  VAR sum := VAL (0, W8);
  BEGIN
    FOR i := FIRST (x) TO LAST (x) DO sum := sum + x[i] END;
    RETURN sum;
  END Sum;

PROCEDURE Bump (VAR x: W16;  by: INTEGER := 1) =
  BEGIN INC (x, by) END Bump;

PROCEDURE Put (name: TEXT;  x: INTEGER) =
  BEGIN IO.Put (name & " = " & Fmt.Int (x) & "\n") END Put;

PROCEDURE PutL (name: TEXT;  x: W64) =
  BEGIN
    IO.Put (name & " = 16_" & Fmt.LongUnsigned (LOOPHOLE (x, LONGINT), 16)
            & "\n");
  END PutL;

BEGIN
  Put ("C8a", VAL (C8a, INTEGER));
  Put ("C8b", VAL (C8b, INTEGER));
  PutL ("C32", VAL (VAL (C32, LONGINT), W64));
  PutL ("C64", C64);
  PutL ("C64n", C64n);
  PutL ("LAST(W64)", LAST (W64));
  Put ("FIRST(W16)", VAL (FIRST (W16), INTEGER));
  Put ("LAST(W16)", VAL (LAST (W16), INTEGER));
  Put ("NUMBER(W8)", NUMBER (W8));
  Put ("Word32.Size", Word32.Size);

  a := VAL (200, W8);  b := VAL (100, W8);
  Put ("a+b", VAL (a + b, INTEGER));
  Put ("b-a", VAL (b - a, INTEGER));
  Put ("a*b", VAL (a * b, INTEGER));
  Put ("-a", VAL (-a, INTEGER));
  Put ("a DIV b", VAL (a DIV b, INTEGER));
  Put ("a MOD b", VAL (a MOD b, INTEGER));
  Put ("ORD(a)", VAL (ORD (a), INTEGER));
  Put ("MAX(a,b)", VAL (MAX (a, b), INTEGER));
  Put ("MIN(a,b)", VAL (MIN (a, b), INTEGER));
  Put ("a>b", ORD (a > b));
  Put ("a=b", ORD (a = b));

  c := VAL (65535, W16);  d := VAL (2, W16);
  Put ("c+d", VAL (c + d, INTEGER));
  Put ("c*c", VAL (c * c, INTEGER));
  e := VAL (16_80000000, W32);  f := VAL (2, W32);
  Put ("e*f", VAL (e * f, INTEGER));
  Put ("e DIV f", VAL (e DIV f, INTEGER));
  Put ("e>f", ORD (e > f));
  Put ("VAL(e,INTEGER)", VAL (e, INTEGER));

  g := LAST (W64);  h := VAL (2L, W64);
  PutL ("g", g);
  Put ("g>h", ORD (g > h));
  Put ("g<h", ORD (g < h));
  PutL ("g DIV h", g DIV h);
  PutL ("g MOD h", g MOD h);
  PutL ("g DIV 4", g DIV VAL (4L, W64));
  PutL ("g MOD 8", g MOD VAL (8L, W64));
  PutL ("g+h", g + h);
  PutL ("h-g", h - g);
  PutL ("g*g", g * g);
  PutL ("-h", -h);
  Put ("VAL(h,LONGINT)", VAL (VAL (h, LONGINT), INTEGER));

  a := LAST (W8);  INC (a);  Put ("INC LAST", VAL (a, INTEGER));
  DEC (a);  Put ("DEC 0", VAL (a, INTEGER));
  INC (a, 10);  Put ("INC 10", VAL (a, INTEGER));
  DEC (a, 20);  Put ("DEC 20", VAL (a, INTEGER));
  INC (a, -1);  Put ("INC -1", VAL (a, INTEGER));
  INC (a, one8);  Put ("INC one8", VAL (a, INTEGER));
  g := LAST (W64);  INC (g);  PutL ("INC LAST64", g);
  DEC (g, 2);  PutL ("DEC 2", g);

  n := 0;
  FOR i := VAL (250, W8) TO LAST (W8) DO INC (n) END;
  Put ("FOR to LAST", n);
  n := 0;
  FOR i := VAL (5, W8) TO FIRST (W8) BY -1 DO INC (n) END;
  Put ("FOR down to 0", n);
  n := 0;
  FOR i := FIRST (W8) TO LAST (W8) BY 100 DO INC (n, VAL (i, INTEGER)) END;
  Put ("FOR BY 100 sum", n);
  n := 0;  k := 3;
  FOR i := VAL (0, W8) TO LAST (W8) BY k DO INC (n) END;
  Put ("FOR BY var", n);
  n := 0;
  FOR i := LAST (W64) - VAL (3L, W64) TO LAST (W64) DO INC (n) END;
  Put ("FOR to LAST64", n);
  n := 0;
  FOR i := FIRST (W64) TO LAST (W64) BY VAL (16_4000000000000000L, W64) DO
    INC (n)
  END;
  Put ("FOR W64 BY 2^62", n);
  n := 0;
  FOR i := VAL (10, W8) TO VAL (0, W8) BY -n - 3 DO INC (n) END;
  Put ("FOR BY run-time negative", n);

  s := VAL (5, W8);
  INC (s, 4);
  Put ("s", VAL (s, INTEGER));
  Put ("FIRST(Small)", VAL (FIRST (Small), INTEGER));
  Put ("BITSIZE(Small)", BITSIZE (Small));

  r.a := VAL (255, W8);  r.b := VAL (65535, W16);
  r.c := VAL (16_FFFFFFFF, W32);  r.d := LAST (W64);
  INC (r.a);  Bump (r.b);  INC (r.c, 2);  INC (r.d, 3);
  Put ("r.a", VAL (r.a, INTEGER));
  Put ("r.b", VAL (r.b, INTEGER));
  Put ("r.c", VAL (r.c, INTEGER));
  PutL ("r.d", r.d);
  Put ("BYTESIZE(R)", BYTESIZE (R));

  pk.a := VAL (7, W8);  pk.b := VAL (200, W8);
  pk.c := VAL (40000, W16);  pk.d := VAL (16_80000001, W32);
  pk.b := pk.b + pk.b;  pk.c := pk.c * VAL (2, W16);
  pk.d := pk.d * VAL (2, W32);
  Put ("pk.a", VAL (pk.a, INTEGER));
  Put ("pk.b", VAL (pk.b, INTEGER));
  Put ("pk.c", VAL (pk.c, INTEGER));
  Put ("pk.d", VAL (pk.d, INTEGER));
  Put ("BITSIZE(P)", BITSIZE (P));

  PutL ("o.m", o.m (VAL (7L, W64)));

  a := VAL (200, W8);
  arr8[a] := 7;  arr8[LAST (W8)] := 9;
  Put ("arr8[a]", arr8[a]);
  Put ("arr8[255]", arr8[VAL (255, W8)]);
  Put ("NUMBER(arr8)", NUMBER (arr8));
  FOR i := FIRST (arr) TO LAST (arr) DO arr[i] := VAL (i, INTEGER) END;
  Put ("arr[12]", arr[VAL (12, W8)]);
  arr64[VAL (11L, W64)] := 42;
  Put ("arr64[11]", arr64[VAL (11L, W64)]);

  ra := NEW (REF ARRAY OF W8, 300);
  FOR i := 0 TO LAST (ra^) DO ra[i] := VAL (i MOD 256, W8) END;
  Put ("Sum", VAL (Sum (ra^), INTEGER));

  st := SET OF W8 {a, VAL (3, W8), LAST (W8)};
  Put ("a IN st", ORD (a IN st));
  Put ("4 IN st", ORD (VAL (4, W8) IN st));
  Put ("255 IN st", ORD (LAST (W8) IN st));
  s16 := SET OF [VAL (0, W16) .. VAL (1000, W16)] {VAL (999, W16)};
  Put ("999 IN s16", ORD (VAL (999, W16) IN s16));

  CASE a OF
  | VAL (1, W8) => IO.Put ("CASE 1\n");
  | VAL (200, W8) => IO.Put ("CASE 200\n");
  ELSE IO.Put ("CASE ELSE\n");
  END;
END Main.
