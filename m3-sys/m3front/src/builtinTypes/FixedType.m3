(* See the file COPYRIGHT for a full description. *)

(* This fork: the fixed-width integer types.  See FixedType.i3. *)

MODULE FixedType;

IMPORT M3, M3ID, CG, Type, TypeRep, Target, TInt, TWord, TipeMap, TipeDesc;
IMPORT Tipe, Scope, Module, NamedType, Constant, IntegerExpr, Int, LInt;
IMPORT Scanner, Host, FixedWord;

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
  all   : ARRAY [0..3] OF P;
  names : ARRAY [0..3] OF M3ID.T;

CONST
  hasUnit = ARRAY [0..3] OF BOOLEAN { FALSE, FALSE, TRUE, FALSE };
  (* which of all[] m3core implements, in src/word *)

PROCEDURE New (bits: INTEGER;  READONLY rep: Target.Int_type;
               tag, name: TEXT): P =
  VAR p := NEW (P, bits := bits, signed := FALSE, rep := rep,
                tag := tag, name := name);
  BEGIN
    TypeRep.Init (p, Type.Class.Fixed);
    RETURN p;
  END New;

PROCEDURE Initialize () =
  BEGIN
    all[0] := New ( 8, Target.Word8,  "$word8",  "Word8");
    all[1] := New (16, Target.Word16, "$word16", "Word16");
    all[2] := New (32, Target.Word32, "$word32", "Word32");
    all[3] := New (64, Target.Word64, "$word64", "Word64");
    Word8  := all[0];
    Word16 := all[1];
    Word32 := all[2];
    Word64 := all[3];
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

PROCEDURE Wrap (READONLY info: Info;  READONLY x: Target.Int;
                VAR r: Target.Int) =
  BEGIN
    <*ASSERT NOT info.signed*>
    EVAL TWord.Truncate (x, info.bits DIV 8, r);
  END Wrap;

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
    IF info.bits < TargetSize (stk) THEN
      <*ASSERT NOT info.signed*>
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

(*---------------------------------------------------------- type methods ---*)

PROCEDURE Check (p: P) =
  BEGIN
    p.info.size      := p.rep.size;
    p.info.min_size  := p.rep.size;
    p.info.alignment := p.rep.align;
    p.info.mem_type  := p.rep.cg_type;
    IF p.bits <= Target.Word.size
      THEN p.info.stk_type := Target.Word.cg_type;
      ELSE p.info.stk_type := Target.Long.cg_type;
    END;
    p.info.class     := Type.Class.Fixed;
    p.info.isTraced  := FALSE;
    p.info.isEmpty   := FALSE;
    p.info.isSolid   := TRUE;
    p.info.hash      := 20 + p.bits;
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

PROCEDURE GenMap (<*UNUSED*> p: P;  offset, size: INTEGER;
                  refs_only: BOOLEAN) =
  (* as SubrangeType.GenMap does for an unsigned subrange *)
  VAR bit_offset := offset MOD Target.Byte;  op: TipeMap.Op;
  BEGIN
    IF refs_only THEN RETURN END;
    IF (bit_offset # 0) THEN             op := TipeMap.Op.Word_Field;
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
