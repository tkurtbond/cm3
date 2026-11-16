(* See the file COPYRIGHT for a full description. *)

(* M3LLVMIR: an M3CG back end that writes textual LLVM IR.

   Design (see PLAN.md, Phase 1):
   - The M3CG expression stack is simulated at compile time: each entry
     is an LLVM operand (a constant, a global, or an SSA temporary
     "%t.N") together with its M3CG stack type.
   - Every local, parameter and temporary lives in memory: an "alloca"
     in the entry block ("%v.N").  Parameters arrive as "%p.N" and are
     stored into their alloca on entry.  LLVM's mem2reg turns this into
     SSA form when optimizing.
   - Labels become basic blocks "L.N".  A conditional branch starts a
     new fall-through block; code after a terminator starts a fresh
     (unreachable) block.
   - Segments and initialized globals become packed structs, with
     explicit zero padding between the initialized fields.
   - All output is buffered and written by end_unit, so the order of
     M3CG operations does not constrain the order of the IR.
   - Operations not implemented yet are inherited from
     M3CG_AssertFalse and fail loudly. *)

MODULE M3LLVMIR;

IMPORT Wr, TextWr, Text, Fmt, Stdio, Thread, TextRefTbl;
IMPORT M3CG, M3CG_Ops, M3CG_AssertFalse, M3ID, Target, TInt;
FROM M3CG IMPORT Name, ByteOffset, TypeUID, CallingConvention;
FROM M3CG IMPORT BitSize, ByteSize, Alignment, Frequency;
FROM M3CG IMPORT Var, Proc, Label, BitOffset;
FROM M3CG IMPORT Type, ZType, IType, MType;

<*FATAL Wr.Failure, Thread.Alerted*>

TYPE
  VarKind = {Global, Imported, Local, Param};

  LVar = Var OBJECT
    id       : INTEGER;
    kind     : VarKind;
    name     : TEXT;           (* "@name" or "%v.N" *)
    size     : ByteSize  := 0;
    align    : Alignment := 1;
    type     : Type      := Type.Struct;
    exported : BOOLEAN   := FALSE;
    used     : BOOLEAN   := FALSE;
  END;

  LProc = Proc OBJECT
    id         : INTEGER;
    name       : TEXT;         (* "@name" *)
    return     : Type;
    imported   : BOOLEAN := FALSE;
    exported   : BOOLEAN := FALSE;
    defined    : BOOLEAN := FALSE;
    used       : BOOLEAN := FALSE;
    params     : REF ARRAY OF LVar;
    n_declared : INTEGER := 0;
    locals     : VarList := NIL;  (* declared before begin_procedure *)
  END;

  VarList  = REF RECORD v: LVar;  next: VarList  END;
  ProcList = REF RECORD p: LProc; next: ProcList END;

  Operand = RECORD
    type : ZType;   (* the M3CG stack type *)
    val  : TEXT;    (* the LLVM operand, without its type *)
  END;

  U = M3CG_AssertFalse.T OBJECT
    wr          : Wr.T;
    error       : M3CG_Ops.ErrorHandler := NIL;
    source_file : TEXT := NIL;
    source_line : INTEGER := 0;

    globals     : TextWr.T;    (* global variable definitions *)
    funcs       : TextWr.T;    (* function definitions *)
    procs       : ProcList := NIL;
    imports     : VarList := NIL;  (* imported globals *)

    next_var    := 1;
    next_proc   := 1;
    n_labels    := 1;
    next_tmp    := 1;
    next_block  := 1;

    (* the procedure whose body is being generated *)
    cur_proc    : LProc := NIL;
    allocas     : TextWr.T;    (* entry block of cur_proc *)
    body        : TextWr.T;    (* rest of cur_proc *)
    terminated  := FALSE;      (* last instruction was a terminator *)

    (* the procedure that receives declare_param *)
    decl_proc   : LProc := NIL;

    stack       : REF ARRAY OF Operand;
    sp          := 0;

    (* the call being built (calls do not nest) *)
    call_proc   : LProc := NIL;
    call_args   : TEXT := "";
    call_n      := 0;

    (* the initializer being built *)
    init_target : LVar := NIL;
    init_types  : TextWr.T;
    init_vals   : TextWr.T;
    init_pos    := 0;
    init_n      := 0;
  OVERRIDES
    next_label := next_label;
    set_error_handler := set_error_handler;
    begin_unit := begin_unit;
    end_unit := end_unit;
    import_unit := import_unit;
    export_unit := export_unit;
    set_source_file := set_source_file;
    set_source_line := set_source_line;
    declare_typename := declare_typename;
    declare_array := declare_array;
    declare_open_array := declare_open_array;
    declare_enum := declare_enum;
    declare_enum_elt := declare_enum_elt;
    declare_packed := declare_packed;
    declare_record := declare_record;
    declare_field := declare_field;
    declare_set := declare_set;
    declare_subrange := declare_subrange;
    declare_pointer := declare_pointer;
    declare_indirect := declare_indirect;
    declare_proctype := declare_proctype;
    declare_formal := declare_formal;
    declare_raises := declare_raises;
    declare_object := declare_object;
    declare_method := declare_method;
    declare_opaque := declare_opaque;
    reveal_opaque := reveal_opaque;
    declare_exception := declare_exception;
    widechar_size := widechar_size;
    set_runtime_proc := set_runtime_proc;
    import_global := import_global;
    declare_segment := declare_segment;
    bind_segment := bind_segment;
    declare_global := declare_global;
    declare_constant := declare_constant;
    declare_local := declare_local;
    declare_param := declare_param;
    declare_temp := declare_temp;
    free_temp := free_temp;
    begin_init := begin_init;
    end_init := end_init;
    init_int := init_int;
    init_proc := init_proc;
    init_var := init_var;
    init_chars := init_chars;
    import_procedure := import_procedure;
    declare_procedure := declare_procedure;
    begin_procedure := begin_procedure;
    end_procedure := end_procedure;
    begin_block := begin_block;
    end_block := end_block;
    note_procedure_origin := note_procedure_origin;
    set_label := set_label;
    jump := jump;
    if_true := if_true;
    if_false := if_false;
    exit_proc := exit_proc;
    load := load;
    store := store;
    load_address := load_address;
    load_nil := load_nil;
    load_integer := load_integer;
    pop := pop;
    start_call_direct := start_call_direct;
    pop_param := pop_param;
    call_direct := call_direct;
    load_procedure := load_procedure;
    comment := comment;
  END;

