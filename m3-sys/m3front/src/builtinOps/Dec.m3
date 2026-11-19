(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: Dec.m3                                                *)
(* Last Modified On Tue May 23 15:31:47 PDT 1995 By kalsow     *)
(*      Modified On Tue Apr  2 03:46:13 1991 By muller         *)

MODULE Dec;

IMPORT CG, CallExpr, Expr, ExprRep, Type, Procedure, Error, Int, LInt, Module;
IMPORT FixedType; (* This fork *)
IMPORT M3ID, Addr, Target, TInt, IntegerExpr, Host, NamedExpr;

VAR Z: CallExpr.MethodList;

PROCEDURE Check (ce: CallExpr.T;  VAR cs: Expr.CheckState) =
  BEGIN
    DoCheck ("DEC", ce, cs);
  END Check;

PROCEDURE DoCheck (name: TEXT;  ce: CallExpr.T;
                   <*UNUSED*> VAR cs: Expr.CheckState) =
  VAR t, u: Type.T; e: Expr.T;  nm: M3ID.T;
  BEGIN
    e := ce.args[0];
    t := Type.Base (Expr.TypeOf (e));
    IF NOT Type.IsOrdinal (t) THEN
      IF Type.IsSubtype (t, Addr.T) THEN
        IF Module.IsSafe () THEN Error.Txt (name, "unsafe operation") END;
      ELSE
        Error.Txt (name, "first argument must be of an ordinal type");
      END;
    END;
    IF (NOT Expr.IsDesignator (e)) THEN
      Error.Txt (name, "first argument must be a variable");
    ELSIF (NOT Expr.IsWritable (e, traced := FALSE)) THEN
      Error.Txt (name, "first argument must be writable");
    ELSIF NamedExpr.SplitName (e, nm) THEN
      (* simple scalar => we don't need an explicit address
            -- demanded by Eric Veach 9/17/93 *)
    ELSE
      Expr.NeedsAddress (e);
    END;
    IF (NUMBER (ce.args^) > 1) THEN
      IF FixedType.Is (t) THEN (* This fork: the same type or INTEGER *)
        u := Type.Base (Expr.TypeOf (ce.args[1]));
        IF (u # t) AND (u # Int.T) THEN
          Error.Txt (name, "second argument must be of the first argument's"
                             & " base type or an INTEGER");
        END;
      ELSIF Type.IsSubtype (t, LInt.T) THEN
        t := Type.Base (Expr.TypeOf (ce.args[1]));
        IF (t # LInt.T) THEN
          Error.Txt (name, "second argument must be a LONGINT");
        END;
      ELSE
        t := Type.Base (Expr.TypeOf (ce.args[1]));
        IF (t # Int.T) THEN
          Error.Txt (name, "second argument must be an INTEGER");
        END;
      END;
    END;
    ce.type := NIL;
  END DoCheck;

PROCEDURE Prep (ce: CallExpr.T) =
  BEGIN
    Expr.PrepLValue (ce.args[0], traced := FALSE);
    IF (NUMBER (ce.args^) > 1) THEN Expr.Prep (ce.args[1]); END;
  END Prep;

PROCEDURE Compile (ce: CallExpr.T) =
  VAR
    lhs    := ce.args[0];
    tlhs   := Expr.TypeOf (lhs);
    info   : Type.Info;
    dec    : Expr.T;
    check  : [0..3] := 0;
    lvalue : CG.Val;
    tmin, tmax, bmin, bmax: Target.Int;
    cg_type: CG.Type;
  BEGIN
    IF CompileFixed (ce, up := FALSE) THEN RETURN END; (* This fork *)
    tlhs := Type.CheckInfo (tlhs, info);
    IF Type.IsSubtype (tlhs, LInt.T)
      THEN tlhs := LInt.T; cg_type := Target.Longint.cg_type;
      ELSE tlhs := Int.T;  cg_type := Target.Integer.cg_type;
    END;
    EVAL Type.GetBounds (tlhs, tmin, tmax);
    IF (NUMBER (ce.args^) > 1)
      THEN dec := ce.args[1];
      ELSE dec := IntegerExpr.New (tlhs, TInt.One);  Expr.Prep (dec);
    END;
    Expr.GetBounds (lhs, bmin, bmax);

    IF Host.doRangeChk THEN
      IF TInt.LT (tmin, bmin) THEN INC (check) END;
      IF TInt.LT (bmax, tmax) THEN INC (check, 2) END;
    END;

    Expr.CompileLValue (lhs, traced := FALSE);
    lvalue := CG.Pop ();
    CG.Push (lvalue);

    CG.Push (lvalue);
    CG.Load_indirect (info.stk_type, 0, info.size, info.alignment);
    Expr.Compile (dec);

    IF (info.stk_type = CG.Type.Addr)
      THEN CG.Index_bytes (-Target.Byte);  check := 0;
      ELSE CG.Subtract (cg_type);
    END;

    CASE check OF
    | 0 => (* no range checking *)
    | 1 => CG.Check_lo (cg_type, bmin, CG.RuntimeError.ValueOutOfRange);
    | 2 => CG.Check_hi (cg_type, bmax, CG.RuntimeError.ValueOutOfRange);
    | 3 => CG.Check_range (cg_type, bmin, bmax,
                           CG.RuntimeError.ValueOutOfRange);
    END;

    CG.Store_indirect (info.stk_type, 0, info.size);
    CG.Free (lvalue);
    Expr.NoteWrite (lhs);
  END Compile;

(* This fork: INC and DEC of a WordN wrap modulo 2^N; of a SignedN they
   are checked as its '+' and '-' are.  The step is of the variable's
   base type or an INTEGER; an INTEGER is converted to the stack type,
   which gives the right result modulo 2^N even when it is negative.
   For a SignedN narrower than its stack type an INTEGER step is first
   checked to lie within +-(LAST - FIRST), so that the sum can't
   overflow the stack type.  A subrange is then checked against its
   bounds. *)
PROCEDURE CompileFixed (ce: CallExpr.T;  up: BOOLEAN): BOOLEAN =
  VAR
    lhs    := ce.args[0];
    info   : Type.Info;
    fixed  : FixedType.Info;
    check  : [0..3] := 0;
    lvalue : CG.Val;
    bmin, bmax, span, nspan: Target.Int;
    stk    : CG.Type;
    b      : BOOLEAN;
  BEGIN
    IF NOT FixedType.Split (Expr.TypeOf (lhs), fixed) THEN RETURN FALSE END;
    EVAL Type.CheckInfo (Expr.TypeOf (lhs), info);
    stk := FixedType.StackType (fixed);
    Expr.GetBounds (lhs, bmin, bmax);
    IF Host.doRangeChk THEN
      IF TInt.LT (fixed.min, bmin) THEN INC (check) END;
      IF TInt.LT (bmax, fixed.max) THEN INC (check, 2) END;
    END;

    Expr.CompileLValue (lhs, traced := FALSE);
    lvalue := CG.Pop ();
    CG.Push (lvalue);

    CG.Push (lvalue);
    CG.Load_indirect (info.stk_type, 0, info.size, info.alignment);
    IF (NUMBER (ce.args^) > 1) THEN
      WITH step = ce.args[1],
           from = FixedType.OrdStackType (Expr.TypeOf (step)) DO
        Expr.Compile (step);
        IF from # stk THEN CG.Loophole (from, stk) END;
        IF fixed.signed AND Host.doRangeChk AND NOT FixedType.Fills (fixed)
          AND NOT FixedType.Is (Expr.TypeOf (step)) THEN
          b := TInt.Subtract (fixed.max, fixed.min, span);  <*ASSERT b*>
          b := TInt.Subtract (TInt.Zero, span, nspan);  <*ASSERT b*>
          CG.Check_range (stk, nspan, span, CG.RuntimeError.IntegerOverflow);
        END;
      END;
    ELSE
      CG.Load_integer (stk, TInt.One);
    END;
    IF up
      THEN FixedType.Operate (fixed, FixedType.Op.Add);
      ELSE FixedType.Operate (fixed, FixedType.Op.Subtract);
    END;

    CASE check OF
    | 0 => (* no range checking *)
    | 1 => CG.Check_lo (stk, bmin, CG.RuntimeError.ValueOutOfRange);
    | 2 => CG.Check_hi (stk, bmax, CG.RuntimeError.ValueOutOfRange);
    | 3 => CG.Check_range (stk, bmin, bmax, CG.RuntimeError.ValueOutOfRange);
    END;

    CG.Store_indirect (info.stk_type, 0, info.size);
    CG.Free (lvalue);
    Expr.NoteWrite (lhs);
    RETURN TRUE;
  END CompileFixed;

PROCEDURE Initialize () =
  BEGIN
    Z := CallExpr.NewMethodList (1, 2, FALSE, FALSE, TRUE, NIL,
                                 NIL, NIL,
                                 CallExpr.NotAddressable,
                                 Check,
                                 Prep,
                                 Compile,
                                 CallExpr.NoLValue,
                                 CallExpr.NoLValue,
                                 CallExpr.NotBoolean,
                                 CallExpr.NotBoolean,
                                 CallExpr.NoValue,
                                 CallExpr.NoBounds,
                                 CallExpr.IsNever, (* writable *)
                                 CallExpr.IsNever, (* designator *)
                                 CallExpr.NotWritable (* noteWriter *));
    Procedure.DefinePredefined ("DEC", Z, TRUE);
  END Initialize;

BEGIN
END Dec.
