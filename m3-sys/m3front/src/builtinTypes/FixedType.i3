(* See the file COPYRIGHT for a full description. *)

(* This fork: the fixed-width integer types.  Word8.T, Word16.T,
   Word32.T and Word64.T are unsigned and wrap: arithmetic is modulo
   2^N.  They are ordinal types of class Type.Class.Fixed, distinct
   from each other and from INTEGER and LONGINT, so mixing them
   needs an explicit VAL.  See
   LLVM-IR-backend-docs/fixed-width-integer-types-plan.md. *)

INTERFACE FixedType;

IMPORT Type, Target, CG, M3ID;

TYPE
  Info = RECORD
    type   : Type.T  := NIL;   (* the fixed type itself, not a subrange *)
    bits   : INTEGER := 0;     (* 8, 16, 32 or 64 *)
    signed : BOOLEAN := FALSE; (* always FALSE until the signed family *)
    min    : Target.Int;
    max    : Target.Int;
  END;

VAR
  Word8, Word16, Word32, Word64: Type.T;

PROCEDURE Initialize ();
(* Create the types.  Called from BuiltinTypes. *)

PROCEDURE InitializeInterfaces ();
(* Create the builtin interfaces Word8 .. Word64, each exporting T and
   Size.  Called from M3Front. *)

PROCEDURE IsInterface (name: M3ID.T): BOOLEAN;
(* Is 'name' one of the interfaces Word8 .. Word64?  No unit exports
   them, so the front end records no version stamps for what they
   declare. *)

PROCEDURE Split (t: Type.T;  VAR info: Info): BOOLEAN;
(* If 't', or the base type of 't' when 't' is a subrange or packed,
   is a fixed type, set 'info' and return TRUE. *)

PROCEDURE Is (t: Type.T): BOOLEAN;
(* = Split (t, info) for some info *)

PROCEDURE Wrap (READONLY info: Info;  READONLY x: Target.Int;
                VAR r: Target.Int);
(* r := x modulo 2^info.bits, in info.min .. info.max *)

PROCEDURE StackType (READONLY info: Info): CG.Type;
(* The CG type of a value of the fixed type on the CG stack. *)

PROCEDURE OrdStackType (t: Type.T): CG.Type;
(* The CG stack type of a value of the integer type 't': the stack type
   of a fixed type, else Longint for subtypes of LONGINT, else Integer
   (INTEGER subranges and enumerations). *)

PROCEDURE Mask (READONLY info: Info);
(* Reduce the value on top of the CG stack, of type StackType (info),
   modulo 2^info.bits.  A no-op when the type fills the stack type. *)

END FixedType.