(*------------------------------------------------------------ targets ---*)

PROCEDURE TargetTriple (): TEXT =
  BEGIN
    IF Text.Equal (Target.System_name, "AMD64_LINUX") THEN
      RETURN "x86_64-unknown-linux-gnu";
    END;
    RETURN NIL;
  END TargetTriple;

PROCEDURE DataLayout (): TEXT =
  BEGIN
    IF Text.Equal (Target.System_name, "AMD64_LINUX") THEN
      (* From clang 22; LLVM 18 and later accept it. *)
      RETURN "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128"
               & "-f80:128-n8:16:32:64-S128";
    END;
    RETURN NIL;
  END DataLayout;

(*--------------------------------------------------------- utilities ---*)

PROCEDURE New (wr: Wr.T): M3CG.T =
  VAR u := NEW (U, wr := wr);
  BEGIN
    u.globals := TextWr.New ();
    u.funcs := TextWr.New ();
    u.stack := NEW (REF ARRAY OF Operand, 32);
    RETURN u;
  END New;

PROCEDURE Fatal (u: U; msg: TEXT) =
  BEGIN
    msg := "m3llvmir: " & msg;
    IF u.source_file # NIL THEN
      msg := msg & " (" & u.source_file & ", line "
               & Fmt.Int (u.source_line) & ")";
    END;
    Wr.PutText (Stdio.stderr, msg & Wr.EOL);
    Wr.Flush (Stdio.stderr);
    <*ASSERT FALSE*>
  END Fatal;

PROCEDURE IsInt (t: Type): BOOLEAN =
  BEGIN
    RETURN Type.Word8 <= t AND t <= Type.Int64;
  END IsInt;

PROCEDURE IsSigned (t: Type): BOOLEAN =
  BEGIN
    RETURN t = Type.Int8 OR t = Type.Int16 OR t = Type.Int32
           OR t = Type.Int64;
  END IsSigned;

PROCEDURE TypeBytes (t: Type): INTEGER =
  BEGIN
    CASE t OF
    | Type.Word8, Type.Int8   => RETURN 1;
    | Type.Word16, Type.Int16 => RETURN 2;
    | Type.Word32, Type.Int32 => RETURN 4;
    | Type.Word64, Type.Int64 => RETURN 8;
    | Type.Reel               => RETURN 4;
    | Type.LReel              => RETURN 8;
    | Type.XReel              => RETURN Target.Extended.bytes;
    | Type.Addr               => RETURN Target.Address.bytes;
    | Type.Struct, Type.Void  => RETURN 0;
    END;
  END TypeBytes;

PROCEDURE LType (t: Type): TEXT =
  BEGIN
    CASE t OF
    | Type.Word8, Type.Int8   => RETURN "i8";
    | Type.Word16, Type.Int16 => RETURN "i16";
    | Type.Word32, Type.Int32 => RETURN "i32";
    | Type.Word64, Type.Int64 => RETURN "i64";
    | Type.Reel               => RETURN "float";
    | Type.LReel              => RETURN "double";
    | Type.XReel =>
        IF Target.Extended.size = 128 THEN RETURN "fp128" END;
        RETURN "double";
    | Type.Addr, Type.Struct  => RETURN "ptr";
    | Type.Void               => RETURN "void";
    END;
  END LType;

PROCEDURE ExtAttr (t: Type): TEXT =
  (* The extension attribute the C ABI wants for small integers. *)
  BEGIN
    CASE t OF
    | Type.Int8, Type.Int16   => RETURN " signext";
    | Type.Word8, Type.Word16 => RETURN " zeroext";
    ELSE RETURN "";
    END;
  END ExtAttr;

PROCEDURE StackType (t: Type): ZType =
  (* The type a value of type "t" has on the M3CG stack. *)
  BEGIN
    CASE t OF
    | Type.Int8, Type.Int16   => RETURN Type.Int32;
    | Type.Word8, Type.Word16 => RETURN Type.Word32;
    | Type.Struct, Type.Void  => RETURN Type.Addr;
    ELSE RETURN t;
    END;
  END StackType;

PROCEDURE IntBits (t: Type): INTEGER =
  BEGIN
    RETURN 8 * TypeBytes (t);
  END IntBits;

PROCEDURE AlignAt (align: Alignment; offset: INTEGER; t: Type): INTEGER =
  (* The alignment of a "t" at "offset" bytes into something aligned to
     "align" bytes. *)
  VAR a := MAX (align, 1);
  BEGIN
    WHILE a > 1 AND offset MOD a # 0 DO a := a DIV 2 END;
    IF TypeBytes (t) > 0 THEN a := MIN (a, TypeBytes (t)) END;
    RETURN a;
  END AlignAt;

