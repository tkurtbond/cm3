(* See the file COPYRIGHT for a full description. *)

(* This fork: the fixed-width integer types.  Word8.T, Word16.T,
   Word32.T and Word64.T are unsigned and wrap: arithmetic is modulo
   2^N.  Signed8.T .. Signed64.T are signed and checked: arithmetic
   that overflows is a run-time error (IntegerOverflow), or wraps when
   range checks are off.  They are ordinal types of class
   Type.Class.Fixed, distinct from each other and from INTEGER and
   LONGINT, so mixing them needs an explicit VAL.  See
   LLVM-IR-backend-docs/fixed-width-integer-types-plan.md. *)

INTERFACE FixedType;

IMPORT Type, Target, CG, M3ID, Expr;

TYPE
  Info = RECORD
    type   : Type.T  := NIL;   (* the fixed type itself, not a subrange *)
    bits   : INTEGER := 0;     (* 8, 16, 32 or 64 *)
    signed : BOOLEAN := FALSE; (* SignedN, not WordN *)
    min    : Target.Int;
    max    : Target.Int;
  END;

VAR
  Word8, Word16, Word32, Word64: Type.T;
  Signed8, Signed16, Signed32, Signed64: Type.T;

PROCEDURE Initialize ();
(* Create the types.  Called from BuiltinTypes. *)

PROCEDURE InitializeInterfaces ();
(* Create the builtin interfaces Word8 .. Word64 and Signed8 ..
   Signed64, each exporting T, Size and the procedures and constants
   of FixedWord.Define.  Called from M3Front. *)

PROCEDURE IsInterface (name: M3ID.T): BOOLEAN;
(* Is 'name' one of the interfaces Word8 .. Signed64? *)

PROCEDURE HasNoUnit (name: M3ID.T): BOOLEAN;
(* Is 'name' one of the interfaces Word8 .. Signed64 that m3core doesn't
   yet implement?  Nothing exports those, so the front end records no
   version stamps for what they declare and links to no unit.  (Since
   Phase 5 m3core implements all eight, so this is always FALSE; it is
   kept for a future builtin interface without a unit.) *)

PROCEDURE Split (t: Type.T;  VAR info: Info): BOOLEAN;
(* If 't', or the base type of 't' when 't' is a subrange or packed,
   is a fixed type, set 'info' and return TRUE. *)

PROCEDURE Is (t: Type.T): BOOLEAN;
(* = Split (t, info) for some info *)

PROCEDURE IsWord (t: Type.T): BOOLEAN;
(* = Split (t, info) AND NOT info.signed for some info *)

PROCEDURE Wrap (READONLY info: Info;  READONLY x: Target.Int;
                VAR r: Target.Int);
(* r := x modulo 2^info.bits, in info.min .. info.max *)

PROCEDURE InRange (READONLY info: Info;  READONLY x: Target.Int): BOOLEAN;
(* info.min <= x <= info.max *)

PROCEDURE StackType (READONLY info: Info): CG.Type;
(* The CG type of a value of the fixed type on the CG stack. *)

PROCEDURE OrdStackType (t: Type.T): CG.Type;
(* The CG stack type of a value of the integer type 't': the stack type
   of a fixed type, else Longint for subtypes of LONGINT, else Integer
   (INTEGER subranges and enumerations). *)

PROCEDURE Fills (READONLY info: Info): BOOLEAN;
(* Does the type fill its stack type, so that no masking is needed? *)

PROCEDURE Mask (READONLY info: Info);
(* Reduce the value on top of the CG stack, of type StackType (info),
   modulo 2^info.bits into info.min .. info.max: zero-extend for WordN,
   sign-extend for SignedN.  A no-op when the type fills the stack
   type. *)

(* The arithmetic.  For WordN it wraps: the operation, then Mask.  For
   SignedN, a result outside info.min .. info.max is a run-time error,
   IntegerOverflow, when range checks are on (Host.doRangeChk), and
   wraps when they are off.  DIV and MOD round down, as for INTEGER, and
   a divisor of -1 never traps.

   A few of the SignedN operations branch, so they can't be compiled
   while the CG stack holds anything but their operands: Multiply, Div
   and Mod when the type fills its stack type (NeedsPrep says which).
   An expression compiles those in its Prep, with PrepOperate, and
   pushes the value in its Compile, with CompileOperate. *)

TYPE Op = {Add, Subtract, Multiply, Div, Mod};

PROCEDURE NeedsPrep (READONLY info: Info;  op: Op;  b: Expr.T): BOOLEAN;
(* Does 'a op b' branch, so that it must be compiled in Prep? *)

PROCEDURE PrepOperate (READONLY info: Info;  op: Op;  a, b: Expr.T): CG.Val;
(* Called from an expression's Prep, after Expr.Prep (a) and
   Expr.Prep (b).  If NeedsPrep (info, op, b), compile 'a op b' and
   return its value; else return NIL. *)

PROCEDURE CompileOperate (READONLY info: Info;  op: Op;  a, b: Expr.T;
                          VAR val: CG.Val);
(* Push 'a op b': 'val' if PrepOperate returned it (then free it and
   set it to NIL), else compile a, b and Operate. *)

PROCEDURE Operate (READONLY info: Info;  op: Op;
                   signA, signB := CG.Sign.Unknown);
(* s1 := s1 op s0; pop.  Both are of type StackType (info).
   PRE: NOT NeedsPrep (info, op, s0); for Div and Mod, s0 # 0 is the
   caller's business, as for CG.Div. *)

PROCEDURE Negate (READONLY info: Info);
(* s0 := -s0, wrapped or checked *)

PROCEDURE Abs (READONLY info: Info);
(* s0 := ABS (s0), checked.  PRE: info.signed *)

END FixedType.
