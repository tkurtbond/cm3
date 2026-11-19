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

IMPORT Wr, TextWr, Text, Fmt, Stdio, Thread, TextRefTbl, Word;
IMPORT M3CG, M3CG_Ops, M3CG_AssertFalse, M3ID, Target, TInt, TFloat;
IMPORT M3LLVMIRDebug;  (* Phase 5 *)
FROM M3CG IMPORT Name, ByteOffset, TypeUID, CallingConvention;
FROM M3CG IMPORT BitSize, ByteSize, Alignment, Frequency;
FROM M3CG IMPORT Var, Proc, Label, BitOffset;
FROM M3CG IMPORT Type, ZType, IType, MType, RType, AType;
FROM M3CG IMPORT Sign, CompareOp, ConvertOp, RuntimeError;
FROM M3CG IMPORT MemoryOrder, AtomicOp;  (* Phase 3 *)

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
    owner    : LProc     := NIL;   (* for locals and parameters *)
    up_level : BOOLEAN   := FALSE; (* lives in owner's frame *)
    frame_off: INTEGER   := 0;
    (* debug information (Phase 5) *)
    m3name   : TEXT      := NIL;   (* NIL: no debug information *)
    typeid   : TypeUID   := 0;
    line     : INTEGER   := 0;
    scope    : TEXT      := NIL;  (* its DILexicalBlock; NIL: the procedure *)
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
    level      : INTEGER := 0;    (* static nesting level *)
    (* The frame holds the up-level variables and, at offset 0, the
       static link (a pointer to the parent's frame). *)
    frame_size : INTEGER := 0;
    frame_align: INTEGER := 0;
    frame_used : BOOLEAN := FALSE;
    returns_twice : BOOLEAN := FALSE;  (* setjmp *)
    calls_setjmp  : BOOLEAN := FALSE;
    has_eh        : BOOLEAN := FALSE;  (* has a landing pad (Phase 7) *)
    (* debug information (Phase 5) *)
    m3name     : TEXT := NIL;     (* the symbol, unquoted *)
    ret_typeid : TypeUID := 0;
    dbg_sp     : TEXT := NIL;     (* its DISubprogram, if any *)
    dbg_file   : TEXT := NIL;     (* its DIFile *)
    dbg_line   : INTEGER := 0;
    dbg_vars   : VarList := NIL;  (* named locals and parameters *)
    dbg_blocks : TextList := NIL; (* the open blocks, innermost first;
                                     NIL entries have no DILexicalBlock *)
  END;

  TextList = REF RECORD t: TEXT;  next: TextList END;

  (* A try region (Phase 7, ex_stack): every call in it unwinds to its
     landing pad "lpad". *)
  TryList  = REF RECORD
    lpad    : TEXT;
    handler : Label := M3CG.No_label;  (* from invoke_*, if any *)
    next    : TryList;
  END;

  VarList  = REF RECORD v: LVar;  next: VarList  END;
  ProcList = REF RECORD p: LProc; next: ProcList END;
  DeclList = REF RECORD name, text: TEXT; next: DeclList END;

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
    decls       : DeclList := NIL; (* extra "declare" lines *)
    helpers     : DeclList := NIL; (* internal helper functions *)
    module_data : LVar := NIL;     (* passed to RTHooks.ReportFault *)

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
    try_open    : TryList := NIL;  (* open try regions, innermost first *)
    try_last    : TryList := NIL;  (* the region end_try closed last *)

    (* the procedure that receives declare_param *)
    decl_proc   : LProc := NIL;

    stack       : REF ARRAY OF Operand;
    sp          := 0;

    (* the call being built (calls do not nest) *)
    call_proc   : LProc := NIL;   (* NIL for indirect calls *)
    call_args   : TEXT := "";
    call_n      := 0;
    in_call     := FALSE;
    call_aborted:= FALSE;  (* abort occurred among the arguments *)
    call_sl     : TEXT := NIL;  (* static link for an indirect call *)
    call_last   : TEXT := NIL;  (* the last argument, as an i64 *)

    (* the initializer being built *)
    init_target : LVar := NIL;
    init_types  : TextWr.T;
    init_vals   : TextWr.T;
    init_pos    := 0;
    init_n      := 0;

    (* debug information (Phase 5); NIL if not wanted *)
    dbg         : M3LLVMIRDebug.T := NIL;
    unit_file   : TEXT := NIL;     (* the first source file *)
    loc_line    := -1;             (* the cached location of Emit *)
    loc_file    : TEXT := NIL;
    loc         : TEXT := NIL;     (* ", !dbg !N" *)
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
    (* Phase 2 *)
    init_float := init_float;
    if_compare := if_compare;
    case_jump := case_jump;
    load_indirect := load_indirect;
    store_indirect := store_indirect;
    load_float := load_float;
    compare := compare;
    add := add;
    subtract := subtract;
    multiply := multiply;
    divide := divide;
    negate := negate;
    abs := abs;
    max := max;
    min := min;
    cvt_int := cvt_int;
    cvt_float := cvt_float;
    div := div;
    mod := mod;
    set_union := set_union;
    set_difference := set_difference;
    set_intersection := set_intersection;
    set_sym_difference := set_sym_difference;
    set_member := set_member;
    set_compare := set_compare;
    set_range := set_range;
    set_singleton := set_singleton;
    not := not;
    and := and;
    or := or;
    xor := xor;
    shift := shift;
    shift_left := shift_left;
    shift_right := shift_right;
    rotate := rotate;
    rotate_left := rotate_left;
    rotate_right := rotate_right;
    widen := widen;
    chop := chop;
    extract := extract;
    extract_n := extract_n;
    extract_mn := extract_mn;
    insert := insert;
    insert_n := insert_n;
    insert_mn := insert_mn;
    swap := swap;
    copy_n := copy_n;
    copy := copy;
    zero_n := zero_n;
    zero := zero;
    loophole := loophole;
    abort := abort;
    check_nil := check_nil;
    check_lo := check_lo;
    check_hi := check_hi;
    check_range := check_range;
    check_index := check_index;
    check_eq := check_eq;
    add_offset := add_offset;
    index_address := index_address;
    start_call_indirect := start_call_indirect;
    call_indirect := call_indirect;
    pop_struct := pop_struct;
    pop_static_link := pop_static_link;
    load_static_link := load_static_link;
    (* Phase 3 *)
    init_label := init_label;
    init_offset := init_offset;
    store_ordered := store_ordered;
    load_ordered := load_ordered;
    exchange := exchange;
    compare_exchange := compare_exchange;
    fence := fence;
    fetch_and_op := fetch_and_op;
    (* Phase 7: zero-cost exceptions (ex_stack) *)
    start_try := start_try;
    end_try := end_try;
    invoke_direct := invoke_direct;
    invoke_indirect := invoke_indirect;
    landing_pad := landing_pad;
  END;

(*------------------------------------------------------------ targets ---*)

PROCEDURE TargetTriple (): TEXT =
  BEGIN
    IF Text.Equal (Target.System_name, "AMD64_LINUX") THEN
      RETURN "x86_64-unknown-linux-gnu";
    ELSIF Text.Equal (Target.System_name, "ARM64_LINUX") THEN
      RETURN "aarch64-unknown-linux-gnu";
    ELSIF Text.Equal (Target.System_name, "AMD64_DARWIN") THEN
      RETURN "x86_64-apple-macosx";
    ELSIF Text.Equal (Target.System_name, "ARM64_DARWIN") THEN
      RETURN "arm64-apple-macosx";
    END;
    RETURN NIL;
  END TargetTriple;

PROCEDURE DataLayout (): TEXT =
  BEGIN
    IF Text.Equal (Target.System_name, "AMD64_LINUX") THEN
      (* From clang 22; LLVM 18 and later accept it. *)
      RETURN "e-m:e-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128"
               & "-f80:128-n8:16:32:64-S128";
    ELSIF Text.Equal (Target.System_name, "ARM64_LINUX") THEN
      (* From clang 22; clang 19 (whose own string lacks the p27x
         address spaces) accepts it too. *)
      RETURN "e-m:e-p270:32:32-p271:32:32-p272:64:64-i8:8:32-i16:16:32"
               & "-i64:64-i128:128-n32:64-S128-Fn32";
    ELSIF Text.Equal (Target.System_name, "AMD64_DARWIN") THEN
      (* Mach-O ("m:o"); from clang 22. *)
      RETURN "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128"
               & "-f80:128-n8:16:32:64-S128";
    ELSIF Text.Equal (Target.System_name, "ARM64_DARWIN") THEN
      RETURN "e-m:o-p270:32:32-p271:32:32-p272:64:64-i64:64-i128:128"
               & "-n32:64-S128-Fn32";
    END;
    RETURN NIL;
  END DataLayout;

(*--------------------------------------------------------- utilities ---*)

PROCEDURE New (wr: Wr.T; debug := FALSE): M3CG.T =
  VAR u := NEW (U, wr := wr);
  BEGIN
    IF debug THEN u.dbg := M3LLVMIRDebug.New () END;
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
    Wr.PutText (u.body, "  " & instr & Loc (u) & Wr.EOL);
  END Emit;

PROCEDURE Loc (u: U): TEXT =
  (* The "!dbg" attachment for the current source line, or "". *)
  VAR p := u.cur_proc;  scope: TEXT;  line := u.source_line;
  BEGIN
    IF p = NIL OR p.dbg_sp = NIL THEN RETURN "" END;
    IF line <= 0 THEN line := p.dbg_line END;
    IF u.loc # NIL AND line = u.loc_line AND u.source_file = u.loc_file THEN
      RETURN u.loc;
    END;
    scope := Scope (p);
    IF u.source_file # NIL THEN
      WITH f = M3LLVMIRDebug.File (u.dbg, u.source_file) DO
        IF NOT Text.Equal (f, p.dbg_file) THEN
          (* code from another file *)
          scope := M3LLVMIRDebug.Node (u.dbg, "!DILexicalBlockFile(scope: "
                                     & scope & ", file: " & f
                                     & ", discriminator: 0)");
        END;
      END;
    END;
    u.loc_line := line;
    u.loc_file := u.source_file;
    u.loc := ", !dbg " & M3LLVMIRDebug.Node (u.dbg, "!DILocation(line: "
                                             & Fmt.Int (line) & ", scope: "
                                             & scope & ")");
    RETURN u.loc;
  END Loc;

PROCEDURE Scope (p: LProc): TEXT =
  (* The innermost debug scope open in "p": a DILexicalBlock or its
     DISubprogram. *)
  VAR l := p.dbg_blocks;
  BEGIN
    WHILE l # NIL DO
      IF l.t # NIL THEN RETURN l.t END;
      l := l.next;
    END;
    RETURN p.dbg_sp;
  END Scope;

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
    ELSIF IsFloat (from) AND IsFloat (to) THEN
      IF FloatBits (to) > FloatBits (from)
        THEN op := "fpext";
        ELSE op := "fptrunc";
      END;
    ELSIF IsInt (from) AND IsFloat (to) THEN
      IF IsSigned (from) THEN op := "sitofp" ELSE op := "uitofp" END;
    ELSIF IsFloat (from) AND IsInt (to) THEN
      IF IsSigned (to) THEN op := "fptosi" ELSE op := "fptoui" END;
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
    IF v.up_level AND v.owner # NIL THEN
      IF v.owner = u.cur_proc THEN
        u.cur_proc.frame_used := TRUE;
      ELSE
        (* A variable of an enclosing procedure, in its frame. *)
        t := NewTemp (u);
        Emit (u, t & " = getelementptr i8, ptr "
                   & FrameOf (u, v.owner.level) & ", i64 "
                   & Fmt.Int (v.frame_off + offset));
        RETURN t;
      END;
    ELSIF v.owner # NIL AND v.owner # u.cur_proc THEN
      Fatal (u, "reference to a non-up-level variable of another procedure");
    END;
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

    VAR d := u.helpers; BEGIN
      WHILE d # NIL DO Wr.PutText (wr, d.text & Wr.EOL); d := d.next END;
    END;

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
    VAR d := u.decls; BEGIN
      WHILE d # NIL DO
        IF NOT defined.get (d.name, ref) AND NOT seen.get (d.name, ref) THEN
          EVAL seen.put (d.name, d);
          Wr.PutText (wr, d.text & Wr.EOL);
        END;
        d := d.next;
      END;
    END;
    Wr.PutText (wr, Wr.EOL);

    Wr.PutText (wr, "attributes #0 = { uwtable \"frame-pointer\"=\"all\" }"
                      & Wr.EOL);
    Wr.PutText (wr, "attributes #1 = { returns_twice }" & Wr.EOL);
    IF u.dbg # NIL AND u.unit_file # NIL THEN
      M3LLVMIRDebug.Finish (u.dbg, wr, M3LLVMIRDebug.File (u.dbg, u.unit_file));
    END;
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
    IF u.unit_file = NIL THEN u.unit_file := file END;
  END set_source_file;

PROCEDURE set_source_line (u: U; line: INTEGER) =
  BEGIN
    u.source_line := line;
  END set_source_line;

(* Type declarations are for debug information (M3LLVMIRDebug).
   Method, exception and raises declarations are not described. *)

<*NOWARN*>PROCEDURE declare_typename(self: U; typeid: TypeUID; name: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Typename (self.dbg, typeid, M3ID.ToText (name)) END; END declare_typename;
<*NOWARN*>PROCEDURE declare_array(self: U; typeid, index_typeid, element_typeid: TypeUID; bit_size: BitSize; element_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Array (self.dbg, typeid, index_typeid, element_typeid, bit_size) END; END declare_array;
<*NOWARN*>PROCEDURE declare_open_array(self: U; typeid, element_typeid: TypeUID; bit_size: BitSize; element_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.OpenArray (self.dbg, typeid, element_typeid, bit_size) END; END declare_open_array;
<*NOWARN*>PROCEDURE declare_enum(self: U; typeid: TypeUID; n_elts: INTEGER; bit_size: BitSize) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Enum (self.dbg, typeid, n_elts, bit_size) END; END declare_enum;
<*NOWARN*>PROCEDURE declare_enum_elt(self: U; name: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.EnumElt (self.dbg, M3ID.ToText (name)) END; END declare_enum_elt;
<*NOWARN*>PROCEDURE declare_packed(self: U; typeid: TypeUID; bit_size: BitSize; base: TypeUID; base_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Packed (self.dbg, typeid, bit_size, base) END; END declare_packed;
<*NOWARN*>PROCEDURE declare_record(self: U; typeid: TypeUID; bit_size: BitSize; n_fields: INTEGER) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Record (self.dbg, typeid, bit_size, n_fields) END; END declare_record;
<*NOWARN*>PROCEDURE declare_field(self: U; name: Name; bit_offset: BitOffset; bit_size: BitSize; typeid: TypeUID; typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Field (self.dbg, M3ID.ToText (name), bit_offset, bit_size, typeid) END; END declare_field;
<*NOWARN*>PROCEDURE declare_set(self: U; t, domain: TypeUID; bit_size: BitSize; domain_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Set (self.dbg, t, domain, bit_size) END; END declare_set;
<*NOWARN*>PROCEDURE declare_subrange(self: U; typeid, domain_typeid: TypeUID; READONLY min, max: Target.Int; bit_size: BitSize; domain_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Subrange (self.dbg, typeid, domain_typeid, min, max, bit_size) END; END declare_subrange;
<*NOWARN*>PROCEDURE declare_pointer(self: U; typeid, target_typeid: TypeUID; brand: TEXT; traced: BOOLEAN; target_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Pointer (self.dbg, typeid, target_typeid) END; END declare_pointer;
<*NOWARN*>PROCEDURE declare_indirect(self: U; typeid, target_typeid: TypeUID; target_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Indirect (self.dbg, typeid, target_typeid) END; END declare_indirect;
<*NOWARN*>PROCEDURE declare_proctype(self: U; typeid: TypeUID; n_formals: INTEGER; result: TypeUID; n_raises: INTEGER; callingConvention: CallingConvention; result_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.ProcType (self.dbg, typeid, n_formals, result) END; END declare_proctype;
<*NOWARN*>PROCEDURE declare_formal(self: U; name: Name; typeid: TypeUID; typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Formal (self.dbg, typeid) END; END declare_formal;
<*NOWARN*>PROCEDURE declare_raises(self: U; name: Name) = BEGIN END declare_raises;
<*NOWARN*>PROCEDURE declare_object(self: U; typeid, super_typeid: TypeUID; brand: TEXT; traced: BOOLEAN; n_fields, n_methods: INTEGER; field_size: BitSize; field_offset, method_offset : INTEGER; super_typename: Name) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Object (self.dbg, typeid, super_typeid, n_fields, field_size, field_offset, n_methods, method_offset) END; END declare_object;
<*NOWARN*>PROCEDURE declare_method(self: U; name: Name; signature: TypeUID) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Method (self.dbg, M3ID.ToText (name), signature) END; END declare_method;
<*NOWARN*>PROCEDURE declare_opaque(self: U; typeid, super_typeid: TypeUID) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Opaque (self.dbg, typeid, super_typeid) END; END declare_opaque;
<*NOWARN*>PROCEDURE reveal_opaque(self: U; lhs_typeid, rhs_typeid: TypeUID) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.Reveal (self.dbg, lhs_typeid, rhs_typeid) END; END reveal_opaque;
<*NOWARN*>PROCEDURE declare_exception(self: U; name: Name; arg_typeid: TypeUID; raise_proc: BOOLEAN; base: Var; offset: INTEGER) = BEGIN END declare_exception;
<*NOWARN*>PROCEDURE widechar_size(self: U; size: INTEGER) = BEGIN IF self.dbg # NIL THEN M3LLVMIRDebug.WidecharSize (self.dbg, size) END; END widechar_size;
<*NOWARN*>PROCEDURE set_runtime_proc(self: U; name: Name; proc: Proc) = BEGIN END set_runtime_proc;
<*NOWARN*>PROCEDURE free_temp(self: U; var: Var) = BEGIN END free_temp;
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
                           is_const: BOOLEAN): Var =
  VAR v := NewVar (u, VarKind.Global, 0, 1, Type.Struct);
  BEGIN
    IF name = M3ID.NoID
      THEN v.name := "@seg." & Fmt.Int (v.id);
      ELSE v.name := GlobalName (name);
    END;
    IF NOT is_const AND u.module_data = NIL THEN u.module_data := v END;
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
                               & Fmt.Int (MAX (alignment, 1))
                               & DebugGlobals (u, v) & Wr.EOL);
    END;
  END BindGlobal;

PROCEDURE DebugGlobals (u: U; v: LVar): TEXT =
  (* The module's variables are fields of its data segment. *)
  BEGIN
    IF u.dbg = NIL OR v # u.module_data OR u.unit_file = NIL THEN
      RETURN "";
    END;
    RETURN M3LLVMIRDebug.Globals (u.dbg, M3LLVMIRDebug.File (u.dbg,
                                                             u.unit_file));
  END DebugGlobals;

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
                             & DebugGlobals (u, v) & Wr.EOL);
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
    p.m3name := M3ID.ToText (name);
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
    p.returns_twice := Text.Equal (p.name, "@_setjmp")
                         OR Text.Equal (p.name, "@setjmp")
                         OR Text.Equal (p.name, "@sigsetjmp");
    RETURN p;
  END import_procedure;

PROCEDURE declare_procedure (u: U; name: Name; n_params: INTEGER;
                             return_type: Type; level: INTEGER;
                             <*UNUSED*> callingConvention: CallingConvention;
                             exported: BOOLEAN; parent: Proc;
                             return_typeid: TypeUID;
                             <*UNUSED*> return_typename: Name): Proc =
  VAR p: LProc;
  BEGIN
    EVAL parent;
    p := NewProc (u, name, n_params, return_type);
    p.exported := exported;
    p.level := level;
    p.ret_typeid := return_typeid;
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
    res := attr & ReturnType (p) & " " & p.name & "(";
    FOR i := 0 TO p.n_declared - 1 DO
      v := p.params[i];
      IF i > 0 THEN res := res & ", " END;
      res := res & LType (v.type) & ExtAttr (v.type);
      IF names THEN res := res & " %p." & Fmt.Int (v.id) END;
    END;
    IF p.level > 0 THEN
      (* The static link is the last parameter. *)
      IF p.n_declared > 0 THEN res := res & ", " END;
      res := res & "ptr";
      IF names THEN res := res & " %sl" END;
    END;
    res := res & ")";
    IF p.returns_twice THEN res := res & " #1" END;
    RETURN res;
  END Signature;

PROCEDURE Alloca (u: U; v: LVar) =
  BEGIN
    IF v.up_level THEN
      Wr.PutText (u.allocas, "  " & v.name
                               & " = getelementptr i8, ptr %frame, i64 "
                               & Fmt.Int (v.frame_off) & Wr.EOL);
      u.cur_proc.frame_used := TRUE;
    ELSE
      Wr.PutText (u.allocas, "  " & v.name & " = alloca ["
                               & Fmt.Int (MAX (v.size, 1)) & " x i8], align "
                               & Fmt.Int (MAX (v.align, 1)) & Wr.EOL);
    END;
  END Alloca;

PROCEDURE InFrame (p: LProc; v: LVar) =
  (* Give "v" a place in "p"'s frame.  Offset 0 is the static link. *)
  VAR a := MAX (v.align, 1);  off: INTEGER;
  BEGIN
    IF p.frame_size < 8 THEN p.frame_size := 8; p.frame_align := 8 END;
    off := (p.frame_size + a - 1) DIV a * a;
    v.up_level := TRUE;
    v.frame_off := off;
    p.frame_size := off + v.size;
    p.frame_align := MAX (p.frame_align, a);
  END InFrame;

PROCEDURE ReturnType (p: LProc): TEXT =
  BEGIN
    IF p.returns_twice THEN RETURN "i32" END;  (* C "int" *)
    RETURN LType (p.return);
  END ReturnType;

PROCEDURE NewLocal (u: U; kind: VarKind; byte_size: ByteSize;
                    alignment: Alignment; type: Type): LVar =
  VAR v := NewVar (u, kind, byte_size, alignment, type);
  BEGIN
    v.name := "%v." & Fmt.Int (v.id);
    RETURN v;
  END NewLocal;

PROCEDURE declare_local (u: U; name: Name; byte_size: ByteSize;
                         alignment: Alignment; type: Type;
                         typeid: TypeUID;
                         in_memory, up_level: BOOLEAN;
                         <*UNUSED*> frequency: Frequency;
                         <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Local, byte_size, alignment, type);
  BEGIN
    EVAL in_memory;
    IF u.cur_proc # NIL THEN
      v.owner := u.cur_proc;
      IF up_level THEN InFrame (v.owner, v) END;
      Alloca (u, v);
    ELSIF u.decl_proc # NIL THEN
      v.owner := u.decl_proc;
      IF up_level THEN InFrame (v.owner, v) END;
      u.decl_proc.locals := NEW (VarList, v := v,
                                 next := u.decl_proc.locals);
    ELSE
      Fatal (u, "declare_local outside a procedure");
    END;
    DebugVar (u, v, name, typeid);
    RETURN v;
  END declare_local;

PROCEDURE declare_param (u: U; name: Name; byte_size: ByteSize;
                         alignment: Alignment; type: Type;
                         typeid: TypeUID;
                         <*UNUSED*> in_memory: BOOLEAN; up_level: BOOLEAN;
                         <*UNUSED*> frequency: Frequency;
                         <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Param, byte_size, alignment, type);
      p := u.decl_proc;
  BEGIN
    IF p = NIL THEN Fatal (u, "declare_param without a procedure") END;
    v.owner := p;
    IF up_level AND NOT p.imported THEN InFrame (p, v) END;
    IF p.n_declared < NUMBER (p.params^) THEN
      p.params[p.n_declared] := v;
      INC (p.n_declared);
    ELSE
      Fatal (u, "too many parameters for " & p.name);
    END;
    IF NOT p.imported THEN DebugVar (u, v, name, typeid) END;
    RETURN v;
  END declare_param;

PROCEDURE DebugVar (u: U; v: LVar; name: Name; typeid: TypeUID) =
  (* Remember a named local or parameter for its DILocalVariable. *)
  BEGIN
    IF u.dbg = NIL OR name = M3ID.NoID OR v.owner = NIL THEN RETURN END;
    v.m3name := M3ID.ToText (name);
    (* The front end's temporary for a function's result. *)
    IF Text.Equal (v.m3name, "_result") THEN RETURN END;
    v.typeid := typeid;
    (* Variables declared before begin_procedure belong to its line. *)
    IF u.cur_proc # NIL THEN v.line := u.source_line END;
    (* Locals of a nested block (VAR ... BEGIN) belong to its scope. *)
    IF u.cur_proc = v.owner AND v.owner.dbg_blocks # NIL THEN
      v.scope := Scope (v.owner);
    END;
    v.owner.dbg_vars := NEW (VarList, v := v, next := v.owner.dbg_vars);
  END DebugVar;

PROCEDURE begin_block (u: U) =
  (* A nested scope (Phase 5): its locals and code get a DILexicalBlock,
     so that gdb tells apart variables of the same name. *)
  VAR p := u.cur_proc;  b: TEXT := NIL;  line: INTEGER;
  BEGIN
    IF p = NIL THEN RETURN END;
    IF p.dbg_sp # NIL THEN
      line := MAX (u.source_line, p.dbg_line);
      b := M3LLVMIRDebug.Node (u.dbg, "distinct !DILexicalBlock(scope: "
                                 & Scope (p) & ", file: " & p.dbg_file
                                 & ", line: " & Fmt.Int (line) & ")");
      u.loc := NIL;
    END;
    p.dbg_blocks := NEW (TextList, t := b, next := p.dbg_blocks);
  END begin_block;

PROCEDURE end_block (u: U) =
  VAR p := u.cur_proc;
  BEGIN
    IF p = NIL OR p.dbg_blocks = NIL THEN RETURN END;
    p.dbg_blocks := p.dbg_blocks.next;
    u.loc := NIL;
  END end_block;

PROCEDURE DebugProc (u: U; p: LProc) =
  (* Reserve "p"'s DISubprogram, at the current source position. *)
  CONST UID_ADDRESS = 138420323;
  VAR params: REF ARRAY OF TypeUID;  ret := p.ret_typeid;
  BEGIN
    u.loc := NIL;
    IF u.dbg = NIL OR u.source_file = NIL THEN RETURN END;
    p.dbg_file := M3LLVMIRDebug.File (u.dbg, u.source_file);
    p.dbg_line := u.source_line;
    p.dbg_sp := M3LLVMIRDebug.Reserve (u.dbg);
    params := NEW (REF ARRAY OF TypeUID, p.n_declared);
    FOR i := 0 TO p.n_declared - 1 DO params[i] := p.params[i].typeid END;
    (* The front end gives no result type to a module's body, which
       returns its ADDRESS. *)
    IF ret = 0 AND p.return = Type.Addr THEN ret := UID_ADDRESS END;
    M3LLVMIRDebug.Subprogram (u.dbg, p.dbg_sp, p.m3name, p.dbg_file,
                              p.dbg_line, NOT p.exported, ret, params^);
  END DebugProc;

PROCEDURE DebugDeclares (u: U; p: LProc): TEXT =
  (* The llvm.dbg.declare calls for "p"'s named variables. *)
  VAR wr: TextWr.T;  l := p.dbg_vars;  v: LVar;  var, expr: TEXT;
      arg: INTEGER;  scope: TEXT;
  BEGIN
    IF p.dbg_sp = NIL OR l = NIL THEN RETURN "" END;
    wr := TextWr.New ();
    WHILE l # NIL DO
      v := l.v;
      arg := 0;
      FOR i := 0 TO p.n_declared - 1 DO
        IF p.params[i] = v THEN arg := i + 1 END;
      END;
      var := M3LLVMIRDebug.Reserve (u.dbg);
      expr := M3LLVMIRDebug.Reserve (u.dbg);
      scope := v.scope;
      IF scope = NIL THEN scope := p.dbg_sp END;
      M3LLVMIRDebug.Variable (u.dbg, var, expr, v.m3name, arg, scope,
                              p.dbg_file, MAX (v.line, p.dbg_line),
                              v.typeid);
      Wr.PutText (wr, "  call void @llvm.dbg.declare(metadata ptr " & v.name
                        & ", metadata " & var & ", metadata " & expr
                        & "), !dbg "
                        & M3LLVMIRDebug.Node (u.dbg, "!DILocation(line: "
                            & Fmt.Int (MAX (v.line, p.dbg_line))
                            & ", scope: " & scope & ")") & Wr.EOL);
      l := l.next;
    END;
    AddDecl (u, "@llvm.dbg.declare",
             "declare void @llvm.dbg.declare(metadata, metadata, metadata)");
    RETURN TextWr.ToText (wr);
  END DebugDeclares;

PROCEDURE declare_temp (u: U; byte_size: ByteSize; alignment: Alignment;
                        type: Type; <*UNUSED*> in_memory: BOOLEAN;
                        <*UNUSED*> typename: Name): Var =
  VAR v := NewLocal (u, VarKind.Local, byte_size, alignment, type);
  BEGIN
    IF u.cur_proc = NIL THEN Fatal (u, "declare_temp outside a procedure") END;
    v.owner := u.cur_proc;
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
    u.try_open := NIL;
    u.try_last := NIL;
    DebugProc (u, p);
    FOR i := 0 TO p.n_declared - 1 DO
      v := p.params[i];
      Alloca (u, v);
      IF v.type = Type.Struct THEN
        (* The caller passes the address; the callee makes the copy. *)
        Wr.PutText (u.allocas, "  call void @llvm.memcpy.p0.p0.i64(ptr "
                                 & v.name & ", ptr %p." & Fmt.Int (v.id)
                                 & ", i64 " & Fmt.Int (v.size)
                                 & ", i1 false)" & Wr.EOL);
        UseMemIntrinsic (u, "memcpy");
      ELSE
        Wr.PutText (u.allocas, "  store " & LType (v.type) & " %p."
                                 & Fmt.Int (v.id) & ", ptr " & v.name
                                 & ", align "
                                 & Fmt.Int (AlignAt (v.align, 0, v.type))
                                 & Wr.EOL);
      END;
    END;
    l := p.locals;
    WHILE l # NIL DO Alloca (u, l.v); l := l.next END;
  END begin_procedure;

PROCEDURE end_procedure (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);  frame := "";  body, sp := "";
  BEGIN
    IF p # u.cur_proc THEN Fatal (u, "end_procedure does not match") END;
    IF u.try_open # NIL THEN Fatal (u, "unclosed try region") END;
    IF NOT u.terminated THEN
      IF p.return = Type.Void
        THEN EmitTerm (u, "ret void");
        ELSE EmitTerm (u, "unreachable");
      END;
    END;
    IF p.level > 0 OR p.frame_used OR p.frame_size > 8 THEN
      frame := "  %frame = alloca [" & Fmt.Int (MAX (p.frame_size, 8))
                 & " x i8], align " & Fmt.Int (MAX (p.frame_align, 8))
                 & Wr.EOL;
      IF p.level > 0 THEN
        frame := frame & "  store ptr %sl, ptr %frame, align 8" & Wr.EOL;
      END;
    END;
    body := TextWr.ToText (u.body);
    IF p.calls_setjmp THEN
      (* Locals must survive longjmp: keep them in memory. *)
      body := Replace (body, " = load ", " = load volatile ");
      body := Replace (body, "  store ", "  store volatile ");
    END;
    IF p.dbg_sp # NIL THEN sp := " !dbg " & p.dbg_sp END;
    IF p.has_eh THEN  (* Phase 7, ex_stack *)
      sp := " personality ptr @__gxx_personality_v0" & sp;
    END;
    Wr.PutText (u.funcs, "define " & Linkage (p.exported)
                           & Signature (p, TRUE) & " #0" & sp & " {"
                           & Wr.EOL & "entry:" & Wr.EOL & frame
                           & TextWr.ToText (u.allocas)
                           & DebugDeclares (u, p)
                           & body
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

PROCEDURE StartCall (u: U; p: LProc) =
  BEGIN
    u.call_proc := p;
    u.call_args := "";
    u.call_n := 0;
    u.call_last := NIL;
    u.in_call := TRUE;
    u.call_aborted := FALSE;
    u.call_sl := NIL;
  END StartCall;

PROCEDURE EndCall (u: U) =
  BEGIN
    u.call_proc := NIL;
    u.call_args := "";
    u.in_call := FALSE;
    u.call_aborted := FALSE;
    u.call_sl := NIL;
  END EndCall;

PROCEDURE AddArg (u: U; arg: TEXT) =
  BEGIN
    IF u.call_n > 0 THEN u.call_args := u.call_args & ", " END;
    u.call_args := u.call_args & arg;
    INC (u.call_n);
  END AddArg;

PROCEDURE start_call_direct (u: U; proc: Proc; <*UNUSED*> level: INTEGER;
                             <*UNUSED*> type: Type) =
  BEGIN
    StartCall (u, NARROW (proc, LProc));
  END start_call_direct;

PROCEDURE pop_param (u: U; type: MType) =
  VAR p := u.call_proc;  x := Pop (u);  ptype: Type := type;  val: TEXT;
  BEGIN
    IF NOT u.in_call THEN Fatal (u, "pop_param outside a call") END;
    IF p # NIL AND u.call_n < p.n_declared THEN
      ptype := p.params[u.call_n].type;
    END;
    val := Cvt (u, Cvt (u, x.val, x.type, StackType (type)),
                StackType (type), ptype);
    u.call_last := Cvt (u, x.val, x.type, Type.Word64);
    AddArg (u, LType (ptype) & ExtAttr (ptype) & " " & val);
  END pop_param;

PROCEDURE call_direct (u: U; proc: Proc; type: Type) =
  VAR p := NARROW (proc, LProc);  r: TEXT;  call, attr := "";
  BEGIN
    IF u.call_aborted THEN
      IF type # Type.Void THEN Push (u, StackType (type), "poison") END;
      EndCall (u);
      RETURN;
    END;
    IF p.imported AND Text.Equal (p.name, "@alloca") AND u.call_n = 1 THEN
      (* The C library's alloca is a compiler builtin. *)
      r := NewTemp (u);
      Emit (u, r & " = alloca i8, i64 " & u.call_last & ", align 16");
      Push (u, Type.Addr, r);
      EndCall (u);
      RETURN;
    END;
    p.used := TRUE;
    (* The front end calls a FINALLY handler procedure directly without
       its declared "activation" parameter (see TryFinStmt.Compile2);
       pass zero for missing parameters so the static link lands last. *)
    WHILE u.call_n < p.n_declared DO
      WITH t = p.params[u.call_n].type DO
        AddArg (u, LType (t) & ExtAttr (t) & " zeroinitializer");
      END;
    END;
    IF p.level > 0 THEN AddArg (u, "ptr " & FrameOf (u, p.level - 1)) END;
    IF p.returns_twice THEN
      u.cur_proc.calls_setjmp := TRUE;
      attr := " #1";
    END;
    call := "call " & ReturnType (p) & " " & p.name & "("
              & u.call_args & ")" & attr;
    IF type = Type.Void THEN
      EmitCall (u, NIL, call, NOT p.returns_twice);
    ELSE
      r := NewTemp (u);
      EmitCall (u, r, call, NOT p.returns_twice);
      IF p.returns_twice
        THEN r := Cvt (u, r, Type.Int32, StackType (type));
        ELSE r := Cvt (u, r, p.return, StackType (type));
      END;
      Push (u, StackType (type), r);
    END;
    EndCall (u);
  END call_direct;

PROCEDURE load_procedure (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);
  BEGIN
    p.used := TRUE;
    Push (u, Type.Addr, p.name);
  END load_procedure;

(*=================================================== Phase 2 helpers ===*)

PROCEDURE IsFloat (t: Type): BOOLEAN =
  BEGIN
    RETURN t = Type.Reel OR t = Type.LReel OR t = Type.XReel;
  END IsFloat;

PROCEDURE FloatBits (t: Type): INTEGER =
  VAR l := LType (t);
  BEGIN
    IF Text.Equal (l, "float") THEN RETURN 32 END;
    IF Text.Equal (l, "double") THEN RETURN 64 END;
    RETURN 128;
  END FloatBits;

PROCEDURE FloatSuffix (t: Type): TEXT =
  (* The overload suffix of a floating-point intrinsic. *)
  BEGIN
    RETURN "f" & Fmt.Int (FloatBits (t));
  END FloatSuffix;

PROCEDURE NatAlign (t: Type): INTEGER =
  BEGIN
    IF t = Type.XReel THEN RETURN MAX (Target.Extended.align DIV 8, 1) END;
    RETURN MAX (TypeBytes (t), 1);
  END NatAlign;

PROCEDURE Replace (t, old, new: TEXT): TEXT =
  VAR wr := TextWr.New ();  start := 0;  i: INTEGER;
      n := Text.Length (old);
  BEGIN
    LOOP
      i := Text.FindChar (t, Text.GetChar (old, 0), start);
      IF i < 0 THEN EXIT END;
      IF Text.Equal (Text.Sub (t, i, n), old) THEN
        Wr.PutText (wr, Text.Sub (t, start, i - start));
        Wr.PutText (wr, new);
        start := i + n;
      ELSE
        Wr.PutText (wr, Text.Sub (t, start, i + 1 - start));
        start := i + 1;
      END;
    END;
    Wr.PutText (wr, Text.Sub (t, start));
    RETURN TextWr.ToText (wr);
  END Replace;

PROCEDURE Find (l: DeclList; name: TEXT): BOOLEAN =
  BEGIN
    WHILE l # NIL DO
      IF Text.Equal (l.name, name) THEN RETURN TRUE END;
      l := l.next;
    END;
    RETURN FALSE;
  END Find;

PROCEDURE AddDecl (u: U; name, text: TEXT) =
  (* Declare the external function "name" (with "@"), once. *)
  BEGIN
    IF NOT Find (u.decls, name) THEN
      u.decls := NEW (DeclList, name := name, text := text, next := u.decls);
    END;
  END AddDecl;

PROCEDURE HaveHelper (u: U; name: TEXT): BOOLEAN =
  BEGIN
    RETURN Find (u.helpers, name);
  END HaveHelper;

PROCEDURE AddHelper (u: U; name, text: TEXT) =
  BEGIN
    u.helpers := NEW (DeclList, name := name, text := text, next := u.helpers);
  END AddHelper;

PROCEDURE UseMemIntrinsic (u: U; which: TEXT) =
  BEGIN
    IF Text.Equal (which, "memset") THEN
      AddDecl (u, "@llvm.memset.p0.i64",
               "declare void @llvm.memset.p0.i64(ptr, i8, i64, i1)");
    ELSE
      AddDecl (u, "@llvm." & which & ".p0.p0.i64",
               "declare void @llvm." & which
                 & ".p0.p0.i64(ptr, ptr, i64, i1)");
    END;
  END UseMemIntrinsic;

PROCEDURE FrameOf (u: U; level: INTEGER): TEXT =
  (* The frame of the enclosing procedure at nesting level "level". *)
  VAR c := u.cur_proc;  f := "%sl";  lev: INTEGER;  t: TEXT;
  BEGIN
    IF level = c.level THEN c.frame_used := TRUE; RETURN "%frame" END;
    IF level > c.level OR level < 0 THEN
      Fatal (u, "bad static nesting level " & Fmt.Int (level));
    END;
    lev := c.level - 1;
    WHILE lev > level DO
      t := NewTemp (u);
      Emit (u, t & " = load ptr, ptr " & f & ", align 8");
      f := t;
      DEC (lev);
    END;
    RETURN f;
  END FrameOf;

PROCEDURE PopAs (u: U; t: Type): TEXT =
  (* Pop s0 and convert it to "t". *)
  VAR x := Pop (u);
  BEGIN
    RETURN Cvt (u, x.val, x.type, t);
  END PopAs;

PROCEDURE Instr (u: U; rhs: TEXT): TEXT =
  (* Emit "%t = rhs" and return %t. *)
  VAR t := NewTemp (u);
  BEGIN
    Emit (u, t & " = " & rhs);
    RETURN t;
  END Instr;

PROCEDURE Bits (t: Type): TEXT =
  BEGIN
    RETURN Fmt.Int (IntBits (t));
  END Bits;

PROCEDURE SignedConst (bits: INTEGER; w: Word.T): TEXT =
  (* "w" truncated to "bits" bits, written as a signed decimal. *)
  BEGIN
    IF bits < BITSIZE (INTEGER) THEN
      w := Word.And (w, Word.Minus (Word.LeftShift (1, bits), 1));
      IF Word.And (w, Word.LeftShift (1, bits - 1)) # 0 THEN
        w := Word.Or (w, Word.Not (Word.Minus (Word.LeftShift (1, bits), 1)));
      END;
    END;
    RETURN Fmt.Int (w);  (* Word.T is INTEGER *)
  END SignedConst;

PROCEDURE LowMask (bits, n: INTEGER): TEXT =
  (* n ones, in a "bits"-bit integer. *)
  BEGIN
    IF n >= bits THEN RETURN "-1" END;
    RETURN SignedConst (bits, Word.Minus (Word.LeftShift (1, n), 1));
  END LowMask;

(*--------------------------------------------------------- faults ---*)

PROCEDURE ReportFault (u: U): LProc =
  VAR pl := u.procs;  p: LProc;
  BEGIN
    WHILE pl # NIL DO
      IF Text.Equal (pl.p.name, "@RTHooks__ReportFault") THEN RETURN pl.p END;
      pl := pl.next;
    END;
    p := NEW (LProc, id := u.next_proc, name := "@RTHooks__ReportFault",
              return := Type.Void, imported := TRUE);
    INC (u.next_proc);
    p.params := NEW (REF ARRAY OF LVar, 2);
    p.params[0] := NEW (LVar, id := 0, type := Type.Addr);
    p.params[1] := NEW (LVar, id := 0, type := Type.Word64);
    p.n_declared := 2;
    u.procs := NEW (ProcList, p := p, next := u.procs);
    RETURN p;
  END ReportFault;

PROCEDURE Fault (u: U; code: RuntimeError) =
  VAR p := ReportFault (u);  m := "null";
      info := ORD (code) + u.source_line * 32;
  BEGIN
    p.used := TRUE;
    IF u.module_data # NIL THEN
      u.module_data.used := TRUE;
      m := u.module_data.name;
    END;
    (* ReportFault raises RuntimeError.E: inside a try region it must
       unwind to the region's landing pad. *)
    EmitCall (u, NIL, "call void " & p.name & "(ptr " & m & ", i64 "
                        & Fmt.Int (info) & ")");
    EmitTerm (u, "unreachable");
  END Fault;

PROCEDURE FaultIf (u: U; cond: TEXT; code: RuntimeError) =
  (* If the i1 "cond" is true, report "code". *)
  VAR bad := NewBlock (u, "fault.");  ok := NewBlock (u, "ok.");
  BEGIN
    EmitTerm (u, "br i1 " & cond & ", label %" & bad & ", label %" & ok);
    StartBlock (u, bad);
    Fault (u, code);
    StartBlock (u, ok);
  END FaultIf;

(*---------------------------------------------------- floating point ---*)

PROCEDURE PrecType (p: Target.Precision): Type =
  BEGIN
    CASE p OF
    | Target.Precision.Short    => RETURN Type.Reel;
    | Target.Precision.Long     => RETURN Type.LReel;
    | Target.Precision.Extended => RETURN Type.XReel;
    END;
  END PrecType;

PROCEDURE Hex16 (READONLY b: ARRAY OF TFloat.Byte; start: INTEGER): TEXT =
  (* Bytes b[start..start+7], little-endian, as 16 hex digits. *)
  VAR t := "";
  BEGIN
    FOR i := start + 7 TO start BY -1 DO t := t & Hex2 (b[i]) END;
    RETURN t;
  END Hex16;

PROCEDURE FloatLit (u: U; t: Type; READONLY f: Target.Float): TEXT =
  VAR buf: ARRAY [0..15] OF TFloat.Byte;  g: Target.Float;  n: INTEGER;
  BEGIN
    IF FloatBits (t) = 128 THEN
      IF TFloat.Prec (f) # Target.Precision.Extended THEN
        IF NOT TFloat.FloatF (f, Target.Precision.Extended, g) THEN
          Fatal (u, "bad floating-point constant");
        END;
      ELSE
        g := f;
      END;
      n := TFloat.ToBytes (g, buf);
      IF n # 16 THEN Fatal (u, "bad EXTENDED constant") END;
      RETURN "0xL" & Hex16 (buf, 0) & Hex16 (buf, 8);
    END;
    (* float and double constants are written as doubles.  A float
       constant must be exactly representable as a float, so it is
       always rounded to REAL first, as C's implicit conversion
       does; the front end can hand a REAL operation a value of
       LONGREAL precision. *)
    IF FloatBits (t) = 32 THEN
      (* TFloat.FloatF does not round, so round here. *)
      g.pre := Target.Precision.Long;
      g.exponent := f.exponent;
      g.fraction := FLOAT (FLOAT (f.fraction, REAL), EXTENDED);
    ELSIF TFloat.Prec (f) # Target.Precision.Long THEN
      IF NOT TFloat.FloatF (f, Target.Precision.Long, g) THEN
        Fatal (u, "bad floating-point constant");
      END;
    ELSE
      g := f;
    END;
    n := TFloat.ToBytes (g, buf);
    IF n # 8 THEN Fatal (u, "bad LONGREAL constant") END;
    RETURN "0x" & Hex16 (buf, 0);
  END FloatLit;

PROCEDURE init_float (u: U; byte_offset: ByteOffset;
                      READONLY f: Target.Float) =
  VAR t := PrecType (TFloat.Prec (f));
  BEGIN
    InitField (u, byte_offset, LType (t), FloatLit (u, t, f),
               TypeBytes (t));
  END init_float;

PROCEDURE load_float (u: U; type: RType; READONLY f: Target.Float) =
  BEGIN
    Push (u, type, FloatLit (u, type, f));
  END load_float;

(*----------------------------------------------------- control flow ---*)

PROCEDURE Pred (t: Type; op: CompareOp): TEXT =
  (* "icmp xx" or "fcmp xx" *)
  BEGIN
    IF IsFloat (t) THEN
      CASE op OF
      | CompareOp.EQ => RETURN "fcmp oeq";
      | CompareOp.NE => RETURN "fcmp une";
      | CompareOp.GT => RETURN "fcmp ogt";
      | CompareOp.GE => RETURN "fcmp oge";
      | CompareOp.LT => RETURN "fcmp olt";
      | CompareOp.LE => RETURN "fcmp ole";
      END;
    ELSIF IsSigned (t) THEN
      CASE op OF
      | CompareOp.EQ => RETURN "icmp eq";
      | CompareOp.NE => RETURN "icmp ne";
      | CompareOp.GT => RETURN "icmp sgt";
      | CompareOp.GE => RETURN "icmp sge";
      | CompareOp.LT => RETURN "icmp slt";
      | CompareOp.LE => RETURN "icmp sle";
      END;
    ELSE
      CASE op OF
      | CompareOp.EQ => RETURN "icmp eq";
      | CompareOp.NE => RETURN "icmp ne";
      | CompareOp.GT => RETURN "icmp ugt";
      | CompareOp.GE => RETURN "icmp uge";
      | CompareOp.LT => RETURN "icmp ult";
      | CompareOp.LE => RETURN "icmp ule";
      END;
    END;
  END Pred;

PROCEDURE Compare2 (u: U; t: ZType; op: CompareOp): TEXT =
  (* Pop s0 and s1; return the i1 "s1 op s0". *)
  VAR b := PopAs (u, t);  a := PopAs (u, t);
  BEGIN
    RETURN Instr (u, Pred (t, op) & " " & LType (t) & " " & a & ", " & b);
  END Compare2;

PROCEDURE if_compare (u: U; type: ZType; op: CompareOp; label: Label;
                      <*UNUSED*> frequency: Frequency) =
  VAR c := Compare2 (u, type, op);  next := NewBlock (u, "B.");
  BEGIN
    EmitTerm (u, "br i1 " & c & ", label %" & LabelName (label)
                   & ", label %" & next);
    StartBlock (u, next);
  END if_compare;

PROCEDURE case_jump (u: U; type: IType; READONLY labels: ARRAY OF Label) =
  VAR x := PopAs (u, type);  def := NewBlock (u, "nocase.");
      wr := TextWr.New ();  lt := LType (type);
  BEGIN
    Wr.PutText (wr, "switch " & lt & " " & x & ", label %" & def & " [");
    FOR i := 0 TO LAST (labels) DO
      Wr.PutText (wr, " " & lt & " " & Fmt.Int (i) & ", label %"
                        & LabelName (labels[i]));
    END;
    Wr.PutText (wr, " ]");
    EmitTerm (u, TextWr.ToText (wr));
    StartBlock (u, def);
    EmitTerm (u, "unreachable");
  END case_jump;

(*------------------------------------------------- loads and stores ---*)

PROCEDURE Offset (u: U; a: TEXT; o: ByteOffset): TEXT =
  BEGIN
    IF o = 0 THEN RETURN a END;
    RETURN Instr (u, "getelementptr i8, ptr " & a & ", i64 " & Fmt.Int (o));
  END Offset;

PROCEDURE load_indirect (u: U; o: ByteOffset; t: MType; z: ZType) =
  VAR a := Offset (u, PopAs (u, Type.Addr), o);  r: TEXT;
  BEGIN
    r := Instr (u, "load " & LType (t) & ", ptr " & a & ", align "
                     & Fmt.Int (NatAlign (t)));
    Push (u, z, Cvt (u, r, t, z));
  END load_indirect;

PROCEDURE store_indirect (u: U; o: ByteOffset; z: ZType; t: MType) =
  VAR x := Pop (u);  a := Offset (u, PopAs (u, Type.Addr), o);  val: TEXT;
  BEGIN
    val := Cvt (u, Cvt (u, x.val, x.type, z), z, t);
    Emit (u, "store " & LType (t) & " " & val & ", ptr " & a & ", align "
               & Fmt.Int (NatAlign (t)));
  END store_indirect;

(*------------------------------------------------------- arithmetic ---*)

PROCEDURE compare (u: U; t: ZType; r: IType; op: CompareOp) =
  VAR c := Compare2 (u, t, op);
  BEGIN
    Push (u, r, Instr (u, "zext i1 " & c & " to " & LType (r)));
  END compare;

PROCEDURE Binary (u: U; t: Type; iop, fop: TEXT) =
  VAR b := PopAs (u, t);  a := PopAs (u, t);  op := iop;
  BEGIN
    IF IsFloat (t) THEN op := fop END;
    Push (u, t, Instr (u, op & " " & LType (t) & " " & a & ", " & b));
  END Binary;

PROCEDURE add (u: U; t: AType) =
  BEGIN Binary (u, t, "add", "fadd") END add;

PROCEDURE subtract (u: U; t: AType) =
  BEGIN Binary (u, t, "sub", "fsub") END subtract;

PROCEDURE multiply (u: U; t: AType) =
  BEGIN Binary (u, t, "mul", "fmul") END multiply;

PROCEDURE divide (u: U; t: RType) =
  BEGIN Binary (u, t, "fdiv", "fdiv") END divide;

PROCEDURE negate (u: U; t: AType) =
  VAR a := PopAs (u, t);
  BEGIN
    IF IsFloat (t)
      THEN Push (u, t, Instr (u, "fneg " & LType (t) & " " & a));
      ELSE Push (u, t, Instr (u, "sub " & LType (t) & " 0, " & a));
    END;
  END negate;

PROCEDURE abs (u: U; t: AType) =
  VAR a := PopAs (u, t);  lt := LType (t);  n, c: TEXT;
  BEGIN
    IF IsFloat (t) THEN
      AddDecl (u, "@llvm.fabs." & FloatSuffix (t),
               "declare " & lt & " @llvm.fabs." & FloatSuffix (t)
                 & "(" & lt & ")");
      Push (u, t, Instr (u, "call " & lt & " @llvm.fabs." & FloatSuffix (t)
                              & "(" & lt & " " & a & ")"));
    ELSIF IsSigned (t) THEN
      n := Instr (u, "sub " & lt & " 0, " & a);
      c := Instr (u, "icmp slt " & lt & " " & a & ", 0");
      Push (u, t, Instr (u, "select i1 " & c & ", " & lt & " " & n & ", "
                              & lt & " " & a));
    ELSE
      Push (u, t, a);
    END;
  END abs;

PROCEDURE MaxMin (u: U; t: ZType; op: CompareOp) =
  (* M3C: s0 op s1 ? s0 : s1 *)
  VAR b := PopAs (u, t);  a := PopAs (u, t);  lt := LType (t);  c: TEXT;
  BEGIN
    c := Instr (u, Pred (t, op) & " " & lt & " " & b & ", " & a);
    Push (u, t, Instr (u, "select i1 " & c & ", " & lt & " " & b & ", "
                            & lt & " " & a));
  END MaxMin;

PROCEDURE max (u: U; t: ZType) =
  BEGIN MaxMin (u, t, CompareOp.GT) END max;

PROCEDURE min (u: U; t: ZType) =
  BEGIN MaxMin (u, t, CompareOp.LT) END min;

PROCEDURE cvt_int (u: U; t: RType; r: IType; op: ConvertOp) =
  VAR a := PopAs (u, t);  lt := LType (t);  sfx := FloatSuffix (t);
      fn, v: TEXT;
  BEGIN
    CASE op OF
    | ConvertOp.Trunc =>
        v := Instr (u, "fptosi " & lt & " " & a & " to i64");
    | ConvertOp.Round =>
        IF FloatBits (t) = 128 THEN
          AddDecl (u, "@llroundq", "declare i64 @llroundq(fp128)");
          v := Instr (u, "call i64 @llroundq(fp128 " & a & ")");
        ELSE
          fn := "@llvm.llround.i64." & sfx;
          AddDecl (u, fn, "declare i64 " & fn & "(" & lt & ")");
          v := Instr (u, "call i64 " & fn & "(" & lt & " " & a & ")");
        END;
    | ConvertOp.Floor, ConvertOp.Ceiling =>
        IF FloatBits (t) = 128 THEN
          IF op = ConvertOp.Floor THEN fn := "@floorq" ELSE fn := "@ceilq" END;
        ELSIF op = ConvertOp.Floor THEN
          fn := "@llvm.floor." & sfx;
        ELSE
          fn := "@llvm.ceil." & sfx;
        END;
        AddDecl (u, fn, "declare " & lt & " " & fn & "(" & lt & ")");
        v := Instr (u, "call " & lt & " " & fn & "(" & lt & " " & a & ")");
        v := Instr (u, "fptosi " & lt & " " & v & " to i64");
    END;
    Push (u, r, Cvt (u, v, Type.Int64, r));
  END cvt_int;

PROCEDURE cvt_float (u: U; t: AType; r: RType) =
  VAR x := Pop (u);
  BEGIN
    Push (u, r, Cvt (u, Cvt (u, x.val, x.type, t), t, r));
  END cvt_float;

PROCEDURE DivMod (u: U; t: IType; a, b: Sign; is_div: BOOLEAN) =
  (* sdiv and srem of FIRST (T) by -1 are undefined in LLVM, and trap
     on x86 (bug 26). Unless an operand is known to be non-negative,
     divide by 1 instead when the divisor is -1: srem then gives the
     right MOD, 0, and the DIV is -x, which wraps as "-" does. *)
  VAR y := PopAs (u, t);  x := PopAs (u, t);  lt := LType (t);
      q, r, c1, c2, adj, res, m1: TEXT;
      guard := a # Sign.Positive AND b # Sign.Positive;
  BEGIN
    IF NOT IsSigned (t) THEN
      IF is_div
        THEN Push (u, t, Instr (u, "udiv " & lt & " " & x & ", " & y));
        ELSE Push (u, t, Instr (u, "urem " & lt & " " & x & ", " & y));
      END;
      RETURN;
    END;
    IF guard THEN
      m1 := Instr (u, "icmp eq " & lt & " " & y & ", -1");
      y := Instr (u, "select i1 " & m1 & ", " & lt & " 1, " & lt & " " & y);
    END;
    IF a = b AND a # Sign.Unknown THEN
      IF is_div
        THEN res := Instr (u, "sdiv " & lt & " " & x & ", " & y);
        ELSE res := Instr (u, "srem " & lt & " " & x & ", " & y);
      END;
    ELSE
      (* Round toward minus infinity. *)
      q := Instr (u, "sdiv " & lt & " " & x & ", " & y);
      r := Instr (u, "srem " & lt & " " & x & ", " & y);
      c1 := Instr (u, "icmp ne " & lt & " " & r & ", 0");
      c2 := Instr (u, "xor " & lt & " " & r & ", " & y);
      c2 := Instr (u, "icmp slt " & lt & " " & c2 & ", 0");
      adj := Instr (u, "and i1 " & c1 & ", " & c2);
      IF is_div THEN
        c1 := Instr (u, "sub " & lt & " " & q & ", 1");
        res := Instr (u, "select i1 " & adj & ", " & lt & " " & c1
                           & ", " & lt & " " & q);
      ELSE
        c1 := Instr (u, "add " & lt & " " & r & ", " & y);
        res := Instr (u, "select i1 " & adj & ", " & lt & " " & c1
                           & ", " & lt & " " & r);
      END;
    END;
    IF guard AND is_div THEN
      c1 := Instr (u, "sub " & lt & " 0, " & x);
      res := Instr (u, "select i1 " & m1 & ", " & lt & " " & c1
                         & ", " & lt & " " & res);
    END;
    Push (u, t, res);
  END DivMod;

PROCEDURE div (u: U; t: IType; a, b: Sign) =
  BEGIN DivMod (u, t, a, b, TRUE) END div;

PROCEDURE mod (u: U; t: IType; a, b: Sign) =
  BEGIN DivMod (u, t, a, b, FALSE) END mod;

(*------------------------------------------------------------- sets ---*)

(* Sets larger than a word are arrays of 64-bit words in memory; the
   operations on them call small internal helper functions, written
   into the unit once each. *)

PROCEDURE SetWords (u: U; s: ByteSize): TEXT =
  BEGIN
    IF s MOD 8 # 0 THEN
      Fatal (u, "set size is not a multiple of 8 bytes: " & Fmt.Int (s));
    END;
    RETURN Fmt.Int (s DIV 8);
  END SetWords;

PROCEDURE SetLoopHelper (u: U; name, op: TEXT) =
  (* a[i] := b[i] op c[i] for i in [0..n-1]; "op" computes %r from
     %vb and %vc. *)
  BEGIN
    IF HaveHelper (u, name) THEN RETURN END;
    AddHelper (u, name,
      "define internal void " & name & "(i64 %n, ptr %a, ptr %b, ptr %c) {\n"
      & "entry:\n  br label %loop\n"
      & "loop:\n  %i = phi i64 [ 0, %entry ], [ %i1, %body ]\n"
      & "  %done = icmp uge i64 %i, %n\n"
      & "  br i1 %done, label %exit, label %body\n"
      & "body:\n"
      & "  %pb = getelementptr i64, ptr %b, i64 %i\n"
      & "  %pc = getelementptr i64, ptr %c, i64 %i\n"
      & "  %pa = getelementptr i64, ptr %a, i64 %i\n"
      & "  %vb = load i64, ptr %pb, align 1\n"
      & "  %vc = load i64, ptr %pc, align 1\n"
      & op
      & "  store i64 %r, ptr %pa, align 1\n"
      & "  %i1 = add i64 %i, 1\n"
      & "  br label %loop\n"
      & "exit:\n  ret void\n}\n");
  END SetLoopHelper;

PROCEDURE SetBinary (u: U; s: ByteSize; name, op: TEXT) =
  VAR c := PopAs (u, Type.Addr);  b := PopAs (u, Type.Addr);
      a := PopAs (u, Type.Addr);
  BEGIN
    SetLoopHelper (u, name, op);
    Emit (u, "call void " & name & "(i64 " & SetWords (u, s) & ", ptr " & a
               & ", ptr " & b & ", ptr " & c & ")");
  END SetBinary;

PROCEDURE set_union (u: U; s: ByteSize) =
  BEGIN
    SetBinary (u, s, "@m3_set_union", "  %r = or i64 %vb, %vc\n");
  END set_union;

PROCEDURE set_difference (u: U; s: ByteSize) =
  BEGIN
    SetBinary (u, s, "@m3_set_difference",
               "  %nc = xor i64 %vc, -1\n  %r = and i64 %vb, %nc\n");
  END set_difference;

PROCEDURE set_intersection (u: U; s: ByteSize) =
  BEGIN
    SetBinary (u, s, "@m3_set_intersection", "  %r = and i64 %vb, %vc\n");
  END set_intersection;

PROCEDURE set_sym_difference (u: U; s: ByteSize) =
  BEGIN
    SetBinary (u, s, "@m3_set_sym_difference", "  %r = xor i64 %vb, %vc\n");
  END set_sym_difference;

PROCEDURE SetTestHelper (u: U; name, op: TEXT) =
  (* Returns 1 if, for every i in [0..n-1], the %x that "op" computes
     from %va and %vb is zero. *)
  BEGIN
    IF HaveHelper (u, name) THEN RETURN END;
    AddHelper (u, name,
      "define internal i1 " & name & "(i64 %n, ptr %a, ptr %b) {\n"
      & "entry:\n  br label %loop\n"
      & "loop:\n  %i = phi i64 [ 0, %entry ], [ %i1, %body ]\n"
      & "  %done = icmp uge i64 %i, %n\n"
      & "  br i1 %done, label %yes, label %body\n"
      & "body:\n"
      & "  %pa = getelementptr i64, ptr %a, i64 %i\n"
      & "  %pb = getelementptr i64, ptr %b, i64 %i\n"
      & "  %va = load i64, ptr %pa, align 1\n"
      & "  %vb = load i64, ptr %pb, align 1\n"
      & op
      & "  %z = icmp eq i64 %x, 0\n"
      & "  %i1 = add i64 %i, 1\n"
      & "  br i1 %z, label %loop, label %no\n"
      & "yes:\n  ret i1 true\n"
      & "no:\n  ret i1 false\n}\n");
  END SetTestHelper;

PROCEDURE SetTest (u: U; name, n, a, b: TEXT): TEXT =
  BEGIN
    IF Text.Equal (name, "@m3_set_eq")
      THEN SetTestHelper (u, name, "  %x = xor i64 %va, %vb\n");
      ELSE SetTestHelper (u, name, "  %nb = xor i64 %vb, -1\n"
                                     & "  %x = and i64 %va, %nb\n");
    END;
    RETURN Instr (u, "call i1 " & name & "(i64 " & n & ", ptr " & a
                       & ", ptr " & b & ")");
  END SetTest;

PROCEDURE set_compare (u: U; s: ByteSize; op: CompareOp; t: IType) =
  (* s1.t := (s1.B op s0.B); pop *)
  VAR b := PopAs (u, Type.Addr);  a := PopAs (u, Type.Addr);
      n := SetWords (u, s);  r, x, y: TEXT;
  BEGIN
    IF op = CompareOp.GT OR op = CompareOp.GE THEN
      x := a;  a := b;  b := x;
      IF op = CompareOp.GT THEN op := CompareOp.LT ELSE op := CompareOp.LE END;
    END;
    CASE op OF
    | CompareOp.EQ => r := SetTest (u, "@m3_set_eq", n, a, b);
    | CompareOp.NE =>
        r := SetTest (u, "@m3_set_eq", n, a, b);
        r := Instr (u, "xor i1 " & r & ", true");
    | CompareOp.LE => r := SetTest (u, "@m3_set_le", n, a, b);
    | CompareOp.LT =>
        x := SetTest (u, "@m3_set_le", n, a, b);
        y := SetTest (u, "@m3_set_eq", n, a, b);
        y := Instr (u, "xor i1 " & y & ", true");
        r := Instr (u, "and i1 " & x & ", " & y);
    ELSE <*ASSERT FALSE*>
    END;
    Push (u, t, Instr (u, "zext i1 " & r & " to " & LType (t)));
  END set_compare;

PROCEDURE SetWordAddr (u: U; set, elt: TEXT; VAR bit: TEXT): TEXT =
  (* The address of the word of "set" holding element "elt" (an i64),
     and in "bit", the bit number within it. *)
  VAR w := Instr (u, "udiv i64 " & elt & ", 64");
  BEGIN
    bit := Instr (u, "urem i64 " & elt & ", 64");
    RETURN Instr (u, "getelementptr i64, ptr " & set & ", i64 " & w);
  END SetWordAddr;

PROCEDURE set_member (u: U; <*UNUSED*> s: ByteSize; t: IType) =
  (* s1.t := (s0.t IN s1.B); pop *)
  VAR e := PopAs (u, Type.Word64);  set := PopAs (u, Type.Addr);
      bit: TEXT;  a := SetWordAddr (u, set, e, bit);  v: TEXT;
  BEGIN
    v := Instr (u, "load i64, ptr " & a & ", align 1");
    v := Instr (u, "lshr i64 " & v & ", " & bit);
    v := Instr (u, "and i64 " & v & ", 1");
    Push (u, t, Cvt (u, v, Type.Word64, t));
  END set_member;

PROCEDURE set_singleton (u: U; <*UNUSED*> s: ByteSize; <*UNUSED*> t: IType) =
  (* s1.A[s0.t] := 1; pop(2) *)
  VAR e := PopAs (u, Type.Word64);  set := PopAs (u, Type.Addr);
      bit: TEXT;  a := SetWordAddr (u, set, e, bit);  v, m: TEXT;
  BEGIN
    v := Instr (u, "load i64, ptr " & a & ", align 1");
    m := Instr (u, "shl i64 1, " & bit);
    v := Instr (u, "or i64 " & v & ", " & m);
    Emit (u, "store i64 " & v & ", ptr " & a & ", align 1");
  END set_singleton;

PROCEDURE set_range (u: U; <*UNUSED*> s: ByteSize; t: IType) =
  (* s2.A[s1.t..s0.t] := 1's; pop(3) *)
  VAR hi := PopAs (u, t);  lo := PopAs (u, t);  set := PopAs (u, Type.Addr);
      name := "@m3_set_range";
  BEGIN
    IF NOT HaveHelper (u, name) THEN
      AddHelper (u, name,
        "define internal void " & name & "(ptr %a, i64 %lo, i64 %hi) {\n"
        & "entry:\n  br label %loop\n"
        & "loop:\n  %i = phi i64 [ %lo, %entry ], [ %i1, %body ]\n"
        & "  %done = icmp sgt i64 %i, %hi\n"
        & "  br i1 %done, label %exit, label %body\n"
        & "body:\n"
        & "  %w = udiv i64 %i, 64\n"
        & "  %bit = urem i64 %i, 64\n"
        & "  %p = getelementptr i64, ptr %a, i64 %w\n"
        & "  %v = load i64, ptr %p, align 1\n"
        & "  %m = shl i64 1, %bit\n"
        & "  %v1 = or i64 %v, %m\n"
        & "  store i64 %v1, ptr %p, align 1\n"
        & "  %i1 = add i64 %i, 1\n"
        & "  br label %loop\n"
        & "exit:\n  ret void\n}\n");
    END;
    Emit (u, "call void " & name & "(ptr " & set & ", i64 "
               & Cvt (u, lo, t, Type.Int64) & ", i64 "
               & Cvt (u, hi, t, Type.Int64) & ")");
  END set_range;

(*----------------------------------------------------- bit operations ---*)

PROCEDURE not (u: U; t: IType) =
  VAR a := PopAs (u, t);
  BEGIN
    Push (u, t, Instr (u, "xor " & LType (t) & " " & a & ", -1"));
  END not;

PROCEDURE and (u: U; t: IType) =
  BEGIN Binary (u, t, "and", "") END and;

PROCEDURE or (u: U; t: IType) =
  BEGIN Binary (u, t, "or", "") END or;

PROCEDURE xor (u: U; t: IType) =
  BEGIN Binary (u, t, "xor", "") END xor;

PROCEDURE Select (u: U; t: Type; c, a, b: TEXT): TEXT =
  VAR lt := LType (t);
  BEGIN
    RETURN Instr (u, "select i1 " & c & ", " & lt & " " & a & ", "
                       & lt & " " & b);
  END Select;

PROCEDURE ShiftOp (u: U; t: Type; op, x, n: TEXT): TEXT =
  (* x op n, or 0 if n >= the bit size (unsigned). *)
  VAR lt := LType (t);  big, r: TEXT;
  BEGIN
    big := Instr (u, "icmp uge " & lt & " " & n & ", " & Bits (t));
    r := Instr (u, op & " " & lt & " " & x & ", " & n);
    RETURN Select (u, t, big, "0", r);
  END ShiftOp;

PROCEDURE shift_left (u: U; t: IType) =
  VAR n := PopAs (u, t);  x := PopAs (u, t);
  BEGIN
    Push (u, t, ShiftOp (u, t, "shl", x, n));
  END shift_left;

PROCEDURE shift_right (u: U; t: IType) =
  VAR n := PopAs (u, t);  x := PopAs (u, t);
  BEGIN
    Push (u, t, ShiftOp (u, t, "lshr", x, n));
  END shift_right;

PROCEDURE shift (u: U; t: IType) =
  (* Positive counts shift left, negative counts right. *)
  VAR n := PopAs (u, t);  x := PopAs (u, t);  lt := LType (t);
      neg, pos, l, r, v, an, big: TEXT;  rop := "lshr";
  BEGIN
    IF IsSigned (t) THEN rop := "ashr" END;   (* as M3C *)
    neg := Instr (u, "sub " & lt & " 0, " & n);
    pos := Instr (u, "icmp sgt " & lt & " " & n & ", 0");
    l := Instr (u, "shl " & lt & " " & x & ", " & n);
    r := Instr (u, rop & " " & lt & " " & x & ", " & neg);
    v := Select (u, t, pos, l, r);
    an := Select (u, t, pos, n, neg);
    big := Instr (u, "icmp uge " & lt & " " & an & ", " & Bits (t));
    Push (u, t, Select (u, t, big, "0", v));
  END shift;

PROCEDURE Funnel (u: U; t: IType; fn: TEXT; neg: BOOLEAN) =
  VAR n := PopAs (u, t);  x := PopAs (u, t);  lt := LType (t);
      name := "@llvm." & fn & "." & lt;
  BEGIN
    IF neg THEN n := Instr (u, "sub " & lt & " 0, " & n) END;
    AddDecl (u, name, "declare " & lt & " " & name & "(" & lt & ", " & lt
                        & ", " & lt & ")");
    Push (u, t, Instr (u, "call " & lt & " " & name & "(" & lt & " " & x
                            & ", " & lt & " " & x & ", " & lt & " " & n
                            & ")"));
  END Funnel;

PROCEDURE rotate (u: U; t: IType) =
  BEGIN Funnel (u, t, "fshl", FALSE) END rotate;

PROCEDURE rotate_left (u: U; t: IType) =
  BEGIN Funnel (u, t, "fshl", FALSE) END rotate_left;

PROCEDURE rotate_right (u: U; t: IType) =
  BEGIN Funnel (u, t, "fshr", FALSE) END rotate_right;

PROCEDURE widen (u: U; sign: BOOLEAN) =
  VAR a := PopAs (u, Type.Int32);
  BEGIN
    IF sign
      THEN Push (u, Type.Int64, Instr (u, "sext i32 " & a & " to i64"));
      ELSE Push (u, Type.Word64, Instr (u, "zext i32 " & a & " to i64"));
    END;
  END widen;

PROCEDURE chop (u: U) =
  VAR a := PopAs (u, Type.Int64);
  BEGIN
    Push (u, Type.Int32, Instr (u, "trunc i64 " & a & " to i32"));
  END chop;

PROCEDURE Extract (u: U; t: IType; sign: BOOLEAN; x, off, cnt: TEXT) =
  (* Word.Extract (x, off, cnt), sign-extended if "sign". *)
  VAR lt := LType (t);  v, m, s: TEXT;
  BEGIN
    v := ShiftOp (u, t, "lshr", x, off);
    m := Instr (u, "xor " & lt & " " & ShiftOp (u, t, "shl", "-1", cnt)
                     & ", -1");
    v := Instr (u, "and " & lt & " " & v & ", " & m);
    IF sign THEN
      s := Instr (u, "sub " & lt & " " & Bits (t) & ", " & cnt);
      v := ShiftOp (u, t, "shl", v, s);
      v := Instr (u, "ashr " & lt & " " & v & ", " & s);
      (* a count of zero gives zero *)
      m := Instr (u, "icmp eq " & lt & " " & cnt & ", 0");
      v := Select (u, t, m, "0", v);
    END;
    Push (u, t, v);
  END Extract;

PROCEDURE extract (u: U; t: IType; sign: BOOLEAN) =
  VAR cnt := PopAs (u, t);  off := PopAs (u, t);  x := PopAs (u, t);
  BEGIN
    Extract (u, t, sign, x, off, cnt);
  END extract;

PROCEDURE extract_n (u: U; t: IType; sign: BOOLEAN; n: CARDINAL) =
  VAR off := PopAs (u, t);  x := PopAs (u, t);
  BEGIN
    Extract (u, t, sign, x, off, Fmt.Int (n));
  END extract_n;

PROCEDURE extract_mn (u: U; t: IType; sign: BOOLEAN; m, n: CARDINAL) =
  VAR x := PopAs (u, t);  lt := LType (t);  bits := IntBits (t);  v: TEXT;
  BEGIN
    IF n = 0 OR m >= bits THEN Push (u, t, "0"); RETURN END;
    n := MIN (n, bits - m);
    IF sign THEN
      v := x;
      IF bits - m - n > 0 THEN
        v := Instr (u, "shl " & lt & " " & v & ", " & Fmt.Int (bits - m - n));
      END;
      IF bits - n > 0 THEN
        v := Instr (u, "ashr " & lt & " " & v & ", " & Fmt.Int (bits - n));
      END;
    ELSE
      v := x;
      IF m > 0 THEN
        v := Instr (u, "lshr " & lt & " " & v & ", " & Fmt.Int (m));
      END;
      IF n < bits THEN
        v := Instr (u, "and " & lt & " " & v & ", " & LowMask (bits, n));
      END;
    END;
    Push (u, t, v);
  END extract_mn;

PROCEDURE Insert (u: U; t: IType; x, y, off, cnt: TEXT) =
  (* Word.Insert (x, y, off, cnt) *)
  VAR lt := LType (t);  m, nm, v, w: TEXT;
  BEGIN
    m := Instr (u, "xor " & lt & " " & ShiftOp (u, t, "shl", "-1", cnt)
                     & ", -1");
    m := ShiftOp (u, t, "shl", m, off);
    nm := Instr (u, "xor " & lt & " " & m & ", -1");
    v := ShiftOp (u, t, "shl", y, off);
    v := Instr (u, "and " & lt & " " & v & ", " & m);
    w := Instr (u, "and " & lt & " " & x & ", " & nm);
    Push (u, t, Instr (u, "or " & lt & " " & v & ", " & w));
  END Insert;

PROCEDURE insert (u: U; t: IType) =
  VAR cnt := PopAs (u, t);  off := PopAs (u, t);  y := PopAs (u, t);
      x := PopAs (u, t);
  BEGIN
    Insert (u, t, x, y, off, cnt);
  END insert;

PROCEDURE insert_n (u: U; t: IType; n: CARDINAL) =
  VAR off := PopAs (u, t);  y := PopAs (u, t);  x := PopAs (u, t);
  BEGIN
    Insert (u, t, x, y, off, Fmt.Int (n));
  END insert_n;

PROCEDURE insert_mn (u: U; t: IType; m, n: CARDINAL) =
  VAR y := PopAs (u, t);  x := PopAs (u, t);  lt := LType (t);
      bits := IntBits (t);  mask: Word.T;  v, w: TEXT;
  BEGIN
    IF n = 0 OR m >= bits THEN Push (u, t, x); RETURN END;
    n := MIN (n, bits - m);
    IF n >= BITSIZE (Word.T)
      THEN mask := Word.Not (0);
      ELSE mask := Word.Minus (Word.LeftShift (1, n), 1);
    END;
    mask := Word.LeftShift (mask, m);
    v := y;
    IF m > 0 THEN v := Instr (u, "shl " & lt & " " & v & ", " & Fmt.Int (m)) END;
    v := Instr (u, "and " & lt & " " & v & ", " & SignedConst (bits, mask));
    w := Instr (u, "and " & lt & " " & x & ", "
                     & SignedConst (bits, Word.Not (mask)));
    Push (u, t, Instr (u, "or " & lt & " " & v & ", " & w));
  END insert_mn;

PROCEDURE swap (u: U; <*UNUSED*> a, b: Type) =
  VAR x := Pop (u);  y := Pop (u);
  BEGIN
    Push (u, x.type, x.val);
    Push (u, y.type, y.val);
  END swap;

(*-------------------------------------------------- copying and zeroing ---*)

PROCEDURE MemCopy (u: U; dst, src, len: TEXT; overlap: BOOLEAN) =
  VAR fn := "memcpy";
  BEGIN
    IF overlap THEN fn := "memmove" END;
    UseMemIntrinsic (u, fn);
    Emit (u, "call void @llvm." & fn & ".p0.p0.i64(ptr " & dst & ", ptr "
               & src & ", i64 " & len & ", i1 false)");
  END MemCopy;

PROCEDURE MemZero (u: U; dst, len: TEXT) =
  BEGIN
    UseMemIntrinsic (u, "memset");
    Emit (u, "call void @llvm.memset.p0.i64(ptr " & dst & ", i8 0, i64 "
               & len & ", i1 false)");
  END MemZero;

PROCEDURE copy (u: U; n: INTEGER; t: MType; overlap: BOOLEAN) =
  (* Mem[s1.A:n] := Mem[s0.A:n]; pop(2) *)
  VAR src := PopAs (u, Type.Addr);  dst := PopAs (u, Type.Addr);
  BEGIN
    MemCopy (u, dst, src, Fmt.Int (n * TypeBytes (t)), overlap);
  END copy;

PROCEDURE copy_n (u: U; z: IType; t: MType; overlap: BOOLEAN) =
  (* Mem[s2.A:s0.z] := Mem[s1.A:s0.z]; pop(3) *)
  VAR n := PopAs (u, z);  src := PopAs (u, Type.Addr);
      dst := PopAs (u, Type.Addr);  len: TEXT;
  BEGIN
    len := Instr (u, "mul i64 " & Cvt (u, n, z, Type.Int64) & ", "
                       & Fmt.Int (TypeBytes (t)));
    MemCopy (u, dst, src, len, overlap);
  END copy_n;

PROCEDURE zero (u: U; n: INTEGER; t: MType) =
  VAR dst := PopAs (u, Type.Addr);
  BEGIN
    MemZero (u, dst, Fmt.Int (n * TypeBytes (t)));
  END zero;

PROCEDURE zero_n (u: U; z: IType; t: MType) =
  VAR n := PopAs (u, z);  dst := PopAs (u, Type.Addr);  len: TEXT;
  BEGIN
    len := Instr (u, "mul i64 " & Cvt (u, n, z, Type.Int64) & ", "
                       & Fmt.Int (TypeBytes (t)));
    MemZero (u, dst, len);
  END zero_n;

(*------------------------------------------------------- conversions ---*)

PROCEDURE loophole (u: U; from, two: ZType) =
  VAR x := Pop (u);  v := Cvt (u, x.val, x.type, from);
  BEGIN
    IF IsFloat (from) # IsFloat (two) AND TypeBytes (from) = TypeBytes (two)
      AND from # Type.Addr AND two # Type.Addr THEN
      v := Instr (u, "bitcast " & LType (from) & " " & v & " to "
                       & LType (two));
    ELSIF IsFloat (from) AND two = Type.Addr THEN
      v := Cvt (u, Instr (u, "bitcast " & LType (from) & " " & v & " to i"
                               & Fmt.Int (FloatBits (from))),
                IntOfBits (FloatBits (from)), two);
    ELSIF from = Type.Addr AND IsFloat (two) THEN
      v := Instr (u, "bitcast " & LType (IntOfBits (FloatBits (two))) & " "
                       & Cvt (u, v, from, IntOfBits (FloatBits (two)))
                       & " to " & LType (two));
    ELSE
      v := Cvt (u, v, from, two);
    END;
    Push (u, two, v);
  END loophole;

PROCEDURE IntOfBits (bits: INTEGER): Type =
  BEGIN
    CASE bits OF
    | 32 => RETURN Type.Word32;
    | 64 => RETURN Type.Word64;
    ELSE RETURN Type.Word64;
    END;
  END IntOfBits;

(*---------------------------------------------------- runtime checks ---*)

PROCEDURE abort (u: U; code: RuntimeError) =
  BEGIN
    IF u.in_call THEN u.call_aborted := TRUE END;
    Fault (u, code);
  END abort;

PROCEDURE Top (u: U; t: Type): TEXT =
  (* s0 converted to "t", without popping it. *)
  VAR x := Pop (u);  v := Cvt (u, x.val, x.type, t);
  BEGIN
    Push (u, x.type, x.val);
    RETURN v;
  END Top;

PROCEDURE check_nil (u: U; code: RuntimeError) =
  VAR a := Top (u, Type.Addr);
  BEGIN
    FaultIf (u, Instr (u, "icmp eq ptr " & a & ", null"), code);
  END check_nil;

PROCEDURE check_lo (u: U; t: IType; READONLY i: Target.Int;
                    code: RuntimeError) =
  VAR a := Top (u, t);
  BEGIN
    FaultIf (u, Instr (u, Pred (t, CompareOp.LT) & " " & LType (t) & " " & a
                            & ", " & IntText (i)), code);
  END check_lo;

PROCEDURE check_hi (u: U; t: IType; READONLY i: Target.Int;
                    code: RuntimeError) =
  VAR a := Top (u, t);
  BEGIN
    FaultIf (u, Instr (u, Pred (t, CompareOp.GT) & " " & LType (t) & " " & a
                            & ", " & IntText (i)), code);
  END check_hi;

PROCEDURE check_range (u: U; t: IType; READONLY a, b: Target.Int;
                       code: RuntimeError) =
  VAR x := Top (u, t);  lt := LType (t);  lo, hi: TEXT;
  BEGIN
    lo := Instr (u, Pred (t, CompareOp.LT) & " " & lt & " " & x & ", "
                      & IntText (a));
    hi := Instr (u, Pred (t, CompareOp.GT) & " " & lt & " " & x & ", "
                      & IntText (b));
    FaultIf (u, Instr (u, "or i1 " & lo & ", " & hi), code);
  END check_range;

PROCEDURE check_index (u: U; t: IType; code: RuntimeError) =
  (* IF NOT (0 <= s1.t < s0.t) THEN abort(code); pop *)
  VAR n := PopAs (u, t);  i := Top (u, t);  lt := LType (t);
  BEGIN
    FaultIf (u, Instr (u, "icmp ule " & lt & " " & n & ", " & i), code);
  END check_index;

PROCEDURE check_eq (u: U; t: IType; code: RuntimeError) =
  VAR b := PopAs (u, t);  a := PopAs (u, t);
  BEGIN
    FaultIf (u, Instr (u, "icmp ne " & LType (t) & " " & a & ", " & b), code);
  END check_eq;

(*------------------------------------------------- address arithmetic ---*)

PROCEDURE add_offset (u: U; i: INTEGER) =
  VAR a := PopAs (u, Type.Addr);
  BEGIN
    Push (u, Type.Addr, Offset (u, a, i));
  END add_offset;

PROCEDURE index_address (u: U; t: IType; size: INTEGER) =
  (* s1.A := s1.A + s0.t * size; pop *)
  VAR i := PopAs (u, t);  a := PopAs (u, Type.Addr);
  BEGIN
    IF size = 0 THEN Push (u, Type.Addr, a); RETURN END;
    IF size < 0 THEN
      (* Negative sizes occur (m3core's String8, DragonInt); an array
         type can't have one, so scale the index instead. *)
      Push (u, Type.Addr,
            Instr (u, "getelementptr i8, ptr " & a & ", i64 "
                        & Instr (u, "mul i64 " & Cvt (u, i, t, Type.Int64)
                                      & ", " & Fmt.Int (size))));
      RETURN;
    END;
    Push (u, Type.Addr,
          Instr (u, "getelementptr [" & Fmt.Int (size) & " x i8], ptr " & a
                      & ", i64 " & Cvt (u, i, t, Type.Int64)));
  END index_address;

(*----------------------------------------------- indirect calls etc. ---*)

PROCEDURE start_call_indirect (u: U; <*UNUSED*> t: Type;
                               <*UNUSED*> cc: CallingConvention) =
  BEGIN
    StartCall (u, NIL);
  END start_call_indirect;

PROCEDURE SlotName (u: U): TEXT =
  (* The front end pops the static link of an indirect call only on the
     path that calls a closure, so it is kept in memory: a slot that is
     NIL on the other path.  Callees that are not nested ignore the
     extra argument. *)
  BEGIN
    IF u.call_sl = NIL THEN
      u.call_sl := "%slink." & Fmt.Int (u.next_tmp);
      INC (u.next_tmp);
      Wr.PutText (u.allocas, "  " & u.call_sl & " = alloca ptr, align 8"
                               & Wr.EOL & "  store ptr null, ptr "
                               & u.call_sl & ", align 8" & Wr.EOL);
    END;
    RETURN u.call_sl;
  END SlotName;

PROCEDURE call_indirect (u: U; t: Type; <*UNUSED*> cc: CallingConvention) =
  VAR f := PopAs (u, Type.Addr);  r, call, attr := "";
  BEGIN
    IF u.call_aborted THEN
      IF t # Type.Void THEN Push (u, StackType (t), "poison") END;
      EndCall (u);
      RETURN;
    END;
    IF u.call_sl # NIL THEN
      r := Instr (u, "load ptr, ptr " & u.call_sl & ", align 8");
      Emit (u, "store ptr null, ptr " & u.call_sl & ", align 8");
      AddArg (u, "ptr " & r);
    END;
    attr := ExtAttr (t);
    IF Text.Length (attr) > 0 THEN attr := Text.Sub (attr, 1) & " " END;
    call := "call " & attr & LType (t) & " " & f & "(" & u.call_args & ")";
    IF t = Type.Void THEN
      EmitCall (u, NIL, call);
    ELSE
      r := NewTemp (u);
      EmitCall (u, r, call);
      Push (u, StackType (t), Cvt (u, r, t, StackType (t)));
    END;
    EndCall (u);
  END call_indirect;

PROCEDURE pop_struct (u: U; <*UNUSED*> typeid: TypeUID;
                      <*UNUSED*> size: ByteSize;
                      <*UNUSED*> align: Alignment) =
  (* Structures are passed by reference; the callee copies them. *)
  VAR a := PopAs (u, Type.Addr);
  BEGIN
    IF NOT u.in_call THEN Fatal (u, "pop_struct outside a call") END;
    u.call_last := a;
    AddArg (u, "ptr " & a);
  END pop_struct;

PROCEDURE pop_static_link (u: U) =
  BEGIN
    VAR sl := PopAs (u, Type.Addr); BEGIN
      Emit (u, "store ptr " & sl & ", ptr " & SlotName (u) & ", align 8");
    END;
  END pop_static_link;

PROCEDURE load_static_link (u: U; proc: Proc) =
  VAR p := NARROW (proc, LProc);
  BEGIN
    IF p.level = 0
      THEN Push (u, Type.Addr, "null");
      ELSE Push (u, Type.Addr, FrameOf (u, p.level - 1));
    END;
  END load_static_link;

(*------------------------------------------------- Phase 3: static data ---*)

PROCEDURE init_label (<*UNUSED*> u: U; <*UNUSED*> o: ByteOffset;
                      <*UNUSED*> value: Label) =
  (* Only the old stack walker reads these words.  Like the C back end
     (M3C.m3) and M3CG_LLVM, leave them zero. *)
  BEGIN
  END init_label;

PROCEDURE init_offset (<*UNUSED*> u: U; <*UNUSED*> o: ByteOffset;
                       <*UNUSED*> value: Var) =
  (* As init_label: frame offsets for the old stack walker. *)
  BEGIN
  END init_offset;

(*----------------------------------------------------- Phase 3: atomics ---*)

PROCEDURE Ordering (o: MemoryOrder): TEXT =
  BEGIN
    CASE o OF
    | MemoryOrder.Relaxed        => RETURN "monotonic";
    | MemoryOrder.Release        => RETURN "release";
    | MemoryOrder.Acquire        => RETURN "acquire";
    | MemoryOrder.AcquireRelease => RETURN "acq_rel";
    | MemoryOrder.Sequential     => RETURN "seq_cst";
    END;
  END Ordering;

PROCEDURE LoadOrdering (o: MemoryOrder): TEXT =
  (* An atomic load can't be "release" or "acq_rel". *)
  BEGIN
    CASE o OF
    | MemoryOrder.Release        => RETURN "monotonic";
    | MemoryOrder.AcquireRelease => RETURN "acquire";
    ELSE RETURN Ordering (o);
    END;
  END LoadOrdering;

PROCEDURE StoreOrdering (o: MemoryOrder): TEXT =
  (* An atomic store can't be "acquire" or "acq_rel". *)
  BEGIN
    CASE o OF
    | MemoryOrder.Acquire        => RETURN "monotonic";
    | MemoryOrder.AcquireRelease => RETURN "release";
    ELSE RETURN Ordering (o);
    END;
  END StoreOrdering;

PROCEDURE AtomicType (u: U; t: MType): Type =
  (* The memory type the atomic instruction works on.  Integer
     arithmetic on addresses goes through an integer of the same size. *)
  BEGIN
    IF IsFloat (t) THEN
      Fatal (u, "atomic operation on a floating-point type");
    END;
    RETURN t;
  END AtomicType;

PROCEDURE AsMem (u: U; x: Operand; z: ZType; t: MType): TEXT =
  (* Operand "x" converted to the memory type "t". *)
  BEGIN
    RETURN Cvt (u, Cvt (u, x.val, x.type, z), z, t);
  END AsMem;

PROCEDURE store_ordered (u: U; z: ZType; t: MType; order: MemoryOrder) =
  (* Mem [s1.A].t := s0.z; pop (2) *)
  VAR x := Pop (u);  a := PopAs (u, Type.Addr);  m := AtomicType (u, t);
  BEGIN
    Emit (u, "store atomic " & LType (m) & " " & AsMem (u, x, z, m)
               & ", ptr " & a & " " & StoreOrdering (order) & ", align "
               & Fmt.Int (NatAlign (m)));
  END store_ordered;

PROCEDURE load_ordered (u: U; t: MType; z: ZType; order: MemoryOrder) =
  (* s0.z := Mem [s0.A].t *)
  VAR a := PopAs (u, Type.Addr);  m := AtomicType (u, t);  r: TEXT;
  BEGIN
    r := Instr (u, "load atomic " & LType (m) & ", ptr " & a & " "
                     & LoadOrdering (order) & ", align "
                     & Fmt.Int (NatAlign (m)));
    Push (u, z, Cvt (u, r, m, z));
  END load_ordered;

PROCEDURE exchange (u: U; t: MType; z: ZType; order: MemoryOrder) =
  (* tmp := Mem [s1.A].t;  Mem [s1.A].t := s0.z;  s0.z := tmp;  pop *)
  VAR x := Pop (u);  a := PopAs (u, Type.Addr);  m := AtomicType (u, t);
      r: TEXT;
  BEGIN
    r := Instr (u, "atomicrmw xchg ptr " & a & ", " & LType (m) & " "
                     & AsMem (u, x, z, m) & " " & Ordering (order)
                     & ", align " & Fmt.Int (NatAlign (m)));
    Push (u, z, Cvt (u, r, m, z));
  END exchange;

PROCEDURE compare_exchange (u: U; t: MType; z: ZType; r: IType;
                            success, failure: MemoryOrder) =
  (* As the front end (builtinAtomic/CompareSwap.mg) uses it: s2 is the
     address of the variable, s1 the address of "expected", s0 the new
     value.  If Mem [s2.A].t = Mem [s1.A].t, store s0 into Mem [s2.A];
     otherwise store the value found into Mem [s1.A].  Replace the
     three operands with the success flag, of type "r". *)
  VAR x := Pop (u);  e := PopAs (u, Type.Addr);  a := PopAs (u, Type.Addr);
      m := AtomicType (u, t);  lt := LType (m);
      align := ", align " & Fmt.Int (NatAlign (m));
      fail_order := failure;  old, cx, ok: TEXT;
      fail_blk := NewBlock (u, "cxfail.");  done_blk := NewBlock (u, "cxdone.");
  BEGIN
    (* The failure ordering can't be "release" or "acq_rel". *)
    IF fail_order = MemoryOrder.Release THEN
      fail_order := MemoryOrder.Relaxed;
    ELSIF fail_order = MemoryOrder.AcquireRelease THEN
      fail_order := MemoryOrder.Acquire;
    END;
    old := Instr (u, "load " & lt & ", ptr " & e & align);
    cx := Instr (u, "cmpxchg ptr " & a & ", " & lt & " " & old & ", "
                      & lt & " " & AsMem (u, x, z, m) & " "
                      & Ordering (success) & " " & Ordering (fail_order)
                      & align);
    ok := Instr (u, "extractvalue { " & lt & ", i1 } " & cx & ", 1");
    EmitTerm (u, "br i1 " & ok & ", label %" & done_blk & ", label %"
                   & fail_blk);
    StartBlock (u, fail_blk);
    Emit (u, "store " & lt & " "
               & Instr (u, "extractvalue { " & lt & ", i1 } " & cx & ", 0")
               & ", ptr " & e & align);
    EmitTerm (u, "br label %" & done_blk);
    StartBlock (u, done_blk);
    Push (u, r, Instr (u, "zext i1 " & ok & " to " & LType (r)));
  END compare_exchange;

PROCEDURE fence (u: U; order: MemoryOrder) =
  BEGIN
    (* A relaxed fence has no effect, and LLVM rejects "fence monotonic". *)
    IF order # MemoryOrder.Relaxed THEN
      Emit (u, "fence " & Ordering (order));
    END;
  END fence;

PROCEDURE fetch_and_op (u: U; op: AtomicOp; t: MType; z: ZType;
                        order: MemoryOrder) =
  (* tmp := Mem [s1.A].t;  Mem [s1.A].t := tmp op s0.z;  s1.z := tmp;
     pop *)
  CONST OpName = ARRAY AtomicOp OF TEXT {"add", "sub", "or", "and", "xor"};
  VAR x := Pop (u);  a := PopAs (u, Type.Addr);  m := AtomicType (u, t);
      v, r: TEXT;
  BEGIN
    IF m = Type.Addr THEN
      (* atomicrmw arithmetic needs an integer type. *)
      v := Cvt (u, Cvt (u, x.val, x.type, z), z, Type.Word64);
      m := Type.Word64;
    ELSE
      v := AsMem (u, x, z, m);
    END;
    r := Instr (u, "atomicrmw " & OpName[op] & " ptr " & a & ", "
                     & LType (m) & " " & v & " " & Ordering (order)
                     & ", align " & Fmt.Int (NatAlign (m)));
    Push (u, z, Cvt (u, r, m, z));
  END fetch_and_op;

(*============================== Phase 7: zero-cost exceptions (ex_stack) ===*)
(* With M3_USE_STACK_WALKER the front end brackets the body of each TRY,
   TRY FINALLY and LOCK statement with start_try/end_try and follows it
   with "set_label (handler); landing_pad (handler)".  The runtime raises
   a Modula-3 exception by throwing a C++ "_M3Exc" (struct { void *act; },
   see RTStack__ThrowM3Exc), so, as in the C back end's "try { ... }
   catch (_M3Exc&)", every call in an open region becomes an LLVM invoke
   that unwinds to the region's landing pad, which catches _M3Exc with
   __gxx_personality_v0 and pushes its activation.

   The front end jumps to a region's handler label only through the
   landing pad (unmatched exceptions go to the enclosing handler's body,
   after its landing pad), so the landing pad needs no other entry. *)

PROCEDURE EmitCall (u: U; result, call: TEXT; mayRaise := TRUE) =
  (* Emit "result = call" ("call" alone if "result" is NIL), the text
     "call" starting with "call ".  Inside a try region it becomes an
     invoke that unwinds to the innermost region's landing pad. *)
  VAR cont, lhs := "";
  BEGIN
    IF result # NIL THEN lhs := result & " = " END;
    IF u.try_open = NIL OR NOT mayRaise THEN Emit (u, lhs & call); RETURN END;
    cont := NewBlock (u, "cont.");
    EmitTerm (u, lhs & "invoke" & Text.Sub (call, 4) & " to label %" & cont
                   & " unwind label %" & u.try_open.lpad);
    StartBlock (u, cont);
    u.cur_proc.has_eh := TRUE;
    UseEH (u);
  END EmitCall;

PROCEDURE UseEH (u: U) =
  (* Declare what invoke and landingpad need. *)
  BEGIN
    AddDecl (u, "@__gxx_personality_v0",
             "declare i32 @__gxx_personality_v0(...)");
    AddDecl (u, "@__cxa_begin_catch",
             "declare ptr @__cxa_begin_catch(ptr)");
    AddDecl (u, "@__cxa_end_catch", "declare void @__cxa_end_catch()");
    AddDecl (u, "@_ZTVN10__cxxabiv117__class_type_infoE",
             "@_ZTVN10__cxxabiv117__class_type_infoE = external global [0 x ptr]");
    (* typeinfo for "struct _M3Exc", as C++ emits it in every unit that
       catches it *)
    AddDecl (u, "@_ZTS6_M3Exc",
             "@_ZTS6_M3Exc = linkonce_odr constant [8 x i8] c\"6_M3Exc\\00\", align 1");
    AddDecl (u, "@_ZTI6_M3Exc",
             "@_ZTI6_M3Exc = linkonce_odr constant { ptr, ptr } { ptr getelementptr inbounds (ptr, ptr @_ZTVN10__cxxabiv117__class_type_infoE, i64 2), ptr @_ZTS6_M3Exc }, align 8");
  END UseEH;

PROCEDURE start_try (u: U) =
  BEGIN
    u.try_open := NEW (TryList, lpad := NewBlock (u, "lpad."),
                       next := u.try_open);
  END start_try;

PROCEDURE end_try (u: U) =
  BEGIN
    IF u.try_open = NIL THEN Fatal (u, "end_try without start_try") END;
    u.try_last := u.try_open;
    u.try_open := u.try_open.next;
    u.try_last.next := NIL;
  END end_try;

PROCEDURE NoteHandler (u: U; handler: Label) =
  (* An invoke's handler is that of the innermost open region. *)
  VAR r := u.try_open;
  BEGIN
    IF r = NIL THEN Fatal (u, "invoke outside a try region") END;
    IF r.handler = M3CG.No_label THEN
      r.handler := handler;
    ELSIF r.handler # handler THEN
      Fatal (u, "invoke: handler differs from its region's");
    END;
  END NoteHandler;

PROCEDURE invoke_direct (u: U; p: Proc; t: Type;
                         <*UNUSED*> next: Label; handler: Label) =
  (* The front end follows this with set_label (next). *)
  BEGIN
    NoteHandler (u, handler);
    call_direct (u, p, t);
  END invoke_direct;

PROCEDURE invoke_indirect (u: U; t: Type; cc: CallingConvention;
                           <*UNUSED*> next: Label; handler: Label) =
  BEGIN
    NoteHandler (u, handler);
    call_indirect (u, t, cc);
  END invoke_indirect;

PROCEDURE landing_pad (u: U; t: ZType; handler: Label;
                       <*UNUSED*> READONLY catches: ARRAY OF TypeUID) =
  (* Catch the _M3Exc thrown in the region end_try closed last and push
     its activation ("catches" is checked by the handler code). *)
  VAR r := u.try_last;  x, obj, act: TEXT;
  BEGIN
    IF r = NIL THEN Fatal (u, "landing_pad without a try region") END;
    IF r.handler # M3CG.No_label AND r.handler # handler THEN
      Fatal (u, "landing_pad: handler differs from its region's");
    END;
    u.try_last := NIL;
    (* The handler label's block has no other entry. *)
    IF NOT u.terminated THEN EmitTerm (u, "unreachable") END;
    StartBlock (u, r.lpad);
    u.cur_proc.has_eh := TRUE;
    UseEH (u);
    x := Instr (u, "landingpad { ptr, i32 } catch ptr @_ZTI6_M3Exc");
    obj := Instr (u, "extractvalue { ptr, i32 } " & x & ", 0");
    obj := Instr (u, "call ptr @__cxa_begin_catch(ptr " & obj & ")");
    act := Instr (u, "load ptr, ptr " & obj & ", align 8");
    Emit (u, "call void @__cxa_end_catch()");
    Push (u, t, act);
  END landing_pad;

BEGIN
END M3LLVMIR.
