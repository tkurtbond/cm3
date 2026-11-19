(* This fork: DIV and MOD by -1 of FIRST (INTEGER) and FIRST (LONGINT)
   (LLVM-IR-backend-docs/BUGS.md, bug 26), and DIV and MOD over every
   combination of signs. *)

MODULE Main;
IMPORT IO, Fmt;

TYPE Neg = [FIRST (INTEGER) .. -1];   (* operands of known sign *)

VAR
  xs := ARRAY [0..6] OF INTEGER
          {FIRST (INTEGER), FIRST (INTEGER) + 1, -7, -1, 0, 7, LAST (INTEGER)};
  ys := ARRAY [0..5] OF INTEGER {-7, -2, -1, 1, 2, 7};
  ls := ARRAY [0..2] OF LONGINT {FIRST (LONGINT), -7L, LAST (LONGINT)};
  lys := ARRAY [0..2] OF LONGINT {-2L, -1L, 3L};
  n: Neg := FIRST (INTEGER);
  m1: Neg := -1;

BEGIN
  FOR i := FIRST (xs) TO LAST (xs) DO
    FOR j := FIRST (ys) TO LAST (ys) DO
      IO.Put (Fmt.Int (xs[i]) & " DIV " & Fmt.Int (ys[j]) & " = "
              & Fmt.Int (xs[i] DIV ys[j]) & ", MOD = "
              & Fmt.Int (xs[i] MOD ys[j]) & "\n");
    END;
  END;
  FOR i := FIRST (ls) TO LAST (ls) DO
    FOR j := FIRST (lys) TO LAST (lys) DO
      IO.Put (Fmt.LongInt (ls[i]) & "L DIV " & Fmt.LongInt (lys[j])
              & "L = " & Fmt.LongInt (ls[i] DIV lys[j]) & ", MOD = "
              & Fmt.LongInt (ls[i] MOD lys[j]) & "\n");
    END;
  END;
  (* A constant divisor, and two operands the compiler knows are
     negative. *)
  IO.Put ("x DIV -1 = " & Fmt.Int (xs[0] DIV -1) & ", MOD = "
          & Fmt.Int (xs[0] MOD -1) & "\n");
  IO.Put ("Neg DIV Neg = " & Fmt.Int (n DIV m1) & ", MOD = "
          & Fmt.Int (n MOD m1) & "\n");
END Main.