PROCEDURE IsIdentChar (c: CHAR): BOOLEAN =
  BEGIN
    RETURN ('a' <= c AND c <= 'z') OR ('A' <= c AND c <= 'Z')
           OR ('0' <= c AND c <= '9')
           OR c = '_' OR c = '.' OR c = '$' OR c = '-';
  END IsIdentChar;

PROCEDURE Hex2 (n: INTEGER): TEXT =
  BEGIN
    RETURN Fmt.Pad (Fmt.Int (n, 16), 2, '0');
  END Hex2;

PROCEDURE Escape (t: TEXT): TEXT =
  (* The body of an LLVM string literal: printable characters except
     '"' and '\\' as themselves, everything else as "\\XX". *)
  VAR wr := TextWr.New ();  c: CHAR;
  BEGIN
    FOR i := 0 TO Text.Length (t) - 1 DO
      c := Text.GetChar (t, i);
      IF ' ' <= c AND c <= '~' AND c # '"' AND c # '\\' THEN
        Wr.PutChar (wr, c);
      ELSE
        Wr.PutText (wr, "\\" & Hex2 (ORD (c)));
      END;
    END;
    RETURN TextWr.ToText (wr);
  END Escape;

PROCEDURE GlobalName (name: Name): TEXT =
  (* "@name", quoted if "name" contains unusual characters. *)
  VAR t := M3ID.ToText (name);  plain := Text.Length (t) > 0;
  BEGIN
    FOR i := 0 TO Text.Length (t) - 1 DO
      IF NOT IsIdentChar (Text.GetChar (t, i)) THEN plain := FALSE END;
    END;
    IF plain AND NOT ('0' <= Text.GetChar (t, 0)
                      AND Text.GetChar (t, 0) <= '9') THEN
      RETURN "@" & t;
    END;
    RETURN "@\"" & Escape (t) & "\"";
  END GlobalName;

PROCEDURE IntText (READONLY i: Target.Int): TEXT =
  BEGIN
    RETURN TInt.ToText (i);
  END IntText;

(*---------------------------------------------- instructions and stack ---*)

PROCEDURE NewTemp (u: U): TEXT =
  BEGIN
    INC (u.next_tmp);
    RETURN "%t." & Fmt.Int (u.next_tmp - 1);
  END NewTemp;

PROCEDURE NewBlock (u: U; prefix: TEXT): TEXT =
  BEGIN
    INC (u.next_block);
    RETURN prefix & Fmt.Int (u.next_block - 1);
  END NewBlock;

PROCEDURE StartBlock (u: U; name: TEXT) =
  BEGIN
    Wr.PutText (u.body, name & ":" & Wr.EOL);
    u.terminated := FALSE;
  END StartBlock;

PROCEDURE Emit (u: U; instr: TEXT) =
  BEGIN
    IF u.cur_proc = NIL THEN
      Fatal (u, "instruction outside a procedure: " & instr);
    END;
    IF u.terminated THEN StartBlock (u, NewBlock (u, "dead.")) END;
    Wr.PutText (u.body, "  " & instr & Wr.EOL);
  END Emit;

PROCEDURE EmitTerm (u: U; instr: TEXT) =
  BEGIN
    Emit (u, instr);
    u.terminated := TRUE;
  END EmitTerm;

PROCEDURE Push (u: U; type: ZType; val: TEXT) =
  BEGIN
    IF u.sp > LAST (u.stack^) THEN
      VAR new := NEW (REF ARRAY OF Operand, 2 * NUMBER (u.stack^)); BEGIN
        SUBARRAY (new^, 0, NUMBER (u.stack^)) := u.stack^;
        u.stack := new;
      END;
    END;
    u.stack[u.sp] := Operand {type, val};
    INC (u.sp);
  END Push;

PROCEDURE Pop (u: U): Operand =
  BEGIN
    IF u.sp <= 0 THEN Fatal (u, "M3CG stack underflow") END;
    DEC (u.sp);
    RETURN u.stack[u.sp];
  END Pop;

PROCEDURE Cvt (u: U; val: TEXT; from, to: Type): TEXT =
  (* Convert "val" from type "from" to type "to", emitting an
     instruction if the LLVM types differ. *)
  VAR fl := LType (from);  tl := LType (to);  op, t: TEXT;
  BEGIN
    IF Text.Equal (fl, tl) THEN RETURN val END;
    IF IsInt (from) AND IsInt (to) THEN
      IF IntBits (to) > IntBits (from) THEN
        IF IsSigned (from) THEN op := "sext" ELSE op := "zext" END;
      ELSE
        op := "trunc";
      END;
    ELSIF IsInt (from) AND to = Type.Addr THEN
      op := "inttoptr";
    ELSIF from = Type.Addr AND IsInt (to) THEN
      op := "ptrtoint";
    ELSE
      Fatal (u, "unsupported conversion " & fl & " to " & tl);
    END;
    t := NewTemp (u);
    Emit (u, t & " = " & op & " " & fl & " " & val & " to " & tl);
    RETURN t;
  END Cvt;

PROCEDURE AddrOf (u: U; var: Var; offset: ByteOffset): TEXT =
  VAR v := NARROW (var, LVar);  t: TEXT;
  BEGIN
    v.used := TRUE;
    IF offset = 0 THEN RETURN v.name END;
    t := NewTemp (u);
    Emit (u, t & " = getelementptr i8, ptr " & v.name & ", i64 "
               & Fmt.Int (offset));
    RETURN t;
  END AddrOf;

(*------------------------------------------------- unit and no-ops ---*)

PROCEDURE next_label (u: U; n: INTEGER := 1): Label =
  BEGIN
    INC (u.n_labels, n);
    RETURN u.n_labels - n;
  END next_label;

