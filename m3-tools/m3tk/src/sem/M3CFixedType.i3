(* See the file COPYRIGHT for a full description. *)

(* This fork: support for the fixed-width integer types Word8.T ..
   Word64.T and Signed8.T .. Signed64.T (see
   LLVM-IR-backend-docs/fixed-width-integer-types-plan.md).

   The compiler predeclares these types.  In m3core, "WordNRep" and
   "SignedNRep" define "T = WordN.T" by importing the interface
   "WordN = GenWordN(WordNRep)", a cycle that only the compiler's
   builtin interface breaks.  m3tk breaks it after parsing instead:
   "Transform" turns the "T" of those representation interfaces into a
   "Fixed_type" node and drops their import of "WordN". *)

INTERFACE M3CFixedType;

IMPORT M3AST_AS, M3AST_SM;

PROCEDURE Same(t1, t2: M3AST_SM.TYPE_SPEC_UNSET): BOOLEAN;
(* Whether "t1" and "t2" are both fixed-width types of the same size and
   signedness. *)

PROCEDURE Transform(cu: M3AST_AS.Compilation_Unit);
(* If "cu" is one of the interfaces "Word8Rep" .. "Word64Rep" or
   "Signed8Rep" .. "Signed64Rep", rewrite it as described above. *)

END M3CFixedType.
