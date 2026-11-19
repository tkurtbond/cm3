(* See the file COPYRIGHT for a full description. *)

(* This fork: the fixed-width integer types.  See FixedType.i3. *)

MODULE FixedType;

IMPORT M3, M3ID, CG, Type, TypeRep, Target, TInt, TWord, TipeMap, TipeDesc;
IMPORT Tipe, Scope, Module, NamedType, Constant, IntegerExpr, Int, LInt;
IMPORT Scanner, Host, FixedWord, Expr;

TYPE
  P = Type.T BRANDED "FixedType.P" OBJECT
        bits   : INTEGER;
        signed : BOOLEAN;
        rep    : Target.Int_type;   (* the in-memory representation *)
        tag    : TEXT;              (* the fingerprint tag *)
        name   : TEXT;              (* the builtin interface *)
      OVERRIDES
        check      := Check;
        no_straddle:= TypeRep.ScalarNoStraddle;
        isEqual    := TypeRep.NeverEqual;
        isSubtype  := TypeRep.NoSubtypes;
        compile    := Compiler;
        initCost   := InitCoster;
        initValue  := TypeRep.InitToZeros;
        mapper     := GenMap;
        gen_desc   := GenDesc;
        fprint     := FPrinter;
      END;

VAR
  all   : ARRAY [0..7] OF P;
  names : ARRAY [0..7] OF M3ID.T;

CONST
  hasUnit = ARRAY [0..7] OF BOOLEAN { TRUE, .. };
  (* which of all[] m3core implements, in src/word *)

  Overflow = CG.RuntimeError.IntegerOverflow;

PROCEDURE New (bits: INTEGER;  signed: BOOLEAN;
               READONLY rep: Target.Int_type;  tag, name: TEXT): P =
  VAR p := NEW (P, bits := bits, signed := signed, rep := rep,
                tag := tag, name := name);
  BEGIN
    TypeRep.Init (p, Type.Class.Fixed);
    RETURN p;
  END New;

PROCEDURE Initialize () =
  BEGIN
    all[0] := New ( 8, FALSE, Target.Word8,  "$word8",  "Word8");
    all[1] := New (16, FALSE, Target.Word16, "$word16", "Word16");
    all[2] := New (32, FALSE, Target.Word32, "$word32", "Word32");
    all[3] := New (64, FALSE, Target.Word64, "$word64", "Word64");
    all[4] := New ( 8, TRUE,  Target.Int8,   "$signed8",  "Signed8");
    all[5] := New (16, TRUE,  Target.Int16,  "$signed16", "Signed16");
    all[6] := New (32, TRUE,  Target.Int32,  "$signed32", "Signed32");
    all[7] := New (64, TRUE,  Target.Int64,  "$signed64", "Signed64");
    Word8    := all[0];
    Word16   := all[1];
    Word32   := all[2];
    Word64   := all[3];
    Signed8  := all[4];
    Signed16 := all[5];
    Signed32 := all[6];
    Signed64 := all[7];
  END Initialize;

PROCEDURE InitializeInterfaces () =
  VAR m: Module.T;  zz: Scope.T;  size: Target.Int;  b: BOOLEAN;
  BEGIN
    FOR i := FIRST (all) TO LAST (all) DO
      WITH p = all[i] DO
        names[i] := M3ID.Add (p.name);
        Scanner.Push (p.name & ".i3", NIL, is_main := Host.emitBuiltins);
          m := Module.NewDefn (p.name, TRUE, NIL);
          zz := Scope.Push (Module.ExportScope (m));
            Tipe.Define ("T", NamedType.New (p), FALSE);
            b := TInt.FromInt (p.bits, size);  <*ASSERT b*>
            EVAL Constant.Declare ("Size", IntegerExpr.New (Int.T, size),
                                   FALSE);
            FixedWord.Define (p, p.name);
          Scope.Pop (zz);
        Scanner.Pop ();
      END;
    END;
  END InitializeInterfaces;

PROCEDURE IsInterface (name: M3ID.T): BOOLEAN =
  BEGIN
    FOR i := FIRST (names) TO LAST (names) DO
      IF names[i] = name THEN RETURN TRUE END;
    END;
    RETURN FALSE;
  END IsInterface;