PROCEDURE set_error_handler (u: U; p: M3CG_Ops.ErrorHandler) =
  BEGIN
    u.error := p;
  END set_error_handler;

PROCEDURE begin_unit (<*UNUSED*> u: U; <*UNUSED*> optimize: INTEGER) =
  BEGIN
  END begin_unit;

PROCEDURE end_unit (u: U) =
  VAR
    wr := u.wr;
    defined := NEW (TextRefTbl.Default).init ();
    seen := NEW (TextRefTbl.Default).init ();
    ref: REFANY;
    pl: ProcList;
    vl: VarList;
    triple := TargetTriple ();
    layout := DataLayout ();
  BEGIN
    IF u.source_file # NIL THEN
      Wr.PutText (wr, "source_filename = \"" & Escape (u.source_file)
                        & "\"" & Wr.EOL);
    END;
    IF layout # NIL THEN
      Wr.PutText (wr, "target datalayout = \"" & layout & "\"" & Wr.EOL);
    END;
    IF triple # NIL THEN
      Wr.PutText (wr, "target triple = \"" & triple & "\"" & Wr.EOL);
    END;
    Wr.PutText (wr, Wr.EOL);

    Wr.PutText (wr, TextWr.ToText (u.globals));

    (* Imported globals that are used. *)
    vl := u.imports;
    WHILE vl # NIL DO
      IF vl.v.used AND NOT seen.get (vl.v.name, ref) THEN
        EVAL seen.put (vl.v.name, vl.v);
        Wr.PutText (wr, vl.v.name & " = external global ["
                          & Fmt.Int (vl.v.size) & " x i8], align "
                          & Fmt.Int (MAX (vl.v.align, 1)) & Wr.EOL);
      END;
      vl := vl.next;
    END;
    Wr.PutText (wr, Wr.EOL);

    Wr.PutText (wr, TextWr.ToText (u.funcs));

    (* Declarations for procedures used but not defined here. *)
    pl := u.procs;
    WHILE pl # NIL DO
      IF pl.p.defined THEN EVAL defined.put (pl.p.name, pl.p) END;
      pl := pl.next;
    END;
    pl := u.procs;
    WHILE pl # NIL DO
      IF pl.p.used AND NOT pl.p.defined
        AND NOT defined.get (pl.p.name, ref)
        AND NOT seen.get (pl.p.name, ref) THEN
        EVAL seen.put (pl.p.name, pl.p);
        Wr.PutText (wr, "declare " & Signature (pl.p, FALSE) & Wr.EOL);
      END;
      pl := pl.next;
    END;
    Wr.PutText (wr, Wr.EOL);

    Wr.PutText (wr, "attributes #0 = { uwtable \"frame-pointer\"=\"all\" }"
                      & Wr.EOL);
    Wr.Flush (wr);
  END end_unit;

PROCEDURE import_unit (<*UNUSED*> u: U; <*UNUSED*> name: Name) =
  BEGIN
  END import_unit;

PROCEDURE export_unit (<*UNUSED*> u: U; <*UNUSED*> name: Name) =
  BEGIN
  END export_unit;

PROCEDURE set_source_file (u: U; file: TEXT) =
  BEGIN
    u.source_file := file;
  END set_source_file;

PROCEDURE set_source_line (u: U; line: INTEGER) =
  BEGIN
    u.source_line := line;
  END set_source_line;

(* Type declarations are for debug information, which this back end
   does not produce yet. *)

<*NOWARN*>PROCEDURE declare_typename(self: U; typeid: TypeUID; name: Name) = BEGIN END declare_typename;
<*NOWARN*>PROCEDURE declare_array(self: U; typeid, index_typeid, element_typeid: TypeUID; bit_size: BitSize; element_typename: Name) = BEGIN END declare_array;
<*NOWARN*>PROCEDURE declare_open_array(self: U; typeid, element_typeid: TypeUID; bit_size: BitSize; element_typename: Name) = BEGIN END declare_open_array;
<*NOWARN*>PROCEDURE declare_enum(self: U; typeid: TypeUID; n_elts: INTEGER; bit_size: BitSize) = BEGIN END declare_enum;
<*NOWARN*>PROCEDURE declare_enum_elt(self: U; name: Name) = BEGIN END declare_enum_elt;
<*NOWARN*>PROCEDURE declare_packed(self: U; typeid: TypeUID; bit_size: BitSize; base: TypeUID; base_typename: Name) = BEGIN END declare_packed;
<*NOWARN*>PROCEDURE declare_record(self: U; typeid: TypeUID; bit_size: BitSize; n_fields: INTEGER) = BEGIN END declare_record;
<*NOWARN*>PROCEDURE declare_field(self: U; name: Name; bit_offset: BitOffset; bit_size: BitSize; typeid: TypeUID; typename: Name) = BEGIN END declare_field;
<*NOWARN*>PROCEDURE declare_set(self: U; t, domain: TypeUID; bit_size: BitSize; domain_typename: Name) = BEGIN END declare_set;
<*NOWARN*>PROCEDURE declare_subrange(self: U; typeid, domain_typeid: TypeUID; READONLY min, max: Target.Int; bit_size: BitSize; domain_typename: Name) = BEGIN END declare_subrange;
<*NOWARN*>PROCEDURE declare_pointer(self: U; typeid, target_typeid: TypeUID; brand: TEXT; traced: BOOLEAN; target_typename: Name) = BEGIN END declare_pointer;
<*NOWARN*>PROCEDURE declare_indirect(self: U; typeid, target_typeid: TypeUID; target_typename: Name) = BEGIN END declare_indirect;
<*NOWARN*>PROCEDURE declare_proctype(self: U; typeid: TypeUID; n_formals: INTEGER; result: TypeUID; n_raises: INTEGER; callingConvention: CallingConvention; result_typename: Name) = BEGIN END declare_proctype;
<*NOWARN*>PROCEDURE declare_formal(self: U; name: Name; typeid: TypeUID; typename: Name) = BEGIN END declare_formal;
<*NOWARN*>PROCEDURE declare_raises(self: U; name: Name) = BEGIN END declare_raises;
<*NOWARN*>PROCEDURE declare_object(self: U; typeid, super_typeid: TypeUID; brand: TEXT; traced: BOOLEAN; n_fields, n_methods: INTEGER; field_size: BitSize; field_offset, method_offset : INTEGER; super_typename: Name) = BEGIN END declare_object;
<*NOWARN*>PROCEDURE declare_method(self: U; name: Name; signature: TypeUID) = BEGIN END declare_method;
<*NOWARN*>PROCEDURE declare_opaque(self: U; typeid, super_typeid: TypeUID) = BEGIN END declare_opaque;
<*NOWARN*>PROCEDURE reveal_opaque(self: U; lhs_typeid, rhs_typeid: TypeUID) = BEGIN END reveal_opaque;
<*NOWARN*>PROCEDURE declare_exception(self: U; name: Name; arg_typeid: TypeUID; raise_proc: BOOLEAN; base: Var; offset: INTEGER) = BEGIN END declare_exception;
<*NOWARN*>PROCEDURE widechar_size(self: U; size: INTEGER) = BEGIN END widechar_size;
<*NOWARN*>PROCEDURE set_runtime_proc(self: U; name: Name; proc: Proc) = BEGIN END set_runtime_proc;
<*NOWARN*>PROCEDURE free_temp(self: U; var: Var) = BEGIN END free_temp;
<*NOWARN*>PROCEDURE begin_block(self: U) = BEGIN END begin_block;
<*NOWARN*>PROCEDURE end_block(self: U) = BEGIN END end_block;
<*NOWARN*>PROCEDURE note_procedure_origin(self: U; proc: Proc) = BEGIN END note_procedure_origin;

