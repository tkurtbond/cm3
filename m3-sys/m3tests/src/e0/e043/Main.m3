(* This fork: the signed fixed-width integer types are distinct from
   each other, from the unsigned ones, and from INTEGER and LONGINT;
   mixing them needs VAL.  ABS takes a SignedN but not a WordN. *)

MODULE Main;
IMPORT Signed8, Signed16, Signed64, Word8, Word64;

VAR
  a: Signed8.T;  c: Signed16.T;  g: Signed64.T;
  w: Word8.T;  x: Word64.T;  n: INTEGER;  l: LONGINT;

BEGIN
  a := n;
  n := a;
  a := c;
  a := w;
  w := a;
  g := l;
  g := x;
  a := 3;
  a := -1;
  a := a + c;
  a := a + w;
  a := a - 1;
  n := n * a;
  g := g * l;
  a := a DIV n;
  a := a MOD c;
  a := a / a;
  w := ABS (w);
  x := ABS (x);
  a := MIN (a, c);
  a := MAX (a, w);
  IF a < c THEN END;
  IF a = w THEN END;
  IF g > l THEN END;
  INC (a, c);
  INC (a, w);
  INC (a, l);
  INC (n, a);
  FOR i := a TO c DO END;
  FOR i := a TO w DO END;
  FOR i := a TO VAL (3, Signed8.T) BY c DO END;
END Main.
