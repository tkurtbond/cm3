(* See the file COPYRIGHT for a full description. *)

(* The mapping from M3CG types to DWARF follows the LLVM-library back end
   (m3-sys/llvm/llvm22/src/M3CG_LLVM.m3, DebugInit .. DebugGlobals), but
   writes the metadata as text:
   - Ordinals and floats become DIBasicTypes.  Subranges become basic
     types of their size, with the encoding of their base type, except
     that a subrange of an enumeration is the enumeration.
   - Records become structures; packed fields become bit fields.
   - Objects and opaque types are pointers to a structure.  The structure
     inherits from the supertype's (not from ROOT) and holds the fields
     at their offsets in the object.
   - Arrays carry their index bounds.  An open array is the dope vector:
     its data location and upper bound are DWARF expressions on the
     address of the dope vector.
   - REF types are pointers; procedure types are pointers to subroutine
     types; indirect and packed types are their target and base types.
     A variable whose type is indirect (a VAR parameter, for example)
     is located through a DW_OP_deref.
   The compile unit claims to be Modula-2 (DW_LANG_Modula2): gdb has no
   Modula-3 support and treats DW_LANG_Modula3 as a "minimal" language
   that cannot print sets, and prints BOOLEAN and small subranges as C
   would.  Its Modula-2 mode prints sets, TRUE/FALSE and POINTER TO, and
   accepts "p^", "a[i]" and "r.f" as Modula-3 does.  SetLanguage can
   make it claim to be C instead, for lldb. *)

MODULE M3LLVMIRDebug;

IMPORT Wr, TextWr, Text, Fmt, Thread, IntRefTbl, TextRefTbl;
IMPORT Pathname, Process, OSError, Target, TInt, ASCII;
IMPORT Bundle, M3LLVMIRBundle;  (* m3printers.py *)
FROM M3CG IMPORT TypeUID;

<*FATAL Wr.Failure, Thread.Alerted*>

CONST
  (* The UIDs of the built-in types (as signed 32-bit integers). *)
  UID_INTEGER  = 425470580;
  UID_LONGINT  = 89530742;
  UID_CARDINAL = -1746782238;
  UID_LONGCARD = -1662175513;
  UID_REAL     = 1222731122;
  UID_LONGREAL = -1795280138;
  UID_EXTENDED = -1629477661;
  UID_BOOLEAN  = 509158269;
  UID_CHAR     = 1457612899;
  UID_WIDECHAR = -1997260292;
  UID_MUTEX    = 356643957;
  UID_TEXT     = 1358456180;
  UID_UNTRACED_ROOT = -1987139703;
  UID_ROOT     = -1651526519;
  UID_REFANY   = 471614950;
  UID_ADDRESS  = 138420323;
  UID_RANGE_0_31 = 765876253;
  UID_RANGE_0_63 = 799234077;
  UID_NULL     = 1223456110;

TYPE
  Kind = {Basic,      (* a built-in scalar *)
          Address,    (* a built-in reference: a pointer to nothing *)
          Subrange, Enum, Array, OpenArray, Packed, Record, Set,
          Pointer, Indirect, Proc, Object, Opaque, Alias};

  DType = REF RECORD
    kind    : Kind;
    id      : TypeUID;
    name    : TEXT := NIL;     (* from declare_typename *)
    bits    : INTEGER := 0;
    enc     : TEXT := NIL;     (* Basic: the DW_ATE_ encoding *)
    min, max: Target.Int;      (* Subrange *)
    a       : TypeUID := 0;    (* the domain, target, element, base,
                                  supertype or result *)
    b       : TypeUID := 0;    (* Array: the index type *)
    n       : INTEGER := 0;    (* elements added so far *)
    fields  : REF ARRAY OF FieldInfo := NIL;   (* Record, Object *)
    elts    : REF ARRAY OF TEXT := NIL;        (* Enum *)
    formals : REF ARRAY OF TypeUID := NIL;     (* Proc *)
    offset  : INTEGER := 0;    (* Object: bit offset of its fields *)
    md      : TEXT := NIL;     (* the DI type, "!N" *)
    cls     : TEXT := NIL;     (* Object, Opaque: the structure *)
    methods : REF ARRAY OF FieldInfo := NIL;   (* Object: its new methods *)
    n_methods := 0;            (* methods added so far *)
    moffset := -1;             (* Object: bit offset of its methods in
                                  the method suite, < 0 if unknown *)
    suite   : TEXT := NIL;     (* Object: the method suite structure *)
  END;

  FieldInfo = RECORD
    name   : TEXT;
    offset : INTEGER;
    bits   : INTEGER;
    type   : TypeUID;
  END;

  (* Nodes defined by Finish. *)
  Deferred = OBJECT
    next: Deferred := NIL;
  METHODS
    define (t: T) := NIL;
  END;

  DSub = Deferred OBJECT
    ref, linkage, file: TEXT;
    line   : INTEGER;
    local  : BOOLEAN;
    result : TypeUID;
    params : REF ARRAY OF TypeUID;
  OVERRIDES
    define := DefineSub;
  END;

  DVar = Deferred OBJECT
    ref, expr, name, scope, file: TEXT;
    arg, line : INTEGER;
    type      : TypeUID;
  OVERRIDES
    define := DefineVar;
  END;

  DGlobal = Deferred OBJECT
    ref, name, file: TEXT;
    offset : INTEGER;   (* bits *)
    type   : TypeUID;
  OVERRIDES
    define := DefineGlobal;
  END;