PROCEDURE HasNoUnit (name: M3ID.T): BOOLEAN =
  BEGIN
    FOR i := FIRST (names) TO LAST (names) DO
      IF names[i] = name THEN RETURN NOT hasUnit[i] END;
    END;
    RETURN FALSE;
  END HasNoUnit;

PROCEDURE Split (t: Type.T;  VAR info: Info): BOOLEAN =
  VAR u := Type.Check (Type.Base (t));
  BEGIN
    TYPECASE u OF
    | NULL => RETURN FALSE;
    | P (p) =>
        info.type   := p;
        info.bits   := p.bits;
        info.signed := p.signed;
        info.min    := p.rep.min;
        info.max    := p.rep.max;
        RETURN TRUE;
    ELSE RETURN FALSE;
    END;
  END Split;

PROCEDURE Is (t: Type.T): BOOLEAN =
  VAR info: Info;
  BEGIN
    RETURN Split (t, info);
  END Is;

PROCEDURE IsWord (t: Type.T): BOOLEAN =
  VAR info: Info;
  BEGIN
    RETURN Split (t, info) AND NOT info.signed;
  END IsWord;

PROCEDURE Wrap (READONLY info: Info;  READONLY x: Target.Int;
                VAR r: Target.Int) =
  BEGIN
    IF info.signed
      THEN EVAL TInt.Extend (x, info.bits DIV 8, r);
      ELSE EVAL TWord.Truncate (x, info.bits DIV 8, r);
    END;
  END Wrap;

PROCEDURE InRange (READONLY info: Info;  READONLY x: Target.Int): BOOLEAN =
  BEGIN
    RETURN TInt.LE (info.min, x) AND TInt.LE (x, info.max);
  END InRange;

PROCEDURE StackType (READONLY info: Info): CG.Type =
  BEGIN
    RETURN info.type.info.stk_type;
  END StackType;

PROCEDURE OrdStackType (t: Type.T): CG.Type =
  VAR info: Info;
  BEGIN
    IF Split (t, info) THEN RETURN info.type.info.stk_type;
    ELSIF Type.IsSubtype (t, LInt.T) THEN RETURN Target.Longint.cg_type;
    ELSE RETURN Target.Integer.cg_type;
    END;
  END OrdStackType;

PROCEDURE Mask (READONLY info: Info) =
  VAR stk := info.type.info.stk_type;  mask: Target.Int;
  BEGIN
    IF info.bits >= TargetSize (stk) THEN
      (* nothing to do *)
    ELSIF info.signed THEN
      CG.Extract_mn (stk, TRUE, 0, info.bits);
    ELSE
      TWord.nBitsOnRight (info.bits, mask);
      CG.Load_integer (stk, mask);
      CG.And (stk);
    END;
  END Mask;

PROCEDURE Fills (READONLY info: Info): BOOLEAN =
  BEGIN
    RETURN info.bits >= TargetSize (info.type.info.stk_type);
  END Fills;

PROCEDURE TargetSize (t: CG.Type): INTEGER =
  BEGIN
    IF t = Target.Word.cg_type OR t = Target.Integer.cg_type
      THEN RETURN Target.Word.size;
      ELSE RETURN Target.Long.size;
    END;
  END TargetSize;

(*------------------------------------------------------------ arithmetic ---*)

(* SignedN is computed in its stack type, INTEGER or LONGINT.  Below
   the full width of that type, (Signed8, Signed16, and Signed32 on a
   64-bit target) the result can't overflow the stack type, so it is
   checked against the type's bounds afterwards (or, without range
   checks, sign-extended to wrap).  At full width the wrapping result
   is computed in the unsigned stack type, since a signed overflow is
   undefined in C, and overflow is detected from the operands and
   result.  Multiply, and DIV and MOD by a divisor that might be -1,
   need branches, so they are compiled in Prep. *)

PROCEDURE UnsignedType (stk: CG.Type): CG.Type =
  BEGIN
    IF stk = Target.Integer.cg_type
      THEN RETURN Target.Word.cg_type;
      ELSE RETURN Target.Long.cg_type;
    END;
  END UnsignedType;

PROCEDURE CheckOrWrap (READONLY info: Info) =
  (* s0 is the result in the stack type, of a narrow SignedN *)
  BEGIN
    IF Host.doRangeChk
      THEN CG.Check_range (StackType (info), info.min, info.max, Overflow);
      ELSE Mask (info);
    END;
  END CheckOrWrap;