PROCEDURE comment (u: U; a, b, c, d: TEXT := NIL) =
  VAR t := "";  wr: TextWr.T;  ch: CHAR;
  BEGIN
    IF a # NIL THEN t := t & a END;
    IF b # NIL THEN t := t & b END;
    IF c # NIL THEN t := t & c END;
    IF d # NIL THEN t := t & d END;
    wr := TextWr.New ();
    FOR i := 0 TO Text.Length (t) - 1 DO
      ch := Text.GetChar (t, i);
      IF ch < ' ' THEN ch := ' ' END;
      Wr.PutChar (wr, ch);
    END;
    t := "; " & TextWr.ToText (wr) & Wr.EOL;
    IF u.cur_proc # NIL
      THEN Wr.PutText (u.body, t);
      ELSE Wr.PutText (u.globals, t);
    END;
  END comment;

(*------------------------------------------------------------ globals ---*)

PROCEDURE NewVar (u: U; kind: VarKind; size: ByteSize; align: Alignment;
                  type: Type): LVar =
  VAR v := NEW (LVar, id := u.next_var, kind := kind, size := size,
                align := align, type := type);
  BEGIN
    INC (u.next_var);
    RETURN v;
  END NewVar;

PROCEDURE Linkage (exported: BOOLEAN): TEXT =
  BEGIN
    IF exported THEN RETURN "" END;
    RETURN "internal ";
  END Linkage;

PROCEDURE import_global (u: U; name: Name; byte_size: ByteSize;
                         alignment: Alignment; type: Type;
                         <*UNUSED*> typeid: TypeUID;
                         <*UNUSED*> typename: Name): Var =
  VAR v := NewVar (u, VarKind.Imported, byte_size, alignment, type);
  BEGIN
    v.name := GlobalName (name);
    u.imports := NEW (VarList, v := v, next := u.imports);
    RETURN v;
  END import_global;

PROCEDURE declare_segment (u: U; name: Name; <*UNUSED*> typeid: TypeUID;
                           <*UNUSED*> is_const: BOOLEAN): Var =
  VAR v := NewVar (u, VarKind.Global, 0, 1, Type.Struct);
  BEGIN
    IF name = M3ID.NoID
      THEN v.name := "@seg." & Fmt.Int (v.id);
      ELSE v.name := GlobalName (name);
    END;
    RETURN v;
  END declare_segment;

PROCEDURE BindGlobal (u: U; v: LVar; byte_size: ByteSize;
                      alignment: Alignment; type: Type;
                      exported, inited: BOOLEAN) =
  BEGIN
    v.size := byte_size;
    v.align := alignment;
    v.type := type;
    v.exported := exported;
    IF NOT inited THEN
      Wr.PutText (u.globals, v.name & " = " & Linkage (exported)
                               & "global [" & Fmt.Int (byte_size)
                               & " x i8] zeroinitializer, align "
                               & Fmt.Int (MAX (alignment, 1)) & Wr.EOL);
    END;
  END BindGlobal;

PROCEDURE bind_segment (u: U; segment: Var; byte_size: ByteSize;
                        alignment: Alignment; type: Type;
                        exported, inited: BOOLEAN) =
  BEGIN
    BindGlobal (u, NARROW (segment, LVar), byte_size, alignment, type,
                exported, inited);
  END bind_segment;

