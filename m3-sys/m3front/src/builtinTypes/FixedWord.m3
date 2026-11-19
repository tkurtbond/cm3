(* See the file COPYRIGHT for a full description. *)

(* This fork: the procedures of Word8 .. Word64, and the few of
   Signed8 .. Signed64.  See FixedWord.i3.

   One set of methods serves all four widths: each finds the width
   from the signature of the procedure being called (the fixed type
   is its result, or else its first formal's type).

   Let N be the width and S the stack type (FixedType.StackType).
   A value of the fixed type is held in S, zero-extended.  So
   And, Or, Xor, Divide, Mod, the comparisons, right shifts and
   Extract need no correction; Plus, Times, Minus, Not, Shift,
   LeftShift and the conversions to the type are masked to N bits;
   Rotate, when N is less than the size of S, is done with shifts. *)

MODULE FixedWord;

IMPORT CG, CallExpr, Expr, ExprRep, Procedure, Target, TInt, TWord, Type, Value;
IMPORT ProcType, IntegerExpr, Formal, Int, LInt, Card, Bool, SubrangeType;
IMPORT Constant, TextExpr, M3String, Error, CheckExpr, Host, FixedType;

(*------------------------------------------------------------- helpers ---*)

PROCEDURE GetInfo (ce: CallExpr.T;  VAR info: FixedType.Info) =
  VAR sig := Expr.TypeOf (ce.proc);  f: Formal.Info;  b: BOOLEAN;
  BEGIN
    IF NOT FixedType.Split (ProcType.Result (sig), info) THEN
      Formal.Split (ProcType.Formals (sig), f);
      b := FixedType.Split (f.type, info);  <*ASSERT b*>
    END;
  END GetInfo;

PROCEDURE Stk (READONLY info: FixedType.Info): CG.Type =
  BEGIN
    RETURN FixedType.StackType (info);
  END Stk;

PROCEDURE ConstInt (e: Expr.T;  VAR x: Target.Int): BOOLEAN =
  VAR t: Type.T;
  BEGIN
    e := Expr.ConstValue (e);
    RETURN (e # NIL) AND IntegerExpr.Split (e, x, t);
  END ConstInt;

PROCEDURE ConstIndex (e: Expr.T;  VAR i: INTEGER): BOOLEAN =
  BEGIN
    e := Expr.ConstValue (e);
    RETURN (e # NIL) AND IntegerExpr.ToInt (e, i);
  END ConstIndex;

PROCEDURE Result (READONLY info: FixedType.Info;
                  READONLY x: Target.Int): Expr.T =
  VAR r: Target.Int;
  BEGIN
    FixedType.Wrap (info, x, r);
    RETURN IntegerExpr.New (info.type, r);
  END Result;

PROCEDURE Max (n: INTEGER): Target.Int =
  VAR r: Target.Int;  b := TInt.FromInt (n, r);
  BEGIN
    <*ASSERT b*>
    RETURN r;
  END Max;

(*--------------------------------------------------------- type checks ---*)

PROCEDURE Check (ce: CallExpr.T;  VAR cs: Expr.CheckState) =
  VAR sig := Expr.TypeOf (ce.proc);
  BEGIN
    EVAL Formal.CheckArgs (cs, ce.args, ProcType.Formals (sig), ce.proc);
    ce.type := ProcType.Result (sig);
  END Check;

PROCEDURE CheckWrap (ce: CallExpr.T;  VAR cs: Expr.CheckState) =
  (* Wrap's formal is a LONGINT, for when it's used as a procedure
     value, but a call takes any integer type. *)
  VAR t: Type.T;
  BEGIN
    Expr.TypeCheck (ce.args[0], cs);
    t := Type.Base (Expr.TypeOf (ce.args[0]));
    IF (t # Int.T) AND (t # LInt.T) AND NOT FixedType.Is (t) THEN
      Error.Msg ("Wrap: argument must be of an integer type");
    END;
    ce.type := ProcType.Result (Expr.TypeOf (ce.proc));
  END CheckWrap;

(*----------------------------------------------- binary and unary ops ---*)

TYPE BinOp = {Plus, Times, Minus, Divide, Mod, And, Or, Xor};
TYPE CmpOp = {LT, LE, GT, GE, EQ};

CONST CmpMap = ARRAY CmpOp OF CG.Cmp
  { CG.Cmp.LT, CG.Cmp.LE, CG.Cmp.GT, CG.Cmp.GE, CG.Cmp.EQ };

PROCEDURE CompileBinary (ce: CallExpr.T;  op: BinOp) =
  VAR info: FixedType.Info;  stk: CG.Type;
  BEGIN
    GetInfo (ce, info);
    stk := Stk (info);
    Expr.Compile (ce.args[0]);
    Expr.Compile (ce.args[1]);
    CASE op OF
    | BinOp.Plus   => CG.Add (stk);       FixedType.Mask (info);
    | BinOp.Times  => CG.Multiply (stk);  FixedType.Mask (info);
    | BinOp.Minus  => CG.Subtract (stk);  FixedType.Mask (info);
    | BinOp.Divide => CG.Div (stk, CG.Sign.Positive, CG.Sign.Positive);
    | BinOp.Mod    => CG.Mod (stk, CG.Sign.Positive, CG.Sign.Positive);
    | BinOp.And    => CG.And (stk);
    | BinOp.Or     => CG.Or (stk);
    | BinOp.Xor    => CG.Xor (stk);
    END;
  END CompileBinary;

PROCEDURE FoldBinary (ce: CallExpr.T;  op: BinOp): Expr.T =
  VAR info: FixedType.Info;  x, y, r: Target.Int;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) OR NOT ConstInt (ce.args[1], y) THEN
      RETURN NIL;
    END;
    GetInfo (ce, info);
    CASE op OF
    | BinOp.Plus   => TWord.Add (x, y, r);
    | BinOp.Times  => TWord.Multiply (x, y, r);
    | BinOp.Minus  => TWord.Subtract (x, y, r);
    | BinOp.Divide => IF NOT TWord.Div (x, y, r) THEN RETURN NIL END;
    | BinOp.Mod    => IF NOT TWord.Mod (x, y, r) THEN RETURN NIL END;
    | BinOp.And    => TWord.And (x, y, r);
    | BinOp.Or     => TWord.Or (x, y, r);
    | BinOp.Xor    => TWord.Xor (x, y, r);
    END;
    RETURN Result (info, r);
  END FoldBinary;

PROCEDURE CompileCompare (ce: CallExpr.T;  op: CmpOp) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    Expr.Compile (ce.args[1]);
    CG.Compare (Stk (info), CmpMap[op]);
  END CompileCompare;

PROCEDURE FoldCompare (ce: CallExpr.T;  op: CmpOp): Expr.T =
  VAR x, y: Target.Int;  b: BOOLEAN;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) OR NOT ConstInt (ce.args[1], y) THEN
      RETURN NIL;
    END;
    (* both are values of the fixed type: in range, so TInt compares
       them right whether it is signed or not *)
    CASE op OF
    | CmpOp.LT => b := TInt.LT (x, y);
    | CmpOp.LE => b := TInt.LE (x, y);
    | CmpOp.GT => b := TInt.GT (x, y);
    | CmpOp.GE => b := TInt.GE (x, y);
    | CmpOp.EQ => b := TInt.EQ (x, y);
    END;
    RETURN Bool.Map[b];
  END FoldCompare;

PROCEDURE CompilePlus   (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Plus) END CompilePlus;
PROCEDURE CompileTimes  (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Times) END CompileTimes;
PROCEDURE CompileMinus  (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Minus) END CompileMinus;
PROCEDURE CompileDivide (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Divide) END CompileDivide;
PROCEDURE CompileMod    (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Mod) END CompileMod;
PROCEDURE CompileAnd    (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.And) END CompileAnd;
PROCEDURE CompileOr     (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Or) END CompileOr;
PROCEDURE CompileXor    (ce: CallExpr.T) = BEGIN CompileBinary (ce, BinOp.Xor) END CompileXor;

PROCEDURE FoldPlus   (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Plus) END FoldPlus;
PROCEDURE FoldTimes  (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Times) END FoldTimes;
PROCEDURE FoldMinus  (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Minus) END FoldMinus;
PROCEDURE FoldDivide (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Divide) END FoldDivide;
PROCEDURE FoldMod    (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Mod) END FoldMod;
PROCEDURE FoldAnd    (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.And) END FoldAnd;
PROCEDURE FoldOr     (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Or) END FoldOr;
PROCEDURE FoldXor    (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldBinary (ce, BinOp.Xor) END FoldXor;

PROCEDURE CompileLT (ce: CallExpr.T) = BEGIN CompileCompare (ce, CmpOp.LT) END CompileLT;
PROCEDURE CompileLE (ce: CallExpr.T) = BEGIN CompileCompare (ce, CmpOp.LE) END CompileLE;
PROCEDURE CompileGT (ce: CallExpr.T) = BEGIN CompileCompare (ce, CmpOp.GT) END CompileGT;
PROCEDURE CompileGE (ce: CallExpr.T) = BEGIN CompileCompare (ce, CmpOp.GE) END CompileGE;
PROCEDURE CompileEQ (ce: CallExpr.T) = BEGIN CompileCompare (ce, CmpOp.EQ) END CompileEQ;

PROCEDURE FoldLT (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldCompare (ce, CmpOp.LT) END FoldLT;
PROCEDURE FoldLE (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldCompare (ce, CmpOp.LE) END FoldLE;
PROCEDURE FoldGT (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldCompare (ce, CmpOp.GT) END FoldGT;
PROCEDURE FoldGE (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldCompare (ce, CmpOp.GE) END FoldGE;
PROCEDURE FoldEQ (ce: CallExpr.T): Expr.T = BEGIN RETURN FoldCompare (ce, CmpOp.EQ) END FoldEQ;

PROCEDURE CompileNot (ce: CallExpr.T) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    CG.Not (Stk (info));
    FixedType.Mask (info);
  END CompileNot;

PROCEDURE FoldNot (ce: CallExpr.T): Expr.T =
  VAR info: FixedType.Info;  x, r: Target.Int;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) THEN RETURN NIL END;
    GetInfo (ce, info);
    TWord.Not (x, r);
    RETURN Result (info, r);
  END FoldNot;

(*-------------------------------------------------------------- shifts ---*)

PROCEDURE CompileShift (ce: CallExpr.T) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    Expr.Compile (ce.args[1]);
    CG.Shift (Stk (info));
    FixedType.Mask (info);
  END CompileShift;

PROCEDURE CompileLeftShift (ce: CallExpr.T) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    CheckExpr.EmitChecks (ce.args[1], TInt.Zero, Max (info.bits - 1),
                          CG.RuntimeError.ValueOutOfRange);
    CG.Shift_left (Stk (info));
    FixedType.Mask (info);
  END CompileLeftShift;

PROCEDURE CompileRightShift (ce: CallExpr.T) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    CheckExpr.EmitChecks (ce.args[1], TInt.Zero, Max (info.bits - 1),
                          CG.RuntimeError.ValueOutOfRange);
    CG.Shift_right (Stk (info));
  END CompileRightShift;

PROCEDURE FoldShift (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldShifts (ce, 1, FALSE);
  END FoldShift;

PROCEDURE FoldLeftShift (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldShifts (ce, 1, TRUE);
  END FoldLeftShift;

PROCEDURE FoldRightShift (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldShifts (ce, -1, TRUE);
  END FoldRightShift;

PROCEDURE FoldShifts (ce: CallExpr.T;  sign: INTEGER;
                      checked: BOOLEAN): Expr.T =
  VAR info: FixedType.Info;  x, r: Target.Int;  n: INTEGER;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) OR NOT ConstIndex (ce.args[1], n) THEN
      RETURN NIL;
    END;
    GetInfo (ce, info);
    IF checked AND (n < 0 OR n >= info.bits) THEN RETURN NIL END;
    IF ABS (n) >= info.bits THEN RETURN Result (info, TInt.Zero) END;
    TWord.Shift (x, sign * n, r);
    RETURN Result (info, r);
  END FoldShifts;

(*------------------------------------------------------------- rotates ---*)

PROCEDURE CompileRotate (ce: CallExpr.T) =
  BEGIN
    CompileRotates (ce, 0, FALSE);
  END CompileRotate;

PROCEDURE CompileLeftRotate (ce: CallExpr.T) =
  BEGIN
    CompileRotates (ce, 1, TRUE);
  END CompileLeftRotate;

PROCEDURE CompileRightRotate (ce: CallExpr.T) =
  BEGIN
    CompileRotates (ce, -1, TRUE);
  END CompileRightRotate;

PROCEDURE CompileRotates (ce: CallExpr.T;  dir: INTEGER;  checked: BOOLEAN) =
  (* dir = 0: Rotate (any n); 1: LeftRotate; -1: RightRotate. *)
  VAR info: FixedType.Info;  stk: CG.Type;  x, n: CG.Val;
      int := Target.Integer.cg_type;
  BEGIN
    GetInfo (ce, info);
    stk := Stk (info);
    IF FixedType.Fills (info) THEN
      Expr.Compile (ce.args[0]);
      IF checked THEN
        CheckExpr.EmitChecks (ce.args[1], TInt.Zero, Max (info.bits - 1),
                              CG.RuntimeError.ValueOutOfRange);
      ELSE
        Expr.Compile (ce.args[1]);
      END;
      CASE dir OF
      | 0  => CG.Rotate (stk);
      | 1  => CG.Rotate_left (stk);
      | -1 => CG.Rotate_right (stk);
      ELSE <*ASSERT FALSE*>
      END;
      RETURN;
    END;

    (* N is less than the size of S: compute the left rotation count
       n' in [0..N], then (x << n' | x >> (N - n')) masked to N bits.
       n' = N is a rotation by 0: x << N is masked away and x >> 0
       is x. *)
    Expr.Compile (ce.args[0]);
    x := CG.Pop ();
    IF checked THEN
      CheckExpr.EmitChecks (ce.args[1], TInt.Zero, Max (info.bits - 1),
                            CG.RuntimeError.ValueOutOfRange);
      IF dir < 0 THEN
        (* right by n = left by N - n *)
        n := CG.Pop ();
        CG.Load_intt (info.bits);
        CG.Push (n);
        CG.Subtract (int);
        CG.Free (n);
      END;
    ELSE
      Expr.Compile (ce.args[1]);
      CG.Load_intt (info.bits);
      CG.Mod (int, CG.Sign.Unknown, CG.Sign.Positive);
    END;
    n := CG.Pop ();

    CG.Push (x);
    CG.Push (n);
    CG.Shift_left (stk);
    CG.Push (x);
    CG.Load_intt (info.bits);
    CG.Push (n);
    CG.Subtract (int);
    CG.Shift_right (stk);
    CG.Or (stk);
    FixedType.Mask (info);
    CG.Free (x);
    CG.Free (n);
  END CompileRotates;

PROCEDURE FoldRotate (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldRotates (ce, 1, FALSE);
  END FoldRotate;

PROCEDURE FoldLeftRotate (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldRotates (ce, 1, TRUE);
  END FoldLeftRotate;

PROCEDURE FoldRightRotate (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldRotates (ce, -1, TRUE);
  END FoldRightRotate;

PROCEDURE FoldRotates (ce: CallExpr.T;  sign: INTEGER;
                       checked: BOOLEAN): Expr.T =
  VAR info: FixedType.Info;  x, r: Target.Int;  n: INTEGER;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) OR NOT ConstIndex (ce.args[1], n) THEN
      RETURN NIL;
    END;
    GetInfo (ce, info);
    IF checked AND (n < 0 OR n >= info.bits) THEN RETURN NIL END;
    (* TWord.Rotate rotates the low bits DIV 8 bytes; a left rotation
       by (sign * n) MOD N is the same rotation for any n *)
    TWord.Rotate (x, (sign * n) MOD info.bits, info.bits DIV 8, r);
    RETURN Result (info, r);
  END FoldRotates;

(*---------------------------------------------------- Extract, Insert ---*)

PROCEDURE CompileExtract (ce: CallExpr.T) =
  VAR info: FixedType.Info;  stk: CG.Type;  ti, tn: CG.Val;
      i, n: INTEGER;  ci, cn: BOOLEAN;
  BEGIN
    GetInfo (ce, info);
    stk := Stk (info);
    ci := ConstIndex (ce.args[1], i);
    cn := ConstIndex (ce.args[2], n);
    IF ci AND cn THEN
      IF (i < 0) OR (n < 0) OR (i + n > info.bits) THEN
        Error.Warn (2, "Extract: i+n value out of range");
        CG.Load_integer (Target.Integer.cg_type, TInt.One);
        CG.Check_hi (Target.Integer.cg_type, TInt.Zero,
                     CG.RuntimeError.ValueOutOfRange);
        CG.Discard (Target.Integer.cg_type);
        CG.Load_integer (stk, TInt.Zero);
      ELSE
        Expr.Compile (ce.args[0]);
        CG.Extract_mn (stk, FALSE, i, n);
      END;
    ELSE
      EmitBitRange (ce.args[1], ce.args[2], info.bits, ti, tn);
      Expr.Compile (ce.args[0]);
      CG.ForceStacked ();
      CG.Push (ti);
      CG.Push (tn);
      CG.Extract (stk, sign := FALSE);
      CG.Free (ti);
      CG.Free (tn);
    END;
  END CompileExtract;

PROCEDURE CompileInsert (ce: CallExpr.T) =
  VAR info: FixedType.Info;  stk: CG.Type;  ti, tn: CG.Val;
      i, n: INTEGER;  ci, cn: BOOLEAN;
  BEGIN
    GetInfo (ce, info);
    stk := Stk (info);
    ci := ConstIndex (ce.args[2], i);
    cn := ConstIndex (ce.args[3], n);
    IF ci AND cn THEN
      IF (i < 0) OR (n < 0) OR (i + n > info.bits) THEN
        Error.Warn (2, "Insert: i+n value out of range");
        CG.Load_integer (Target.Integer.cg_type, TInt.One);
        CG.Check_hi (Target.Integer.cg_type, TInt.Zero,
                     CG.RuntimeError.ValueOutOfRange);
        CG.Discard (Target.Integer.cg_type);
        CG.Load_integer (stk, TInt.Zero);
      ELSE
        Expr.Compile (ce.args[0]);
        CG.ForceStacked ();
        Expr.Compile (ce.args[1]);
        CG.Insert_mn (stk, i, n);
      END;
    ELSE
      EmitBitRange (ce.args[2], ce.args[3], info.bits, ti, tn);
      Expr.Compile (ce.args[0]);
      CG.ForceStacked ();
      Expr.Compile (ce.args[1]);
      CG.ForceStacked ();
      CG.Push (ti);
      CG.Push (tn);
      CG.Insert (stk);
      CG.Free (ti);
      CG.Free (tn);
    END;
  END CompileInsert;

PROCEDURE EmitBitRange (ei, en: Expr.T;  bits: INTEGER;  VAR ti, tn: CG.Val) =
  (* Compile i and n, check that both are non-negative and that
     i + n <= bits, and leave them in ti and tn. *)
  VAR int := Target.Integer.cg_type;
  BEGIN
    CheckExpr.EmitChecks (ei, TInt.Zero, Target.Integer.max,
                          CG.RuntimeError.ValueOutOfRange);
    ti := CG.Pop ();
    CheckExpr.EmitChecks (en, TInt.Zero, Target.Integer.max,
                          CG.RuntimeError.ValueOutOfRange);
    tn := CG.Pop ();
    IF Host.doRangeChk THEN
      CG.Push (ti);
      CG.Push (tn);
      CG.Add (int);
      CG.Check_hi (int, Max (bits), CG.RuntimeError.ValueOutOfRange);
      CG.Discard (int);
    END;
  END EmitBitRange;

PROCEDURE FoldExtract (ce: CallExpr.T): Expr.T =
  VAR info: FixedType.Info;  x, r: Target.Int;  i, n: INTEGER;
  BEGIN
    IF NOT ConstInt (ce.args[0], x)
      OR NOT ConstIndex (ce.args[1], i)
      OR NOT ConstIndex (ce.args[2], n) THEN
      RETURN NIL;
    END;
    GetInfo (ce, info);
    IF (i < 0) OR (n < 0) OR (i + n > info.bits)
      OR NOT TWord.Extract (x, i, n, r) THEN
      RETURN NIL;
    END;
    RETURN Result (info, r);
  END FoldExtract;

PROCEDURE FoldInsert (ce: CallExpr.T): Expr.T =
  VAR info: FixedType.Info;  x, y, r: Target.Int;  i, n: INTEGER;
  BEGIN
    IF NOT ConstInt (ce.args[0], x)
      OR NOT ConstInt (ce.args[1], y)
      OR NOT ConstIndex (ce.args[2], i)
      OR NOT ConstIndex (ce.args[3], n) THEN
      RETURN NIL;
    END;
    GetInfo (ce, info);
    IF (i < 0) OR (n < 0) OR (i + n > info.bits)
      OR NOT TWord.Insert (x, y, i, n, r) THEN
      RETURN NIL;
    END;
    RETURN Result (info, r);
  END FoldInsert;

(*--------------------------------------------------------- conversions ---*)

PROCEDURE CompileWrap (ce: CallExpr.T) =
  (* Wrap, FromWord and FromLong: keep the low N bits *)
  VAR info: FixedType.Info;  from: CG.Type;
  BEGIN
    GetInfo (ce, info);
    from := FixedType.OrdStackType (Expr.TypeOf (ce.args[0]));
    Expr.Compile (ce.args[0]);
    IF from # Stk (info) THEN CG.Loophole (from, Stk (info)) END;
    FixedType.Mask (info);
  END CompileWrap;

PROCEDURE FoldWrap (ce: CallExpr.T): Expr.T =
  VAR info: FixedType.Info;  x: Target.Int;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) THEN RETURN NIL END;
    GetInfo (ce, info);
    RETURN Result (info, x);
  END FoldWrap;

PROCEDURE CompileToWord (ce: CallExpr.T) =
  (* ToWord and Hash *)
  BEGIN
    CompileTo (ce, Target.Integer.cg_type);
  END CompileToWord;

PROCEDURE CompileToLong (ce: CallExpr.T) =
  BEGIN
    CompileTo (ce, Target.Longint.cg_type);
  END CompileToLong;

PROCEDURE CompileTo (ce: CallExpr.T;  to: CG.Type) =
  VAR info: FixedType.Info;
  BEGIN
    GetInfo (ce, info);
    Expr.Compile (ce.args[0]);
    IF Stk (info) # to THEN CG.Loophole (Stk (info), to) END;
  END CompileTo;

PROCEDURE FoldToWord (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldTo (ce, Int.T, Target.Integer.bytes);
  END FoldToWord;

PROCEDURE FoldToLong (ce: CallExpr.T): Expr.T =
  BEGIN
    RETURN FoldTo (ce, LInt.T, Target.Longint.bytes);
  END FoldToLong;

PROCEDURE FoldTo (ce: CallExpr.T;  t: Type.T;  bytes: INTEGER): Expr.T =
  (* the value's bits, read as a signed integer of 'bytes' bytes *)
  VAR x, r: Target.Int;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) THEN RETURN NIL END;
    EVAL TWord.Truncate (x, bytes, r);
    EVAL TInt.Extend (r, bytes, r);
    RETURN IntegerExpr.New (t, r);
  END FoldTo;

(*------------------------------------------------------------- Compare ---*)

PROCEDURE CompileOrder (ce: CallExpr.T) =
  (* Compare (a, b) = ORD (a > b) - ORD (a < b) *)
  VAR info: FixedType.Info;  stk: CG.Type;  a, b: CG.Val;
  BEGIN
    GetInfo (ce, info);
    stk := Stk (info);
    Expr.Compile (ce.args[0]);
    a := CG.Pop ();
    Expr.Compile (ce.args[1]);
    b := CG.Pop ();
    CG.Push (a);
    CG.Push (b);
    CG.Compare (stk, CG.Cmp.GT);
    CG.Push (a);
    CG.Push (b);
    CG.Compare (stk, CG.Cmp.LT);
    CG.Subtract (Target.Integer.cg_type);
    CG.Free (a);
    CG.Free (b);
  END CompileOrder;

PROCEDURE FoldOrder (ce: CallExpr.T): Expr.T =
  VAR x, y: Target.Int;
  BEGIN
    IF NOT ConstInt (ce.args[0], x) OR NOT ConstInt (ce.args[1], y) THEN
      RETURN NIL;
    END;
    IF    TInt.LT (x, y) THEN RETURN IntegerExpr.New (Int.T, TInt.MOne);
    ELSIF TInt.GT (x, y) THEN RETURN IntegerExpr.New (Int.T, TInt.One);
    ELSE                      RETURN IntegerExpr.New (Int.T, TInt.Zero);
    END;
  END FoldOrder;

(*--------------------------------------------------------- definitions ---*)

PROCEDURE Def (name: TEXT;  sig: Type.T;  nArgs: INTEGER;
               check: CallExpr.TypeChecker;
               compile: CallExpr.Compiler;
               fold: CallExpr.Evaluator;
               boolean := FALSE) =
  VAR z: CallExpr.MethodList;
      prepBR, compileBR: CallExpr.CompilerBR;
  BEGIN
    IF boolean THEN
      prepBR := CallExpr.PrepNoBranch;  compileBR := CallExpr.NoBranch;
    ELSE
      prepBR := CallExpr.NotBoolean;    compileBR := CallExpr.NotBoolean;
    END;
    z := CallExpr.NewMethodList (nArgs, nArgs, TRUE, TRUE, TRUE,
                                 ProcType.Result (sig),
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 check,
                                 CallExpr.PrepArgs,
                                 compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 prepBR,
                                 compileBR,
                                 fold,
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined (name, z, FALSE, sig, assignable := TRUE);
  END Def;

PROCEDURE F (name: TEXT;  offset: INTEGER;  t: Type.T): Value.T =
  BEGIN
    RETURN Formal.NewBuiltin (name, offset, t);
  END F;

PROCEDURE Binary (name: TEXT;  t, result: Type.T;  compile: CallExpr.Compiler;
                  fold: CallExpr.Evaluator) =
  BEGIN
    Def (name, ProcType.New (result, F ("x", 0, t), F ("y", 1, t)), 2,
         Check, compile, fold, boolean := (result = Bool.T));
  END Binary;

PROCEDURE Define (t: Type.T;  name: TEXT) =
  VAR
    info: FixedType.Info;
    b := FixedType.Split (t, info);
    index := SubrangeType.New (TInt.Zero, Max (info.bits - 1), Int.T, FALSE);
    order := SubrangeType.New (TInt.MOne, TInt.One, Int.T, FALSE);
  BEGIN
    <*ASSERT b*>
    IF info.signed THEN
      (* WARNING: the order must be that of m3core's GenSignedN.ig, or
         the version stamps won't match. *)
      DefineWrap (t);
      DefineCommon (t, name, order);
      RETURN;
    END;
    (* WARNING: as in builtinWord/Module.mg, the order must be that of
       m3core's GenWordN.ig, or the version stamps won't match. *)
    Binary ("Plus",   t, t, CompilePlus,   FoldPlus);
    Binary ("Times",  t, t, CompileTimes,  FoldTimes);
    Binary ("Minus",  t, t, CompileMinus,  FoldMinus);
    Binary ("Divide", t, t, CompileDivide, FoldDivide);
    Binary ("Mod",    t, t, CompileMod,    FoldMod);
    Binary ("LT", t, Bool.T, CompileLT, FoldLT);
    Binary ("LE", t, Bool.T, CompileLE, FoldLE);
    Binary ("GT", t, Bool.T, CompileGT, FoldGT);
    Binary ("GE", t, Bool.T, CompileGE, FoldGE);
    Binary ("And", t, t, CompileAnd, FoldAnd);
    Binary ("Or",  t, t, CompileOr,  FoldOr);
    Binary ("Xor", t, t, CompileXor, FoldXor);
    Def ("Not", ProcType.New (t, F ("x", 0, t)), 1,
         Check, CompileNot, FoldNot);
    Def ("Shift", ProcType.New (t, F ("x", 0, t), F ("n", 1, Int.T)), 2,
         Check, CompileShift, FoldShift);
    Def ("LeftShift", ProcType.New (t, F ("x", 0, t), F ("n", 1, index)), 2,
         Check, CompileLeftShift, FoldLeftShift);
    Def ("RightShift", ProcType.New (t, F ("x", 0, t), F ("n", 1, index)), 2,
         Check, CompileRightShift, FoldRightShift);
    Def ("Rotate", ProcType.New (t, F ("x", 0, t), F ("n", 1, Int.T)), 2,
         Check, CompileRotate, FoldRotate);
    Def ("LeftRotate", ProcType.New (t, F ("x", 0, t), F ("n", 1, index)), 2,
         Check, CompileLeftRotate, FoldLeftRotate);
    Def ("RightRotate", ProcType.New (t, F ("x", 0, t), F ("n", 1, index)), 2,
         Check, CompileRightRotate, FoldRightRotate);
    Def ("Extract", ProcType.New (t, F ("x", 0, t), F ("i", 1, Card.T),
                                  F ("n", 2, Card.T)), 3,
         Check, CompileExtract, FoldExtract);
    Def ("Insert", ProcType.New (t, F ("x", 0, t), F ("y", 1, t),
                                 F ("i", 2, Card.T), F ("n", 3, Card.T)), 4,
         Check, CompileInsert, FoldInsert);

    (* GenWordN.ig *)
    DefineWrap (t);
    Def ("FromWord", ProcType.New (t, F ("w", 0, Int.T)), 1,
         Check, CompileWrap, FoldWrap);
    Def ("ToWord", ProcType.New (Int.T, F ("x", 0, t)), 1,
         Check, CompileToWord, FoldToWord);
    Def ("FromLong", ProcType.New (t, F ("l", 0, LInt.T)), 1,
         Check, CompileWrap, FoldWrap);
    Def ("ToLong", ProcType.New (LInt.T, F ("x", 0, t)), 1,
         Check, CompileToLong, FoldToLong);
    DefineCommon (t, name, order);
  END Define;

PROCEDURE DefineWrap (t: Type.T) =
  (* For SignedN, Mask and FixedType.Wrap sign-extend the low N bits. *)
  BEGIN
    Def ("Wrap", ProcType.New (t, F ("x", 0, LInt.T)), 1,
         CheckWrap, CompileWrap, FoldWrap);
  END DefineWrap;

PROCEDURE DefineCommon (t: Type.T;  name: TEXT;  order: Type.T) =
  (* Brand, Equal, Hash and Compare, the same for both families: the
     compares and Hash work in the stack type, which holds a SignedN
     sign-extended. *)
  BEGIN
    EVAL Constant.Declare ("Brand", TextExpr.New8 (M3String.Add (name)),
                           FALSE);
    Def ("Equal", ProcType.New (Bool.T, F ("a", 0, t), F ("b", 1, t)), 2,
         Check, CompileEQ, FoldEQ, boolean := TRUE);
    Def ("Hash", ProcType.New (Int.T, F ("a", 0, t)), 1,
         Check, CompileToWord, FoldToWord);
    Def ("Compare", ProcType.New (order, F ("a", 0, t), F ("b", 1, t)), 2,
         Check, CompileOrder, FoldOrder);
  END DefineCommon;

BEGIN
END FixedWord.
