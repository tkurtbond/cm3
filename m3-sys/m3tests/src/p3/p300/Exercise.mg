(* This fork: every procedure of the interface W (one of Word8 ..
   Word64), called inline, folded into constants, and called through
   procedure values.  The three sections must print the same lines. *)

GENERIC MODULE Exercise (W);

IMPORT IO, Fmt;

TYPE
  Bin = PROCEDURE (x, y: W.T): W.T;
  Cmp = PROCEDURE (x, y: W.T): BOOLEAN;
  Un  = PROCEDURE (x: W.T): W.T;
  Sh  = PROCEDURE (x: W.T;  n: INTEGER): W.T;
  ShC = PROCEDURE (x: W.T;  n: [0 .. W.Size - 1]): W.T;
  Ext = PROCEDURE (x: W.T;  i, n: CARDINAL): W.T;
  Ins = PROCEDURE (x, y: W.T;  i, n: CARDINAL): W.T;
  FromL = PROCEDURE (x: LONGINT): W.T;
  FromI = PROCEDURE (x: INTEGER): W.T;
  ToI = PROCEDURE (x: W.T): INTEGER;
  ToL = PROCEDURE (x: W.T): LONGINT;
  Cmp3 = PROCEDURE (x, y: W.T): [-1 .. 1];

CONST
  KA = W.Wrap (-16);  KB = W.Wrap (16_20);  K7 = W.Wrap (7);

  WordNames = ARRAY OF TEXT {
    "plus", "minus", "times", "divide", "mod", "and", "or", "xor", "not",
    "shift", "shift-", "leftshift", "rightshift", "rotate", "rotate-",
    "rotate+size", "leftrotate", "rightrotate", "extract", "insert",
    "wrap", "fromword", "fromlong" };
  BoolNames = ARRAY OF TEXT { "lt", "le", "gt", "ge", "equal" };
  IntNames = ARRAY OF TEXT { "toword", "hash", "compare", "compare-",
                             "compare=" };

  FoldWords = ARRAY OF W.T {
    W.Plus (KA, KB), W.Minus (KB, KA), W.Times (KA, KB),
    W.Divide (KA, KB), W.Mod (KA, K7), W.And (KA, KB), W.Or (KA, KB),
    W.Xor (KA, KB), W.Not (KA),
    W.Shift (KA, 4), W.Shift (KA, -4), W.LeftShift (KA, 4),
    W.RightShift (KA, 4), W.Rotate (KA, 4), W.Rotate (KA, -4),
    W.Rotate (KA, W.Size + 4), W.LeftRotate (KA, 4),
    W.RightRotate (KA, 4), W.Extract (KA, 2, 4),
    W.Insert (KA, K7, 2, 4),
    W.Wrap (-1), W.FromWord (-2), W.FromLong (-3L) };
  FoldBools = ARRAY OF BOOLEAN {
    W.LT (KB, KA), W.LE (KA, KA), W.GT (KB, KA), W.GE (KB, KA),
    W.Equal (KA, KB) };
  FoldInts = ARRAY OF INTEGER {
    W.ToWord (KA), W.Hash (KA), W.Compare (KA, KB), W.Compare (KB, KA),
    W.Compare (KA, KA) };
  FoldLong = W.ToLong (KA);

PROCEDURE Print (title: TEXT;
                 READONLY words: ARRAY OF W.T;
                 READONLY bools: ARRAY OF BOOLEAN;
                 READONLY ints: ARRAY OF INTEGER;
                 long: LONGINT) =
  BEGIN
    IO.Put ("-- " & W.Brand & " " & title & "\n");
    FOR i := FIRST (words) TO LAST (words) DO
      IO.Put (WordNames[i] & " " & Fmt.LongUnsigned (W.ToLong (words[i]))
              & "\n");
    END;
    FOR i := FIRST (bools) TO LAST (bools) DO
      IO.Put (BoolNames[i] & " " & Fmt.Bool (bools[i]) & "\n");
    END;
    FOR i := FIRST (ints) TO LAST (ints) DO
      IO.Put (IntNames[i] & " " & Fmt.Int (ints[i]) & "\n");
    END;
    IO.Put ("tolong " & Fmt.LongInt (long) & "\n");
  END Print;

