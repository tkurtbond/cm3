(* This fork: the procedures of the builtin interface Word32. *)

MODULE Main;
IMPORT Word32, IO, Fmt;
CONST K = VAL (16_FFFFFFF0, Word32.T);
TYPE Bin = PROCEDURE (x, y: Word32.T): Word32.T;
     Rot = PROCEDURE (x: Word32.T; n: INTEGER): Word32.T;
VAR a, b: Word32.T;  n: INTEGER;
    bins := ARRAY [0..7] OF Bin { Word32.Plus, Word32.Times, Word32.Minus, Word32.Divide,
                                  Word32.Mod, Word32.And, Word32.Or, Word32.Xor };
    rots := ARRAY [0..1] OF Rot { Word32.Shift, Word32.Rotate };
    lt := Word32.LT;  cmp := Word32.Compare;  ins := Word32.Insert;  wrap := Word32.Wrap;
    tow := Word32.ToWord;  lsh := Word32.LeftShift;
PROCEDURE P (x: Word32.T) = BEGIN IO.Put (Fmt.Unsigned (Word32.ToWord (x)) & "\n") END P;
PROCEDURE B (x: BOOLEAN) = BEGIN IO.Put (Fmt.Bool (x) & "\n") END B;
BEGIN
  a := VAL (K, Word32.T);  b := VAL (16_20, Word32.T);  n := 4;
  P (Word32.Plus (a, b));            (* 10 *)
  P (Word32.Minus (b, a));           (* 30 *)
  P (Word32.Times (a, b));           (* fffffe00 *)
  P (Word32.Divide (a, b));          (* 7ffffff *)
  P (Word32.Mod (a, VAL (7, Word32.T)));
  B (Word32.LT (b, a)); B (Word32.GE (b, a)); B (Word32.Equal (a, a));
  IF Word32.GT (a, b) THEN IO.Put ("gt\n") END;
  P (Word32.Not (a));                (* f *)
  P (Word32.Shift (a, n)); P (Word32.Shift (a, -n));
  P (Word32.LeftShift (a, n)); P (Word32.RightShift (a, n));
  P (Word32.Rotate (a, n)); P (Word32.Rotate (a, -n)); P (Word32.Rotate (a, 36));
  P (Word32.LeftRotate (a, n)); P (Word32.RightRotate (a, n));
  P (Word32.Extract (a, n, 8)); P (Word32.Insert (a, b, n, 8));
  P (Word32.Wrap (-1)); P (Word32.Wrap (16_123456789L)); P (Word32.FromWord (-2));
  P (Word32.FromLong (-3L));
  IO.Put (Fmt.Int (Word32.ToWord (a)) & " " & Fmt.LongInt (Word32.ToLong (a)) & "\n");
  IO.Put (Fmt.Int (Word32.Compare (a, b)) & Fmt.Int (Word32.Compare (b, a)) & Fmt.Int (Word32.Compare (a, a)) & "\n");
  IO.Put (Word32.Brand & " " & Fmt.Int (Word32.Hash (a)) & "\n");
  (* constant folds *)
  P (Word32.Plus (K, VAL (16_20, Word32.T))); P (Word32.Rotate (K, 4));
  P (Word32.RightRotate (K, 4)); P (Word32.Not (K));
  P (Word32.Wrap (-1)); P (Word32.Extract (K, 4, 8));
  IO.Put ("-- procedure values\n");
  FOR i := FIRST (bins) TO LAST (bins) DO P (bins[i] (a, b)) END;
  P (rots[0] (a, n)); P (rots[0] (a, -n)); P (rots[1] (a, n)); P (rots[1] (a, -n)); P (rots[1] (a, 36));
  B (lt (b, a)); IO.Put (Fmt.Int (cmp (b, a)) & "\n");
  P (ins (a, b, n, 8)); P (wrap (-5L)); IO.Put (Fmt.Int (tow (a)) & "\n");
  P (lsh (a, 31));
END Main.
