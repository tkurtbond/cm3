(* This fork: the fixed-width integer types are distinct from each
   other and from INTEGER and LONGINT; mixing them needs VAL. *)

MODULE Main;
IMPORT Word8, Word16, Word64;

VAR a: Word8.T;  c: Word16.T;  g: Word64.T;  n: INTEGER;  l: LONGINT;

BEGIN
  a := n;
  n := a;
  a := c;
  g := l;
  a := 3;
  n := ORD (a);
  a := a + c;
  a := a + 1;
  n := n + a;
  a := a * c;
  a := a DIV n;
  a := a MOD c;
  a := a / a;
  a := ABS (a);
  a := MIN (a, c);
  IF a < c THEN END;
  IF a = n THEN END;
  INC (a, c);
  INC (a, l);
  INC (n, a);
  FOR i := a TO c DO END;
END Main.