PROCEDURE declare_global (u: U; name: Name; byte_size: ByteSize;
                          alignment: Alignment; type: Type;
                          <*UNUSED*> typeid: TypeUID;
                          exported, inited: BOOLEAN;
                          <*UNUSED*> typename: Name): Var =
  VAR v := NewVar (u, VarKind.Global, 0, 1, type);
  BEGIN
    IF name = M3ID.NoID
      THEN v.name := "@global." & Fmt.Int (v.id);
      ELSE v.name := GlobalName (name);
    END;
    BindGlobal (u, v, byte_size, alignment, type, exported, inited);
    RETURN v;
  END declare_global;

PROCEDURE declare_constant (u: U; name: Name; byte_size: ByteSize;
                            alignment: Alignment; type: Type;
                            typeid: TypeUID; exported, inited: BOOLEAN;
                            typename: Name): Var =
  BEGIN
    RETURN declare_global (u, name, byte_size, alignment, type, typeid,
                           exported, inited, typename);
  END declare_constant;

(*------------------------------------------------------- initializers ---*)

PROCEDURE begin_init (u: U; var: Var) =
  BEGIN
    u.init_target := NARROW (var, LVar);
    u.init_types := TextWr.New ();
    u.init_vals := TextWr.New ();
    u.init_pos := 0;
    u.init_n := 0;
  END begin_init;

PROCEDURE InitField (u: U; offset: ByteOffset; type, val: TEXT;
                     size: INTEGER) =
  BEGIN
    IF u.init_target = NIL THEN Fatal (u, "initializer outside begin_init") END;
    IF offset < u.init_pos THEN
      Fatal (u, "overlapping or out-of-order initializer at offset "
                  & Fmt.Int (offset));
    END;
    IF offset > u.init_pos THEN
      VAR n := Fmt.Int (offset - u.init_pos); BEGIN
        u.init_pos := offset;
        InitField (u, offset, "[" & n & " x i8]", "zeroinitializer", 0);
      END;
    END;
    IF u.init_n > 0 THEN
      Wr.PutText (u.init_types, ", ");
      Wr.PutText (u.init_vals, ", ");
    END;
    Wr.PutText (u.init_types, type);
    Wr.PutText (u.init_vals, type & " " & val);
    INC (u.init_n);
    INC (u.init_pos, size);
  END InitField;

PROCEDURE end_init (u: U; var: Var) =
  VAR v := NARROW (var, LVar);
  BEGIN
    IF v # u.init_target THEN Fatal (u, "end_init does not match begin_init") END;
    IF u.init_pos > v.size THEN
      Fatal (u, "initializer is larger than " & v.name);
    ELSIF u.init_pos < v.size THEN
      InitField (u, u.init_pos, "[" & Fmt.Int (v.size - u.init_pos)
                                  & " x i8]", "zeroinitializer",
                 v.size - u.init_pos);
    END;
    Wr.PutText (u.globals, v.name & " = " & Linkage (v.exported)
                             & "global <{ " & TextWr.ToText (u.init_types)
                             & " }> <{ " & TextWr.ToText (u.init_vals)
                             & " }>, align " & Fmt.Int (MAX (v.align, 1))
                             & Wr.EOL);
    u.init_target := NIL;
  END end_init;

PROCEDURE init_int (u: U; byte_offset: ByteOffset;
                    READONLY value: Target.Int; type: Type) =
  BEGIN
    InitField (u, byte_offset, LType (type), IntText (value),
               TypeBytes (type));
  END init_int;

PROCEDURE init_proc (u: U; byte_offset: ByteOffset; value: Proc) =
  VAR p := NARROW (value, LProc);
  BEGIN
    p.used := TRUE;
    InitField (u, byte_offset, "ptr", p.name, Target.Address.bytes);
  END init_proc;

PROCEDURE init_var (u: U; byte_offset: ByteOffset; value: Var;
                    bias: ByteOffset) =
  VAR v := NARROW (value, LVar);  val := v.name;
  BEGIN
    v.used := TRUE;
    IF bias # 0 THEN
      val := "getelementptr (i8, ptr " & v.name & ", i64 "
               & Fmt.Int (bias) & ")";
    END;
    InitField (u, byte_offset, "ptr", val, Target.Address.bytes);
  END init_var;

PROCEDURE init_chars (u: U; byte_offset: ByteOffset; value: TEXT) =
  VAR n := Text.Length (value);
  BEGIN
    InitField (u, byte_offset, "[" & Fmt.Int (n) & " x i8]",
               "c\"" & Escape (value) & "\"", n);
  END init_chars;

(*--------------------------------------------------------- procedures ---*)

PROCEDURE NewProc (u: U; name: Name; n_params: INTEGER;
                   return: Type): LProc =
  VAR p := NEW (LProc, id := u.next_proc, name := GlobalName (name),
                return := return);
  BEGIN
    INC (u.next_proc);
    p.params := NEW (REF ARRAY OF LVar, MAX (n_params, 0));
    u.procs := NEW (ProcList, p := p, next := u.procs);
    u.decl_proc := p;
    RETURN p;
  END NewProc;

PROCEDURE import_procedure (u: U; name: Name; n_params: INTEGER;
                            ret_type: Type;
                            <*UNUSED*> callingConvention: CallingConvention;
                            <*UNUSED*> return_typeid: TypeUID;
                            <*UNUSED*> return_typename: Name): Proc =
  VAR p := NewProc (u, name, n_params, ret_type);
  BEGIN
    p.imported := TRUE;
    RETURN p;
  END import_procedure;

PROCEDURE declare_procedure (u: U; name: Name; n_params: INTEGER;
                             return_type: Type; level: INTEGER;
                             <*UNUSED*> callingConvention: CallingConvention;
                             exported: BOOLEAN; parent: Proc;
                             <*UNUSED*> return_typeid: TypeUID;
                             <*UNUSED*> return_typename: Name): Proc =
  VAR p: LProc;
  BEGIN
    IF parent # NIL OR level # 0 THEN
      Fatal (u, "nested procedures are not supported yet: "
                  & M3ID.ToText (name));
    END;
    p := NewProc (u, name, n_params, return_type);
    p.exported := exported;
    RETURN p;
  END declare_procedure;