PROCEDURE WrapOp (READONLY info: Info;  op: Op) =
  (* s1 := s1 op s0, wrapped, for a full-width SignedN; pop *)
  VAR stk := StackType (info);  u := UnsignedType (stk);  b: CG.Val;
  BEGIN
    b := CG.Pop ();
    CG.Loophole (stk, u);
    CG.Push (b);
    CG.Free (b);
    CG.Loophole (stk, u);
    CASE op OF
    | Op.Add      => CG.Add (u);
    | Op.Subtract => CG.Subtract (u);
    | Op.Multiply => CG.Multiply (u);
    | Op.Div, Op.Mod => <*ASSERT FALSE*>
    END;
    CG.Loophole (u, stk);
  END WrapOp;

PROCEDURE NeedsPrep (READONLY info: Info;  op: Op;  b: Expr.T): BOOLEAN =
  VAR min, max: Target.Int;
  BEGIN
    IF NOT info.signed OR NOT Fills (info) THEN RETURN FALSE END;
    CASE op OF
    | Op.Add, Op.Subtract =>
        RETURN FALSE;
    | Op.Multiply =>
        RETURN Host.doRangeChk;
    | Op.Div, Op.Mod =>
        Expr.GetBounds (b, min, max);
        RETURN TInt.LE (min, TInt.MOne) AND TInt.LE (TInt.MOne, max);
    END;
  END NeedsPrep;

PROCEDURE PrepOperate (READONLY info: Info;  op: Op;  a, b: Expr.T): CG.Val =
  VAR
    stk := StackType (info);
    va, vb, res: CG.Val;
    general, fail, done: CG.Label;
  BEGIN
    IF NOT NeedsPrep (info, op, b) THEN RETURN NIL END;
    Expr.Compile (a);  va := CG.Pop_temp ();
    Expr.Compile (b);  vb := CG.Pop ();
    general := CG.Next_label ();
    fail    := CG.Next_label ();
    done    := CG.Next_label ();
    CASE op OF
    | Op.Add, Op.Subtract =>
        <*ASSERT FALSE*>
    | Op.Multiply =>
        (* r := a * b, wrapped;  then
           a = 0:   no overflow
           a = -1:  overflow iff b = FIRST
           else:    no overflow iff r MOD a = 0 AND r DIV a = b *)
        CG.Push (va);  CG.Push (vb);
        WrapOp (info, Op.Multiply);
        res := CG.Pop_temp ();
        CG.Push (va);
        CG.Load_integer (stk, TInt.Zero);
        CG.If_compare (stk, CG.Cmp.EQ, done, CG.Maybe);
        CG.Push (va);
        CG.Load_integer (stk, TInt.MOne);
        CG.If_compare (stk, CG.Cmp.NE, general, CG.Likely);
        CG.Push (vb);
        CG.Load_integer (stk, info.min);
        CG.If_compare (stk, CG.Cmp.NE, done, CG.Likely);
        CG.Jump (fail);
        CG.Set_label (general);
        CG.Push (res);  CG.Push (va);
        CG.Mod (stk, CG.Sign.Unknown, CG.Sign.Unknown);
        CG.Load_integer (stk, TInt.Zero);
        CG.If_compare (stk, CG.Cmp.NE, fail, CG.Never);
        CG.Push (res);  CG.Push (va);
        CG.Div (stk, CG.Sign.Unknown, CG.Sign.Unknown);
        CG.Push (vb);
        CG.If_compare (stk, CG.Cmp.EQ, done, CG.Always);
        CG.Set_label (fail);
        CG.Abort (Overflow);
    | Op.Div, Op.Mod =>
        (* b = -1:  a DIV b = -a (checked), a MOD b = 0
           else:    as usual; neither can overflow.
           The hardware would trap on FIRST DIV -1. *)
        CG.Push (vb);
        CG.Load_integer (stk, TInt.MOne);
        CG.If_compare (stk, CG.Cmp.NE, general, CG.Likely);
        IF op = Op.Div THEN
          CG.Push (va);
          Negate (info);
        ELSE
          CG.Load_integer (stk, TInt.Zero);
        END;
        res := CG.Pop_temp ();
        CG.Jump (done);
        CG.Set_label (general);
        CG.Push (va);  CG.Push (vb);
        IF op = Op.Div
          THEN CG.Div (stk, CG.Sign.Unknown, CG.Sign.Unknown);
          ELSE CG.Mod (stk, CG.Sign.Unknown, CG.Sign.Unknown);
        END;
        CG.Store_temp (res);
    END;
    CG.Set_label (done);
    CG.Free (va);
    CG.Free (vb);
    RETURN res;
  END PrepOperate;