REVEAL
  T = BRANDED "M3LLVMIRDebug.T" REF RECORD
    types    : IntRefTbl.T;
    files    : TextRefTbl.T;
    meta     : TextWr.T;          (* "!N = ..." lines *)
    next_md  : INTEGER := 0;
    cu       : TEXT;
    cur      : DType := NIL;      (* receives fields, elements, formals *)
    seen_const := FALSE;
    globals  : DType := NIL;      (* the module's data segment *)
    gves     : TEXT := "";        (* the compile unit's globals *)
    deferred : Deferred := NIL;
    widechar_bits := 16;
    unknown  : TEXT := NIL;       (* the type of untyped variables *)
    cwd      : TEXT := NIL;
  END;

PROCEDURE New (): T =
  VAR t := NEW (T);
  BEGIN
    t.types := NEW (IntRefTbl.Default).init ();
    t.files := NEW (TextRefTbl.Default).init ();
    t.meta := TextWr.New ();
    t.cu := Reserve (t);
    InitBuiltins (t);
    RETURN t;
  END New;

PROCEDURE Builtin (t: T; id: TypeUID; name: TEXT; bits: INTEGER;
                   enc: TEXT := NIL) =
  VAR d := NEW (DType, id := id, name := name, bits := bits, enc := enc);
  BEGIN
    IF enc = NIL
      THEN d.kind := Kind.Address;
      ELSE d.kind := Kind.Basic;
    END;
    EVAL t.types.put (id, d);
  END Builtin;

PROCEDURE InitBuiltins (t: T) =
  CONST S = "DW_ATE_signed";  U = "DW_ATE_unsigned";  F = "DW_ATE_float";
  VAR
    int := Target.Integer.size;
    ptr := Target.Address.size;
    ext := Target.Extended.size;
    ext_name := "EXTENDED";
  BEGIN
    (* gdb picks a float format from the name and size; a 128-bit
       EXTENDED is IEEE quad precision, which gdb knows as _Float128. *)
    IF ext = 128 THEN ext_name := "_Float128" END;
    Builtin (t, UID_INTEGER,  "INTEGER",  int, S);
    Builtin (t, UID_CARDINAL, "CARDINAL", int, S);
    Builtin (t, UID_LONGINT,  "LONGINT",  64, S);
    Builtin (t, UID_LONGCARD, "LONGCARD", 64, S);
    Builtin (t, UID_BOOLEAN,  "BOOLEAN",  8, "DW_ATE_boolean");
    Builtin (t, UID_CHAR,     "CHAR",     8, "DW_ATE_unsigned_char");
    Builtin (t, UID_WIDECHAR, "WIDECHAR", 16, U);   (* see WidecharSize *)
    Builtin (t, UID_REAL,     "REAL",     32, F);
    Builtin (t, UID_LONGREAL, "LONGREAL", 64, F);
    Builtin (t, UID_EXTENDED, ext_name,   ext, F);
    Builtin (t, UID_RANGE_0_31, "[0..31]", int, U);
    Builtin (t, UID_RANGE_0_63, "[0..63]", int, U);
    Builtin (t, UID_ADDRESS,  "ADDRESS",  ptr);
    Builtin (t, UID_REFANY,   "REFANY",   ptr);
    Builtin (t, UID_ROOT,     "ROOT",     ptr);
    Builtin (t, UID_UNTRACED_ROOT, "UNTRACED_ROOT", ptr);
    Builtin (t, UID_NULL,     "NULL",     ptr);
    Builtin (t, UID_TEXT,     "TEXT",     ptr);
    Builtin (t, UID_MUTEX,    "MUTEX",    ptr);
  END InitBuiltins;

(*---------------------------------------------- M3CG type declarations ---*)

PROCEDURE Add (t: T; kind: Kind; id: TypeUID; bits: INTEGER;
               a: TypeUID := 0): DType =
  VAR d := NEW (DType, kind := kind, id := id, bits := bits, a := a);
  BEGIN
    EVAL t.types.put (id, d);
    RETURN d;
  END Add;

PROCEDURE Typename (t: T; id: TypeUID; name: TEXT) =
  VAR r: REFANY;  d: DType;
  BEGIN
    IF t.types.get (id, r) THEN
      d := r;
      IF d.name = NIL THEN d.name := name END;
    END;
  END Typename;

PROCEDURE Array (t: T; id, index, elt: TypeUID; bits: INTEGER) =
  VAR d := Add (t, Kind.Array, id, bits, elt);
  BEGIN
    d.b := index;
  END Array;

PROCEDURE OpenArray (t: T; id, elt: TypeUID; bits: INTEGER) =
  BEGIN
    EVAL Add (t, Kind.OpenArray, id, bits, elt);
  END OpenArray;

PROCEDURE Enum (t: T; id: TypeUID; n_elts, bits: INTEGER) =
  VAR d := Add (t, Kind.Enum, id, bits);
  BEGIN
    d.elts := NEW (REF ARRAY OF TEXT, MAX (n_elts, 0));
    t.cur := d;
  END Enum;

PROCEDURE EnumElt (t: T; name: TEXT) =
  VAR d := t.cur;
  BEGIN
    IF d # NIL AND d.kind = Kind.Enum AND d.n < NUMBER (d.elts^) THEN
      d.elts[d.n] := name;
      INC (d.n);
    END;
  END EnumElt;

PROCEDURE Packed (t: T; id: TypeUID; bits: INTEGER; base: TypeUID) =
  BEGIN
    EVAL Add (t, Kind.Packed, id, bits, base);
  END Packed;

PROCEDURE Record (t: T; id: TypeUID; bits, n_fields: INTEGER) =
  VAR d := Add (t, Kind.Record, id, bits);
  BEGIN
    d.fields := NEW (REF ARRAY OF FieldInfo, MAX (n_fields, 0));
    t.cur := d;
    IF id = -1 THEN
      (* The first record with typeid -1 describes the constants, and
         the second the module's global variables. *)
      IF NOT t.seen_const
        THEN t.seen_const := TRUE;
        ELSIF t.globals = NIL THEN t.globals := d;
      END;
    END;
  END Record;

PROCEDURE Field (t: T; name: TEXT; offset, bits: INTEGER; type: TypeUID) =
  VAR d := t.cur;
  BEGIN
    IF d # NIL AND d.fields # NIL AND d.n < NUMBER (d.fields^) THEN
      d.fields[d.n] := FieldInfo {name, offset, bits, type};
      INC (d.n);
    END;
  END Field;

PROCEDURE Set (t: T; id, domain: TypeUID; bits: INTEGER) =
  BEGIN
    EVAL Add (t, Kind.Set, id, bits, domain);
  END Set;

PROCEDURE Subrange (t: T; id, domain: TypeUID;
                    READONLY min, max: Target.Int; bits: INTEGER) =
  VAR d := Add (t, Kind.Subrange, id, bits, domain);
  BEGIN
    d.min := min;
    d.max := max;
  END Subrange;

PROCEDURE Pointer (t: T; id, target: TypeUID) =
  BEGIN
    EVAL Add (t, Kind.Pointer, id, Target.Address.size, target);
  END Pointer;

PROCEDURE Indirect (t: T; id, target: TypeUID) =
  BEGIN
    EVAL Add (t, Kind.Indirect, id, Target.Address.size, target);
  END Indirect;

PROCEDURE ProcType (t: T; id: TypeUID; n_formals: INTEGER;
                    result: TypeUID) =
  VAR d := Add (t, Kind.Proc, id, Target.Address.size, result);
  BEGIN
    d.formals := NEW (REF ARRAY OF TypeUID, MAX (n_formals, 0));
    t.cur := d;
  END ProcType;

PROCEDURE Formal (t: T; type: TypeUID) =
  VAR d := t.cur;
  BEGIN
    IF d # NIL AND d.kind = Kind.Proc AND d.n < NUMBER (d.formals^) THEN
      d.formals[d.n] := type;
      INC (d.n);
    END;
  END Formal;

PROCEDURE Object (t: T; id, super: TypeUID; n_fields: INTEGER;
                  field_size, field_offset: INTEGER;
                  n_methods, method_offset: INTEGER) =
  VAR d := Add (t, Kind.Object, id, field_size, super);
  BEGIN
    d.fields := NEW (REF ARRAY OF FieldInfo, MAX (n_fields, 0));
    d.methods := NEW (REF ARRAY OF FieldInfo, MAX (n_methods, 0));
    d.offset := field_offset;
    d.moffset := method_offset;
    IF field_offset >= 0 THEN
      (* the size of the whole object, its supertypes' fields included *)
      d.bits := field_offset + field_size;
    END;
    t.cur := d;
  END Object;

PROCEDURE Method (t: T; name: TEXT; signature: TypeUID) =
  (* The front end declares an object's new methods (not its overrides)
     before its fields. *)
  VAR d := t.cur;
  BEGIN
    IF d # NIL AND d.kind = Kind.Object
       AND d.n_methods < NUMBER (d.methods^) THEN
      d.methods[d.n_methods] := FieldInfo {name, 0, Target.Address.size,
                                           signature};
      INC (d.n_methods);
    END;
  END Method;

PROCEDURE Opaque (t: T; id, super: TypeUID) =
  BEGIN
    EVAL Add (t, Kind.Opaque, id, Target.Address.size, super);
  END Opaque;

PROCEDURE Reveal (t: T; lhs, rhs: TypeUID) =
  VAR r: REFANY;  name: TEXT := NIL;
  BEGIN
    IF t.types.get (lhs, r) THEN name := NARROW (r, DType).name END;
    WITH d = Add (t, Kind.Alias, lhs, 0, rhs) DO d.name := name END;
  END Reveal;

PROCEDURE WidecharSize (t: T; bits: INTEGER) =
  BEGIN
    t.widechar_bits := bits;
  END WidecharSize;

(*------------------------------------------------------------- types ---*)

PROCEDURE Get (t: T; id: TypeUID): DType =
  VAR r: REFANY;
  BEGIN
    IF t.types.get (id, r) THEN RETURN r END;
    RETURN NIL;
  END Get;

PROCEDURE Resolve (t: T; id: TypeUID): DType =
  (* The type behind aliases, indirections and packing. *)
  VAR d := Get (t, id);
  BEGIN
    FOR i := 1 TO 50 DO
      IF d = NIL THEN RETURN NIL END;
      CASE d.kind OF
      | Kind.Alias, Kind.Indirect, Kind.Packed => d := Get (t, d.a);
      ELSE RETURN d;
      END;
    END;
    RETURN NIL;
  END Resolve;

PROCEDURE Root (t: T; d: DType): DType =
  (* The base type of a chain of subranges. *)
  VAR r: DType;
  BEGIN
    FOR i := 1 TO 50 DO
      IF d = NIL OR d.kind # Kind.Subrange OR d.a = d.id THEN RETURN d END;
      r := Resolve (t, d.a);
      IF r = NIL THEN RETURN d END;
      d := r;
    END;
    RETURN d;
  END Root;

PROCEDURE Ref (t: T; id: TypeUID): TEXT =
  (* The DI type of "id", or NIL if it is unknown. *)
  VAR d := Resolve (t, id);  r: DType;
  BEGIN
    IF d = NIL THEN RETURN NIL END;
    IF d.md # NIL THEN RETURN d.md END;
    IF d.kind = Kind.Subrange THEN
      r := Root (t, d);
      IF r # d AND r.kind = Kind.Enum THEN RETURN Ref (t, r.id) END;
    END;
    d.md := Reserve (t);   (* before the body: types can be recursive *)
    Define (t, d.md, Body (t, d));
    RETURN d.md;
  END Ref;

PROCEDURE Body (t: T; d: DType): TEXT =
  BEGIN
    CASE d.kind OF
    | Kind.Basic =>
        IF d.id = UID_WIDECHAR THEN d.bits := t.widechar_bits END;
        RETURN BasicType (d.name, d.bits, d.enc);
    | Kind.Address =>
        IF d.id = UID_TEXT THEN
          (* A typedef, so that a pretty-printer can recognize TEXT by
             its name (m3printers.py, m3lldb.py). *)
          RETURN "!DIDerivedType(tag: DW_TAG_typedef, name: \"TEXT\", "
                   & "baseType: " & Node (t, PointerType (NIL, "null")) & ")";
        END;
        RETURN PointerType (d.name, "null");
    | Kind.Subrange =>
        RETURN SubrangeBody (t, d);
    | Kind.Enum =>
        RETURN EnumBody (t, d);
    | Kind.Array =>
        RETURN ArrayBody (t, d);
    | Kind.OpenArray =>
        RETURN OpenArrayBody (t, d, 0);
    | Kind.Record =>
        RETURN RecordBody (t, d);
    | Kind.Set =>
        RETURN SetBody (t, d);
    | Kind.Pointer =>
        RETURN PointerType (d.name, OrNull (Ref (t, d.a)));
    | Kind.Proc =>
        RETURN PointerType (d.name, SubroutineType (t, d.a, d.formals^));
    | Kind.Object, Kind.Opaque =>
        RETURN PointerType (d.name, Class (t, d));
    | Kind.Alias, Kind.Indirect, Kind.Packed =>
        <*ASSERT FALSE*>   (* resolved by Ref *)
    END;
  END Body;

PROCEDURE BasicType (name: TEXT; bits: INTEGER; enc: TEXT): TEXT =
  BEGIN
    RETURN "!DIBasicType(" & NameField (name) & "size: " & Fmt.Int (bits)
             & ", encoding: " & enc & ")";
  END BasicType;

PROCEDURE PointerType (name, target: TEXT): TEXT =
  BEGIN
    RETURN "!DIDerivedType(tag: DW_TAG_pointer_type, " & NameField (name)
             & "baseType: " & target & ", size: "
             & Fmt.Int (Target.Address.size) & ")";
  END PointerType;

PROCEDURE SubrangeBody (t: T; d: DType): TEXT =
  VAR r := Root (t, d);  enc := "DW_ATE_signed";  min: INTEGER;
  BEGIN
    IF TInt.ToInt (d.min, min) AND min >= 0 THEN enc := "DW_ATE_unsigned" END;
    IF r # NIL THEN
      IF r.id = UID_BOOLEAN THEN enc := "DW_ATE_boolean";
      ELSIF r.id = UID_CHAR THEN enc := "DW_ATE_unsigned_char";
      ELSIF r.id = UID_WIDECHAR THEN enc := "DW_ATE_unsigned";
      END;
    END;
    RETURN BasicType (d.name, MAX (d.bits, 8), enc);
  END SubrangeBody;

PROCEDURE EnumBody (t: T; d: DType): TEXT =
  VAR wr := TextWr.New ();  bits := MAX (d.bits, 8);
  BEGIN
    (* LLVM takes the signedness of the enumerators from the base type. *)
    Wr.PutText (wr, "!DICompositeType(tag: DW_TAG_enumeration_type, "
                      & NameField (d.name) & "baseType: "
                      & Node (t, BasicType (NIL, bits, "DW_ATE_unsigned"))
                      & ", size: " & Fmt.Int (bits) & ", elements: !{");
    FOR i := 0 TO d.n - 1 DO
      IF i > 0 THEN Wr.PutText (wr, ", ") END;
      Wr.PutText (wr, "!DIEnumerator(name: \"" & Esc (d.elts[i])
                        & "\", value: " & Fmt.Int (i)
                        & ", isUnsigned: true)");
    END;
    Wr.PutText (wr, "})");
    RETURN TextWr.ToText (wr);
  END EnumBody;

PROCEDURE Bounds (t: T; id: TypeUID; VAR min, max: INTEGER): BOOLEAN =
  (* The bounds of an ordinal index type. *)
  VAR d := Resolve (t, id);
  BEGIN
    IF d = NIL THEN RETURN FALSE END;
    CASE d.kind OF
    | Kind.Subrange =>
        RETURN TInt.ToInt (d.min, min) AND TInt.ToInt (d.max, max);
    | Kind.Enum =>
        min := 0;  max := NUMBER (d.elts^) - 1;  RETURN TRUE;
    | Kind.Basic =>
        min := 0;
        IF d.id = UID_BOOLEAN THEN max := 1;  RETURN TRUE;
        ELSIF d.id = UID_CHAR THEN max := 255;  RETURN TRUE;
        ELSIF d.id = UID_WIDECHAR THEN
          IF t.widechar_bits = 16
            THEN max := 16_FFFF;
            ELSE max := 16_10FFFF;
          END;
          RETURN TRUE;
        END;
    ELSE
    END;
    RETURN FALSE;
  END Bounds;

PROCEDURE ArrayBody (t: T; d: DType): TEXT =
  VAR elt := Get (t, d.a);  min, max, count: INTEGER;  elt_bits := -1;
  BEGIN
    IF NOT Bounds (t, d.b, min, max) THEN
      min := 0;  max := -1;
    END;
    count := max - min + 1;
    IF elt # NIL AND elt.kind = Kind.Packed THEN elt_bits := elt.bits END;
    IF elt_bits > 0 AND elt_bits MOD 8 # 0 THEN
      (* Packed elements: LLVM 18 has no bit stride for arrays. *)
      RETURN Opaque0 (d.name, d.bits);
    END;
    RETURN "!DICompositeType(tag: DW_TAG_array_type, " & NameField (d.name)
             & "baseType: " & OrUnknown (t, Ref (t, d.a))
             & ", size: " & Fmt.Int (d.bits)
             & ", elements: !{!DISubrange(count: " & Fmt.Int (count)
             & ", lowerBound: " & Fmt.Int (min) & ")})";
  END ArrayBody;

PROCEDURE OpenArrayBody (t: T; d: DType; ofs: INTEGER): TEXT =
  (* "ofs" is the byte offset of this dimension's size in the dope vector,
     after the data pointer. *)
  VAR elt := Resolve (t, d.a);  base, loc := "";
      ptr := Target.Address.bytes;
  BEGIN
    IF elt # NIL AND elt.kind = Kind.OpenArray THEN
      (* a multi-dimensional open array: the inner dimension is described
         by the same dope vector. *)
      base := Node (t, OpenArrayBody (t, elt, ofs + Target.Integer.bytes));
    ELSE
      base := OrUnknown (t, Ref (t, d.a));
    END;
    IF ofs = 0 THEN
      loc := ", dataLocation: !DIExpression(DW_OP_push_object_address, "
               & "DW_OP_deref)";
    END;
    RETURN "!DICompositeType(tag: DW_TAG_array_type, " & NameField (d.name)
             & "baseType: " & base
             & ", elements: !{!DISubrange(lowerBound: 0, upperBound: "
             & "!DIExpression(DW_OP_push_object_address, DW_OP_plus_uconst, "
             & Fmt.Int (ptr + ofs) & ", DW_OP_deref, DW_OP_constu, 1, "
             & "DW_OP_minus))}" & loc & ")";
  END OpenArrayBody;

PROCEDURE Opaque0 (name: TEXT; bits: INTEGER): TEXT =
  BEGIN
    RETURN "!DICompositeType(tag: DW_TAG_structure_type, " & NameField (name)
             & "size: " & Fmt.Int (MAX (bits, 0)) & ", elements: !{})";
  END Opaque0;

PROCEDURE Members (t: T; wr: Wr.T; scope: TEXT; d: DType; base: INTEGER;
                   first: BOOLEAN) =
  VAR f: FieldInfo;  ft: DType;  bitfield: BOOLEAN;
  BEGIN
    FOR i := 0 TO d.n - 1 DO
      f := d.fields[i];
      ft := Get (t, f.type);
      bitfield := (ft # NIL AND ft.kind = Kind.Packed)
                    OR f.offset MOD 8 # 0 OR f.bits MOD 8 # 0;
      IF NOT first THEN Wr.PutText (wr, ", ") END;
      first := FALSE;
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_member, "
                        & NameField (f.name) & "scope: " & scope
                        & ", baseType: " & OrUnknown (t, Ref (t, f.type))
                        & ", size: " & Fmt.Int (f.bits) & ", offset: "
                        & Fmt.Int (base + f.offset));
      IF bitfield THEN
        Wr.PutText (wr, ", flags: DIFlagBitField, extraData: i64 "
                          & Fmt.Int (base + f.offset));
      END;
      Wr.PutText (wr, ")");
    END;
  END Members;

PROCEDURE RecordBody (t: T; d: DType): TEXT =
  VAR wr := TextWr.New ();
  BEGIN
    Wr.PutText (wr, "distinct !DICompositeType(tag: DW_TAG_structure_type, "
                      & NameField (d.name) & "size: " & Fmt.Int (d.bits)
                      & ", elements: !{");
    Members (t, wr, d.md, d, 0, TRUE);
    Wr.PutText (wr, "})");
    RETURN TextWr.ToText (wr);
  END RecordBody;

PROCEDURE Class (t: T; d: DType): TEXT =
  (* The structure that an object or opaque type points to. *)
  VAR wr: TextWr.T;  super: DType;  first := TRUE;  bits := 0;
  BEGIN
    IF d.cls # NIL THEN RETURN d.cls END;
    d.cls := Reserve (t);
    wr := TextWr.New ();
    super := Resolve (t, d.a);
    IF d.kind = Kind.Object AND d.offset >= 0 THEN bits := d.bits END;
    Wr.PutText (wr, "distinct !DICompositeType(tag: DW_TAG_structure_type, "
                      & NameField (d.name) & "size: " & Fmt.Int (bits)
                      & ", elements: !{");
    IF super # NIL AND (super.kind = Kind.Object OR super.kind = Kind.Opaque)
      THEN
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_inheritance, scope: "
                        & d.cls & ", baseType: " & Class (t, super)
                        & ", offset: 0)");
      first := FALSE;
    END;
    IF d.kind = Kind.Object AND d.moffset >= 0 THEN
      (* Every object starts with a pointer to its method suite.  Each
         class has its own "_methods", which hides its supertype's. *)
      IF NOT first THEN Wr.PutText (wr, ", ") END;
      first := FALSE;
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_member, name: \"_methods\", "
                        & "scope: " & d.cls & ", baseType: "
                        & Node (t, PointerType (NIL, Suite (t, d)))
                        & ", size: " & Fmt.Int (Target.Address.size)
                        & ", offset: 0, flags: DIFlagArtificial)");
    END;
    IF d.kind = Kind.Object AND d.offset >= 0 THEN
      Members (t, wr, d.cls, d, d.offset, first);
    END;
    Wr.PutText (wr, "})");
    Define (t, d.cls, TextWr.ToText (wr));
    RETURN d.cls;
  END Class;

PROCEDURE Suite (t: T; d: DType): TEXT =
  (* The method suite of an object type whose method offset is known:
     its supertype's methods, then its own, each a procedure pointer. *)
  VAR wr: TextWr.T;  super: DType;  first := TRUE;  ptr := Target.Address.size;
      name: TEXT := NIL;
  BEGIN
    IF d.suite # NIL THEN RETURN d.suite END;
    d.suite := Reserve (t);
    wr := TextWr.New ();
    IF d.name # NIL THEN name := d.name & "_methods" END;
    Wr.PutText (wr, "distinct !DICompositeType(tag: DW_TAG_structure_type, "
                      & NameField (name) & "size: "
                      & Fmt.Int (d.moffset + d.n_methods * ptr)
                      & ", elements: !{");
    super := Resolve (t, d.a);
    IF super # NIL AND super.kind = Kind.Object AND super.moffset >= 0 THEN
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_inheritance, scope: "
                        & d.suite & ", baseType: " & Suite (t, super)
                        & ", offset: 0)");
      first := FALSE;
    END;
    FOR i := 0 TO d.n_methods - 1 DO
      IF NOT first THEN Wr.PutText (wr, ", ") END;
      first := FALSE;
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_member, "
                        & NameField (d.methods[i].name) & "scope: " & d.suite
                        & ", baseType: "
                        & OrUnknown (t, Ref (t, d.methods[i].type))
                        & ", size: " & Fmt.Int (ptr) & ", offset: "
                        & Fmt.Int (d.moffset + i * ptr) & ")");
    END;
    Wr.PutText (wr, "})");
    Define (t, d.suite, TextWr.ToText (wr));
    RETURN d.suite;
  END Suite;

PROCEDURE SetBody (t: T; d: DType): TEXT =
  VAR dom := Resolve (t, d.a);  ref: TEXT;
  BEGIN
    IF language = Language.C THEN RETURN SetStruct (t, d, dom) END;
    (* LLVM accepts sets of enumerations, subranges and basic types. *)
    IF dom # NIL AND dom.kind IN SET OF Kind {Kind.Enum, Kind.Subrange,
                                                Kind.Basic} THEN
      ref := Ref (t, d.a);
      IF ref # NIL THEN
        RETURN "!DIDerivedType(tag: DW_TAG_set_type, " & NameField (d.name)
                 & "baseType: " & ref & ", size: " & Fmt.Int (d.bits) & ")";
      END;
    END;
    RETURN Opaque0 (d.name, d.bits);
  END SetBody;

PROCEDURE SetStruct (t: T; d: DType; dom: DType): TEXT =
  (* C has no sets, and gdb's C mode cannot print DW_TAG_set_type, so
     in a unit that claims to be C a set is a structure with a one-bit
     BOOLEAN member for each element, named after the element: "Red",
     or "_5" ("_m5" for -5) if the domain is not an enumeration.  Bit
     i - FIRST of the set is element i (little-endian targets). *)
  CONST MaxMembers = 1024;
  VAR wr: Wr.T;  min, max: INTEGER;  name: TEXT;
  BEGIN
    IF dom = NIL OR NOT Bounds (t, d.a, min, max)
      OR max - min + 1 > MIN (MaxMembers, d.bits) THEN
      RETURN Opaque0 (d.name, d.bits);
    END;
    wr := TextWr.New ();
    Wr.PutText (wr, "distinct !DICompositeType(tag: DW_TAG_structure_type, "
                      & NameField (d.name) & "size: " & Fmt.Int (d.bits)
                      & ", elements: !{");
    FOR i := min TO max DO
      IF dom.kind = Kind.Enum AND dom.elts[i] # NIL THEN
        name := dom.elts[i];
      ELSIF i < 0 THEN
        name := "_m" & Fmt.Int (-i);
      ELSE
        name := "_" & Fmt.Int (i);
      END;
      IF i > min THEN Wr.PutText (wr, ", ") END;
      Wr.PutText (wr, "!DIDerivedType(tag: DW_TAG_member, "
                        & NameField (name) & "scope: " & d.md
                        & ", baseType: " & Ref (t, UID_BOOLEAN)
                        & ", size: 1, offset: " & Fmt.Int (i - min)
                        & ", flags: DIFlagBitField, extraData: i64 "
                        & Fmt.Int (i - min) & ")");
    END;
    Wr.PutText (wr, "})");
    RETURN TextWr.ToText (wr);
  END SetStruct;

PROCEDURE SubroutineType (t: T; result: TypeUID;
                          READONLY formals: ARRAY OF TypeUID): TEXT =
  VAR wr := TextWr.New ();
  BEGIN
    Wr.PutText (wr, "!DISubroutineType(types: !{" & OrNull (Ref (t, result)));
    FOR i := 0 TO LAST (formals) DO
      Wr.PutText (wr, ", " & OrUnknown (t, Ref (t, formals[i])));
    END;
    Wr.PutText (wr, "})");
    RETURN TextWr.ToText (wr);
  END SubroutineType;

PROCEDURE OrNull (ref: TEXT): TEXT =
  BEGIN
    IF ref = NIL THEN RETURN "null" END;
    RETURN ref;
  END OrNull;

PROCEDURE OrUnknown (t: T; ref: TEXT): TEXT =
  BEGIN
    IF ref # NIL THEN RETURN ref END;
    IF t.unknown = NIL THEN
      t.unknown := Node (t, "!DIBasicType(tag: DW_TAG_unspecified_type, "
                              & "name: \"?\")");
    END;
    RETURN t.unknown;
  END OrUnknown;

PROCEDURE NameField (name: TEXT): TEXT =
  BEGIN
    IF name = NIL OR Text.Length (name) = 0 THEN RETURN "" END;
    RETURN "name: \"" & Esc (name) & "\", ";
  END NameField;

PROCEDURE Esc (x: TEXT): TEXT =
  VAR wr: TextWr.T;  c: CHAR;
  BEGIN
    IF x = NIL THEN RETURN "" END;
    IF Text.FindChar (x, '"') < 0 AND Text.FindChar (x, '\\') < 0 THEN
      RETURN x;
    END;
    wr := TextWr.New ();
    FOR i := 0 TO Text.Length (x) - 1 DO
      c := Text.GetChar (x, i);
      IF c = '"' OR c = '\\' THEN
        Wr.PutText (wr, "\\" & Fmt.Pad (Fmt.Int (ORD (c), 16), 2, '0'));
      ELSE
        Wr.PutChar (wr, c);
      END;
    END;
    RETURN TextWr.ToText (wr);
  END Esc;

(*----------------------------------------------------------- metadata ---*)

PROCEDURE Reserve (t: T): TEXT =
  BEGIN
    INC (t.next_md);
    RETURN "!" & Fmt.Int (t.next_md - 1);
  END Reserve;

PROCEDURE Define (t: T; ref, node: TEXT) =
  BEGIN
    Wr.PutText (t.meta, ref & " = " & node & Wr.EOL);
  END Define;

PROCEDURE Node (t: T; node: TEXT): TEXT =
  VAR ref := Reserve (t);
  BEGIN
    Define (t, ref, node);
    RETURN ref;
  END Node;

PROCEDURE File (t: T; path: TEXT): TEXT =
  VAR r: REFANY;  dir, name, ref: TEXT;
  BEGIN
    IF t.files.get (path, r) THEN RETURN r END;
    IF t.cwd = NIL THEN
      TRY t.cwd := Process.GetWorkingDirectory ();
      EXCEPT OSError.E => t.cwd := ".";
      END;
    END;
    IF Pathname.Absolute (path) THEN
      dir := Pathname.Prefix (path);
      name := Pathname.Last (path);
    ELSE
      dir := t.cwd;
      name := path;
    END;
    ref := Node (t, "!DIFile(filename: \"" & Esc (name)
                      & "\", directory: \"" & Esc (dir) & "\")");
    EVAL t.files.put (path, ref);
    RETURN ref;
  END File;

PROCEDURE Defer (t: T; d: Deferred) =
  BEGIN
    d.next := t.deferred;
    t.deferred := d;
  END Defer;

PROCEDURE ShortName (linkage: TEXT): TEXT =
  (* "Module__Proc" => "Proc" *)
  VAR n := Text.Length (linkage);
  BEGIN
    FOR i := 0 TO n - 3 DO
      IF Text.GetChar (linkage, i) = '_'
        AND Text.GetChar (linkage, i + 1) = '_' THEN
        RETURN Text.Sub (linkage, i + 2);
      END;
    END;
    RETURN linkage;
  END ShortName;

PROCEDURE Subprogram (t: T; ref: TEXT; linkage_name: TEXT; file: TEXT;
                      line: INTEGER; local: BOOLEAN; result: TypeUID;
                      READONLY params: ARRAY OF TypeUID) =
  VAR d := NEW (DSub, ref := ref, linkage := linkage_name, file := file,
                line := line, local := local, result := result,
                params := NEW (REF ARRAY OF TypeUID, NUMBER (params)));
  BEGIN
    d.params^ := params;
    Defer (t, d);
  END Subprogram;

PROCEDURE DefineSub (d: DSub; t: T) =
  VAR flags := "DISPFlagDefinition";
  BEGIN
    IF d.local THEN flags := flags & " | DISPFlagLocalToUnit" END;
    Define (t, d.ref, "distinct !DISubprogram(name: \""
                        & Esc (ShortName (d.linkage)) & "\", linkageName: \""
                        & Esc (d.linkage) & "\", scope: " & d.file
                        & ", file: " & d.file & ", line: " & Fmt.Int (d.line)
                        & ", type: " & SubroutineType (t, d.result, d.params^)
                        & ", scopeLine: " & Fmt.Int (d.line)
                        & ", spFlags: " & flags & ", unit: " & t.cu & ")");
  END DefineSub;

PROCEDURE Variable (t: T; ref, expr: TEXT; name: TEXT; arg: INTEGER;
                    scope, file: TEXT; line: INTEGER; type: TypeUID) =
  BEGIN
    Defer (t, NEW (DVar, ref := ref, expr := expr, name := name,
                   arg := arg, scope := scope, file := file, line := line,
                   type := type));
  END Variable;

PROCEDURE Located (t: T; type: TypeUID): TEXT =
  (* The DWARF operations that turn the address of a variable's storage
     into the address of its value. *)
  VAR d := Get (t, type);
  BEGIN
    IF d # NIL AND d.kind = Kind.Indirect THEN RETURN "DW_OP_deref" END;
    RETURN "";
  END Located;

PROCEDURE DefineVar (d: DVar; t: T) =
  VAR arg := "";
  BEGIN
    IF d.arg > 0 THEN arg := ", arg: " & Fmt.Int (d.arg) END;
    Define (t, d.ref, "!DILocalVariable(name: \"" & Esc (d.name) & "\"" & arg
                        & ", scope: " & d.scope & ", file: " & d.file
                        & ", line: " & Fmt.Int (d.line) & ", type: "
                        & OrUnknown (t, Ref (t, d.type)) & ")");
    Define (t, d.expr, "!DIExpression(" & Located (t, d.type) & ")");
  END DefineVar;

PROCEDURE Globals (t: T; file: TEXT): TEXT =
  VAR g := t.globals;  res := "";  ref: TEXT;
  BEGIN
    IF g = NIL THEN RETURN "" END;
    t.globals := NIL;   (* describe them once *)
    FOR i := 0 TO g.n - 1 DO
      WITH f = g.fields[i] DO
        (* Exceptions have type 0. *)
        IF f.type # 0 AND f.name # NIL AND Text.Length (f.name) > 0 THEN
          ref := Reserve (t);
          res := res & ", !dbg " & ref;
          IF Text.Length (t.gves) > 0 THEN t.gves := t.gves & ", " END;
          t.gves := t.gves & ref;
          Defer (t, NEW (DGlobal, ref := ref, name := f.name, file := file,
                         offset := f.offset, type := f.type));
        END;
      END;
    END;
    RETURN res;
  END Globals;

PROCEDURE DefineGlobal (d: DGlobal; t: T) =
  VAR var := Reserve (t);  ops := Located (t, d.type);
  BEGIN
    IF Text.Length (ops) > 0 THEN ops := ", " & ops END;
    Define (t, var, "distinct !DIGlobalVariable(name: \"" & Esc (d.name)
                      & "\", scope: " & t.cu & ", file: " & d.file
                      & ", line: 1, type: " & OrUnknown (t, Ref (t, d.type))
                      & ", isLocal: true, isDefinition: true)");
    Define (t, d.ref, "!DIGlobalVariableExpression(var: " & var
                        & ", expr: !DIExpression(DW_OP_plus_uconst, "
                        & Fmt.Int (d.offset DIV 8) & ops & "))");
  END DefineGlobal;

PROCEDURE GdbScripts (wr: Wr.T) =
  (* Embed m3printers.py, gdb's pretty-printers for TEXT and procedures,
     in the .debug_gdb_scripts section.  The entry is an inline Python
     script (4), whose first line is its name.  Each unit has a copy in
     a COMDAT, and the linker keeps one. *)
  CONST Sym = "@__m3_gdb_scripts_m3printers";
  VAR
    script := "m3printers.py\n"
                & Bundle.Get (M3LLVMIRBundle.Get (), "m3printers.py");
    n := Text.Length (script) + 2;   (* the leading 4 and the NUL *)
    lit := TextWr.New ();  c: CHAR;
  BEGIN
    FOR i := 0 TO Text.Length (script) - 1 DO
      c := Text.GetChar (script, i);
      IF c >= ' ' AND c <= '~' AND c # '"' AND c # '\\' THEN
        Wr.PutChar (lit, c);
      ELSE
        Wr.PutText (lit, "\\" & Fmt.Pad (Fmt.Int (ORD (c), 16), 2, '0'));
      END;
    END;
    Wr.PutText (wr, Wr.EOL & "$__m3_gdb_scripts_m3printers = comdat any"
                      & Wr.EOL & Sym & " = linkonce_odr constant ["
                      & Fmt.Int (n) & " x i8] c\"\\04" & TextWr.ToText (lit)
                      & "\\00\", section \".debug_gdb_scripts\", comdat, "
                      & "align 1" & Wr.EOL
                      & "@llvm.used = appending global [1 x ptr] [ptr " & Sym
                      & "], section \"llvm.metadata\"" & Wr.EOL);
  END GdbScripts;

CONST LangName = ARRAY Language OF TEXT {"DW_LANG_Modula2", "DW_LANG_C99"};

PROCEDURE SetLanguage (name: TEXT): BOOLEAN =
  BEGIN
    IF EqualIgnoringCase (name, "Modula2") THEN
      language := Language.Modula2;
    ELSIF EqualIgnoringCase (name, "C") THEN
      language := Language.C;
    ELSE
      RETURN FALSE;
    END;
    RETURN TRUE;
  END SetLanguage;

PROCEDURE EqualIgnoringCase (a, b: TEXT): BOOLEAN =
  BEGIN
    IF Text.Length (a) # Text.Length (b) THEN RETURN FALSE END;
    FOR i := 0 TO Text.Length (a) - 1 DO
      IF ASCII.Upper[Text.GetChar (a, i)] # ASCII.Upper[Text.GetChar (b, i)]
        THEN RETURN FALSE;
      END;
    END;
    RETURN TRUE;
  END EqualIgnoringCase;

PROCEDURE Finish (t: T; wr: Wr.T; file: TEXT) =
  VAR d := t.deferred;  flags1, flags2: TEXT;
  BEGIN
    WHILE d # NIL DO d.define (t); d := d.next END;
    t.deferred := NIL;
    (* No .debug_names: ld.gold concatenates the per-unit tables instead
       of merging them, and gdb then rejects the section. *)
    Define (t, t.cu, "distinct !DICompileUnit(language: "
                       & LangName[language] & ", "
                       & "file: " & file & ", producer: \"cm3\", "
                       & "isOptimized: false, runtimeVersion: 0, "
                       & "emissionKind: FullDebug, globals: !{"
                       & t.gves & "}, nameTableKind: None)");
    GdbScripts (wr);
    flags1 := Node (t, "!{i32 7, !\"Dwarf Version\", i32 5}");
    flags2 := Node (t, "!{i32 2, !\"Debug Info Version\", i32 3}");
    Wr.PutText (wr, Wr.EOL & "!llvm.dbg.cu = !{" & t.cu & "}" & Wr.EOL);
    Wr.PutText (wr, "!llvm.module.flags = !{" & flags1 & ", " & flags2
                      & "}" & Wr.EOL);
    Wr.PutText (wr, TextWr.ToText (t.meta));
  END Finish;

BEGIN
END M3LLVMIRDebug.