PROCEDURE Signature (p: LProc; names: BOOLEAN): TEXT =
  (* "<ret> @name(<params>)", with parameter names if "names". *)
  VAR res, attr: TEXT;  v: LVar;
  BEGIN
    attr := ExtAttr (p.return);
    IF Text.Length (attr) > 0 THEN
      attr := Text.Sub (attr, 1) & " ";   (* drop the leading space *)
    END;
    res := attr & LType (p.return) & " " & p.name & "(";
    FOR i := 0 TO p.n_declared - 1 DO
      v := p.params[i];
      IF i > 0 THEN res := res & ", " END;
      res := res & LType (v.type) & ExtAttr (v.type);
      IF names THEN res := res & " %p." & Fmt.Int (v.id) END;
    END;
    RETURN res & ")";
  END Signature;

PROCEDURE Alloca (u: U; v: LVar) =
  BEGIN
    Wr.PutText (u.allocas, "  " & v.name & " = alloca ["
                             & Fmt.Int (v.size) & " x i8], align "
                             & Fmt.Int (MAX (v.align, 1)) & Wr.EOL);
  END Alloca;

PROCEDURE NewLocal (u: U; kind: VarKind; byte_size: ByteSize;
                    alignment: Alignment; type: Type): LVar =
  VAR v := NewVar (u, kind, byte_size, alignment, type);
  BEGIN
    v.name := "%v." & Fmt.Int (v.id);
    RETURN v;
  END NewLocal;

PROCEDURE declare_local (u: U; <*UNUSED*> name: Name; byte_size: ByteSize;
                         alignment: Alignment; type: Type;
                         <*UNUSED*> typeid: TypeUID;
                         in_memory, up_level: BOOLEAN;
                         <*UNUSED*> frequency: Frequency;
                         <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Local, byte_size, alignment, type);
  BEGIN
    EVAL in_memory;
    IF up_level THEN Fatal (u, "up-level locals are not supported yet") END;
    IF u.cur_proc # NIL THEN
      Alloca (u, v);
    ELSIF u.decl_proc # NIL THEN
      u.decl_proc.locals := NEW (VarList, v := v,
                                 next := u.decl_proc.locals);
    ELSE
      Fatal (u, "declare_local outside a procedure");
    END;
    RETURN v;
  END declare_local;

PROCEDURE declare_param (u: U; <*UNUSED*> name: Name; byte_size: ByteSize;
                         alignment: Alignment; type: Type;
                         <*UNUSED*> typeid: TypeUID;
                         <*UNUSED*> in_memory: BOOLEAN; up_level: BOOLEAN;
                         <*UNUSED*> frequency: Frequency;
                         <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Param, byte_size, alignment, type);
      p := u.decl_proc;
  BEGIN
    IF p = NIL THEN Fatal (u, "declare_param without a procedure") END;
    IF type = Type.Struct THEN
      Fatal (u, "structure parameters are not supported yet");
    END;
    IF up_level AND NOT p.imported THEN
      Fatal (u, "up-level parameters are not supported yet");
    END;
    IF p.n_declared < NUMBER (p.params^) THEN
      p.params[p.n_declared] := v;
      INC (p.n_declared);
    ELSE
      Fatal (u, "too many parameters for " & p.name);
    END;
    RETURN v;
  END declare_param;

PROCEDURE declare_temp (u: U; byte_size: ByteSize; alignment: Alignment;
                        type: Type; <*UNUSED*> in_memory: BOOLEAN;
                        <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Local, byte_size, alignment, type);
  BEGIN
    IF u.cur_proc = NIL THEN Fatal (u, "declare_temp outside a procedure") END;
    Alloca (u, v);
    RETURN v;
  END declare_temp;

PROCEDURE begin_procedure (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);  v: LVar;  l: VarList;
  BEGIN
    IF u.cur_proc # NIL THEN
      Fatal (u, "begin_procedure inside " & u.cur_proc.name);
    END;
    u.cur_proc := p;
    p.defined := TRUE;
    u.allocas := TextWr.New ();
    u.body := TextWr.New ();
    u.terminated := FALSE;
    u.sp := 0;
    FOR i := 0 TO p.n_declared - 1 DO
      v := p.params[i];
      Alloca (u, v);
      Wr.PutText (u.allocas, "  store " & LType (v.type) & " %p."
                               & Fmt.Int (v.id) & ", ptr " & v.name
                               & ", align " & Fmt.Int (MAX (v.align, 1))
                               & Wr.EOL);
    END;
    l := p.locals;
    WHILE l # NIL DO Alloca (u, l.v); l := l.next END;
  END begin_procedure;

PROCEDURE end_procedure (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);
  BEGIN
    IF p # u.cur_proc THEN Fatal (u, "end_procedure does not match") END;
    IF NOT u.terminated THEN
      IF p.return = Type.Void
        THEN EmitTerm (u, "ret void");
        ELSE EmitTerm (u, "unreachable");
      END;
    END;
    Wr.PutText (u.funcs, "define " & Linkage (p.exported)
                           & Signature (p, TRUE) & " #0 {" & Wr.EOL
                           & "entry:" & Wr.EOL
                           & TextWr.ToText (u.allocas)
                           & TextWr.ToText (u.body)
                           & "}" & Wr.EOL & Wr.EOL);
    u.cur_proc := NIL;
    u.allocas := NIL;
    u.body := NIL;
  END end_procedure;