PROCEDURE CompileOperate (READONLY info: Info;  op: Op;  a, b: Expr.T;
                          VAR val: CG.Val) =
  BEGIN
    IF val # NIL THEN
      CG.Push (val);
      CG.Free (val);
      val := NIL;
    ELSE
      Expr.Compile (a);
      Expr.Compile (b);
      Operate (info, op);
    END;
  END CompileOperate;

PROCEDURE Operate (READONLY info: Info;  op: Op;
                   signA, signB := CG.Sign.Unknown) =
  VAR stk := StackType (info);  va, vb, vr: CG.Val;
  BEGIN
    IF NOT info.signed THEN
      CASE op OF
      | Op.Add      => CG.Add (stk);       Mask (info);
      | Op.Subtract => CG.Subtract (stk);  Mask (info);
      | Op.Multiply => CG.Multiply (stk);  Mask (info);
      | Op.Div      => CG.Div (stk, signA, signB);
      | Op.Mod      => CG.Mod (stk, signA, signB);
      END;
    ELSIF NOT Fills (info) THEN
      (* the stack type can hold the exact result *)
      CASE op OF
      | Op.Add      => CG.Add (stk);       CheckOrWrap (info);
      | Op.Subtract => CG.Subtract (stk);  CheckOrWrap (info);
      | Op.Multiply => CG.Multiply (stk);  CheckOrWrap (info);
      | Op.Div      => CG.Div (stk, signA, signB);  CheckOrWrap (info);
      | Op.Mod      => CG.Mod (stk, signA, signB);
      END;
    ELSE
      CASE op OF
      | Op.Add, Op.Subtract =>
          IF NOT Host.doRangeChk THEN
            WrapOp (info, op);
          ELSE
            (* overflow iff the sign of r differs from that of both
               a and b (Add), or of a but not b (Subtract) *)
            vb := CG.Pop ();
            va := CG.Pop ();
            CG.Push (va);  CG.Push (vb);
            WrapOp (info, op);
            vr := CG.Pop ();
            IF op = Op.Add THEN
              CG.Push (va);  CG.Push (vr);  CG.Xor (stk);
              CG.Push (vb);  CG.Push (vr);  CG.Xor (stk);
            ELSE
              CG.Push (va);  CG.Push (vb);  CG.Xor (stk);
              CG.Push (va);  CG.Push (vr);  CG.Xor (stk);
            END;
            CG.And (stk);
            CG.Check_lo (stk, TInt.Zero, Overflow);
            CG.Discard (stk);
            CG.Push (vr);
            CG.Free (va);
            CG.Free (vb);
            CG.Free (vr);
          END;
      | Op.Multiply =>
          <*ASSERT NOT Host.doRangeChk*>
          WrapOp (info, op);
      | Op.Div => CG.Div (stk, signA, signB);  (* the divisor isn't -1 *)
      | Op.Mod => CG.Mod (stk, signA, signB);
      END;
    END;
  END Operate;

PROCEDURE Negate (READONLY info: Info) =
  VAR stk := StackType (info);  u: CG.Type;  v: CG.Val;  min1: Target.Int;
  BEGIN
    IF info.signed AND Host.doRangeChk THEN
      EVAL TInt.Add (info.min, TInt.One, min1);
      CG.Check_lo (stk, min1, Overflow);
      CG.Negate (stk);
    ELSIF info.signed AND NOT Fills (info) THEN
      CG.Negate (stk);
      Mask (info);
    ELSE
      (* 0 - s0, wrapped, in the unsigned type *)
      u := UnsignedType (stk);
      IF NOT info.signed THEN u := stk END;
      IF u # stk THEN CG.Loophole (stk, u) END;
      v := CG.Pop ();
      CG.Load_integer (u, TInt.Zero);
      CG.Push (v);
      CG.Free (v);
      CG.Subtract (u);
      IF u # stk THEN CG.Loophole (u, stk) END;
      Mask (info);
    END;
  END Negate;

PROCEDURE Abs (READONLY info: Info) =
  VAR stk := StackType (info);  min1: Target.Int;
  BEGIN
    <*ASSERT info.signed*>
    IF Host.doRangeChk THEN
      EVAL TInt.Add (info.min, TInt.One, min1);
      CG.Check_lo (stk, min1, Overflow);
    END;
    CG.Abs (stk);   (* both back ends wrap ABS (FIRST) *)
    Mask (info);
  END Abs;

(*---------------------------------------------------------- type methods ---*)

PROCEDURE Check (p: P) =
  BEGIN
    p.info.size      := p.rep.size;
    p.info.min_size  := p.rep.size;
    p.info.alignment := p.rep.align;
    p.info.mem_type  := p.rep.cg_type;
    IF p.signed THEN
      IF p.bits <= Target.Integer.size
        THEN p.info.stk_type := Target.Integer.cg_type;
        ELSE p.info.stk_type := Target.Longint.cg_type;
      END;
    ELSIF p.bits <= Target.Word.size THEN
      p.info.stk_type := Target.Word.cg_type;
    ELSE
      p.info.stk_type := Target.Long.cg_type;
    END;
    p.info.class     := Type.Class.Fixed;
    p.info.isTraced  := FALSE;
    p.info.isEmpty   := FALSE;
    p.info.isSolid   := TRUE;
    p.info.hash      := 20 + p.bits + ORD (p.signed) * 100;
  END Check;

PROCEDURE Compiler (p: P) =
  (* The back ends know the predeclared types by their UIDs; a fixed
     type is new to them, so declare it as a subrange of INTEGER or
     LONGINT with its own UID. *)
  VAR domain: Type.T := Int.T;
  BEGIN
    IF TInt.LT (Target.Integer.max, p.rep.max) THEN domain := LInt.T END;
    CG.Declare_subrange (Type.GlobalUID (p), Type.GlobalUID (domain),
                         p.rep.min, p.rep.max, p.rep.size);
  END Compiler;

PROCEDURE InitCoster (<*UNUSED*> t: Type.T;
                      <*UNUSED*> zeroed: BOOLEAN): INTEGER =
  BEGIN
    RETURN 0;
  END InitCoster;

PROCEDURE FPrinter (p: P;  VAR x: M3.FPInfo) =
  BEGIN
    x.tag := p.tag;
    x.n_nodes := 0;
  END FPrinter;

PROCEDURE GenMap (p: P;  offset, size: INTEGER;  refs_only: BOOLEAN) =
  (* as SubrangeType.GenMap does for a subrange *)
  VAR bit_offset := offset MOD Target.Byte;  op: TipeMap.Op;
  BEGIN
    IF refs_only THEN RETURN END;
    IF p.signed THEN
      IF (bit_offset # 0) THEN             op := TipeMap.Op.Int_Field;
      ELSIF (size = 1 * Target.Byte) THEN  op := TipeMap.Op.Int_1;
      ELSIF (size = 2 * Target.Byte) THEN  op := TipeMap.Op.Int_2;
      ELSIF (size = 4 * Target.Byte) THEN  op := TipeMap.Op.Int_4;
      ELSIF (size = 8 * Target.Byte) THEN  op := TipeMap.Op.Int_8;
      ELSE (* weird size *)                op := TipeMap.Op.Int_Field;
      END;
    ELSIF (bit_offset # 0) THEN          op := TipeMap.Op.Word_Field;
    ELSIF (size = 1 * Target.Byte) THEN  op := TipeMap.Op.Word_1;
    ELSIF (size = 2 * Target.Byte) THEN  op := TipeMap.Op.Word_2;
    ELSIF (size = 4 * Target.Byte) THEN  op := TipeMap.Op.Word_4;
    ELSIF (size = 8 * Target.Byte) THEN  op := TipeMap.Op.Word_8;
    ELSE (* weird size *)                op := TipeMap.Op.Word_Field;
    END;
    TipeMap.Add (offset, op, bit_offset + 256 * size);
  END GenMap;

PROCEDURE GenDesc (p: P) =
  BEGIN
    IF TipeDesc.AddO (TipeDesc.Op.Subrange, p) THEN
      TipeDesc.AddX (p.rep.min);
      TipeDesc.AddX (p.rep.max);
    END;
  END GenDesc;

BEGIN
END FixedType.
