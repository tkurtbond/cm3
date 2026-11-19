(* This fork: an optional warning for the signed operators on Word.T
   and Long.T.  See "Word.T versus WordN.T" in
   LLVM-IR-backend-docs/fixed-width-integer-types-plan.md. *)

INTERFACE WordWarn;

IMPORT Expr, Value;

PROCEDURE Check (a, b: Expr.T;  op, unsigned: TEXT);
(* If a or b has the declared type Word.T or Long.T, directly or through
   other type names, say that op (on INTEGER or LONGINT, already
   checked) is the signed operation and that Word.<unsigned> (or
   Long.<unsigned>) is the unsigned one.  Level 0, so only "cm3 -w0"
   shows it: signed use of Word.T is legal. *)

PROCEDURE NoteWith (var: Value.T;  e: Expr.T);
(* Remember, for Check, the declared type of e, checked, which the
   WITH variable var is bound to. *)

END WordWarn.