(*------------------------------------------------------ control flow ---*)

PROCEDURE LabelName (l: Label): TEXT =
  BEGIN
    RETURN "L." & Fmt.Int (l);
  END LabelName;

PROCEDURE set_label (u: U; label: Label; <*UNUSED*> barrier: BOOLEAN) =
  BEGIN
    IF NOT u.terminated THEN
      EmitTerm (u, "br label %" & LabelName (label));
    END;
    StartBlock (u, LabelName (label));
  END set_label;

PROCEDURE jump (u: U; label: Label) =
  BEGIN
    EmitTerm (u, "br label %" & LabelName (label));
  END jump;

PROCEDURE CondBranch (u: U; type: IType; label: Label; cmp: TEXT) =
  VAR x := Pop (u);  c := NewTemp (u);  next := NewBlock (u, "B.");
  BEGIN
    Emit (u, c & " = icmp " & cmp & " " & LType (type) & " "
               & Cvt (u, x.val, x.type, type) & ", 0");
    EmitTerm (u, "br i1 " & c & ", label %" & LabelName (label)
                   & ", label %" & next);
    StartBlock (u, next);
  END CondBranch;

PROCEDURE if_true (u: U; type: IType; label: Label;
                   <*UNUSED*> frequency: Frequency) =
  BEGIN
    CondBranch (u, type, label, "ne");
  END if_true;

PROCEDURE if_false (u: U; type: IType; label: Label;
                    <*UNUSED*> frequency: Frequency) =
  BEGIN
    CondBranch (u, type, label, "eq");
  END if_false;

PROCEDURE exit_proc (u: U; type: Type) =
  VAR p := u.cur_proc;  x: Operand;
  BEGIN
    IF type = Type.Void THEN
      EmitTerm (u, "ret void");
    ELSE
      x := Pop (u);
      EmitTerm (u, "ret " & LType (p.return) & " "
                     & Cvt (u, x.val, x.type, p.return));
    END;
  END exit_proc;

(*----------------------------------------------- loads, stores, values ---*)

PROCEDURE load (u: U; var: Var; byte_offset: ByteOffset; mtype: MType;
                ztype: ZType) =
  VAR v := NARROW (var, LVar);  a := AddrOf (u, var, byte_offset);
      t := NewTemp (u);
  BEGIN
    Emit (u, t & " = load " & LType (mtype) & ", ptr " & a & ", align "
               & Fmt.Int (AlignAt (v.align, byte_offset, mtype)));
    Push (u, ztype, Cvt (u, t, mtype, ztype));
  END load;

PROCEDURE store (u: U; var: Var; byte_offset: ByteOffset; ztype: ZType;
                 mtype: MType) =
  VAR v := NARROW (var, LVar);  x := Pop (u);  val, a: TEXT;
  BEGIN
    val := Cvt (u, Cvt (u, x.val, x.type, ztype), ztype, mtype);
    a := AddrOf (u, var, byte_offset);
    Emit (u, "store " & LType (mtype) & " " & val & ", ptr " & a
               & ", align "
               & Fmt.Int (AlignAt (v.align, byte_offset, mtype)));
  END store;

PROCEDURE load_address (u: U; var: Var; byte_offset: ByteOffset) =
  BEGIN
    Push (u, Type.Addr, AddrOf (u, var, byte_offset));
  END load_address;

PROCEDURE load_nil (u: U) =
  BEGIN
    Push (u, Type.Addr, "null");
  END load_nil;

PROCEDURE load_integer (u: U; type: IType; READONLY int: Target.Int) =
  BEGIN
    Push (u, type, IntText (int));
  END load_integer;

PROCEDURE pop (u: U; <*UNUSED*> type: Type) =
  BEGIN
    EVAL Pop (u);
  END pop;

(*-------------------------------------------------------------- calls ---*)

PROCEDURE start_call_direct (u: U; proc: Proc; level: INTEGER;
                             <*UNUSED*> type: Type) =
  BEGIN
    IF level # 0 THEN
      Fatal (u, "calls to nested procedures are not supported yet");
    END;
    u.call_proc := NARROW (proc, LProc);
    u.call_args := "";
    u.call_n := 0;
  END start_call_direct;

PROCEDURE pop_param (u: U; type: MType) =
  VAR p := u.call_proc;  x := Pop (u);  ptype: Type := type;
  BEGIN
    IF p = NIL THEN Fatal (u, "pop_param outside a call") END;
    IF u.call_n < p.n_declared THEN ptype := p.params[u.call_n].type END;
    IF u.call_n > 0 THEN u.call_args := u.call_args & ", " END;
    u.call_args := u.call_args & LType (ptype) & ExtAttr (ptype) & " "
                     & Cvt (u, x.val, x.type, ptype);
    INC (u.call_n);
  END pop_param;

PROCEDURE call_direct (u: U; proc: Proc; type: Type) =
  VAR p := NARROW (proc, LProc);  r: TEXT;  call: TEXT;
  BEGIN
    p.used := TRUE;
    call := "call " & LType (p.return) & " " & p.name & "("
              & u.call_args & ")";
    IF type = Type.Void THEN
      Emit (u, call);
    ELSE
      r := NewTemp (u);
      Emit (u, r & " = " & call);
      Push (u, StackType (type), Cvt (u, r, p.return, StackType (type)));
    END;
    u.call_proc := NIL;
    u.call_args := "";
  END call_direct;

PROCEDURE load_procedure (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);
  BEGIN
    p.used := TRUE;
    Push (u, Type.Addr, p.name);
  END load_procedure;

BEGIN
END M3LLVMIR.