PROCEDURE Inline () =
  VAR a := KA;  b := KB;  seven := K7;  n := 4;  m := W.Size + 4;
      i := 2;  w := 4;
  BEGIN
    Print ("inline",
      ARRAY OF W.T {
        W.Plus (a, b), W.Minus (b, a), W.Times (a, b), W.Divide (a, b),
        W.Mod (a, seven), W.And (a, b), W.Or (a, b), W.Xor (a, b),
        W.Not (a),
        W.Shift (a, n), W.Shift (a, -n), W.LeftShift (a, n),
        W.RightShift (a, n), W.Rotate (a, n), W.Rotate (a, -n),
        W.Rotate (a, m), W.LeftRotate (a, n), W.RightRotate (a, n),
        W.Extract (a, i, w), W.Insert (a, seven, i, w),
        W.Wrap (-n DIV 4), W.FromWord (-n DIV 2), W.FromLong (-3L) },
      ARRAY OF BOOLEAN {
        W.LT (b, a), W.LE (a, a), W.GT (b, a), W.GE (b, a),
        W.Equal (a, b) },
      ARRAY OF INTEGER {
        W.ToWord (a), W.Hash (a), W.Compare (a, b), W.Compare (b, a),
        W.Compare (a, a) },
      W.ToLong (a));
  END Inline;

PROCEDURE Values () =
  VAR a := KA;  b := KB;  seven := K7;  n := 4;  m := W.Size + 4;
      plus: Bin := W.Plus;  minus: Bin := W.Minus;  times: Bin := W.Times;
      divide: Bin := W.Divide;  mod: Bin := W.Mod;  and: Bin := W.And;
      or: Bin := W.Or;  xor: Bin := W.Xor;  not: Un := W.Not;
      shift: Sh := W.Shift;  lsh: ShC := W.LeftShift;
      rsh: ShC := W.RightShift;  rot: Sh := W.Rotate;
      lrot: ShC := W.LeftRotate;  rrot: ShC := W.RightRotate;
      extract: Ext := W.Extract;  insert: Ins := W.Insert;
      wrap: FromL := W.Wrap;  fromword: FromI := W.FromWord;
      fromlong: FromL := W.FromLong;
      lt: Cmp := W.LT;  le: Cmp := W.LE;  gt: Cmp := W.GT;  ge: Cmp := W.GE;
      equal: Cmp := W.Equal;
      toword: ToI := W.ToWord;  hash: ToI := W.Hash;  tolong: ToL := W.ToLong;
      compare: Cmp3 := W.Compare;
  BEGIN
    Print ("procedure values",
      ARRAY OF W.T {
        plus (a, b), minus (b, a), times (a, b), divide (a, b),
        mod (a, seven), and (a, b), or (a, b), xor (a, b), not (a),
        shift (a, n), shift (a, -n), lsh (a, n), rsh (a, n), rot (a, n),
        rot (a, -n), rot (a, m), lrot (a, n), rrot (a, n),
        extract (a, 2, 4), insert (a, seven, 2, 4),
        wrap (-1L), fromword (-2), fromlong (-3L) },
      ARRAY OF BOOLEAN {
        lt (b, a), le (a, a), gt (b, a), ge (b, a), equal (a, b) },
      ARRAY OF INTEGER {
        toword (a), hash (a), compare (a, b), compare (b, a),
        compare (a, a) },
      tolong (a));
  END Values;

PROCEDURE Run () =
  BEGIN
    IO.Put ("== " & W.Brand & ", Size " & Fmt.Int (W.Size) & "\n");
    Inline ();
    Print ("folded", FoldWords, FoldBools, FoldInts, FoldLong);
    Values ();
  END Run;

BEGIN
END Exercise.
