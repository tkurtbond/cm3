(* See the file COPYRIGHT for a full description. *)

(* An M3CG back end that writes textual LLVM IR (a ".ll" file) to a
   writer.  It does not link against LLVM: the output is compiled by
   the system's clang or llc.  Operations it does not implement yet
   fail with an assertion (it is built on M3CG_AssertFalse). *)

INTERFACE M3LLVMIR;

IMPORT M3CG, Wr;

PROCEDURE New (wr: Wr.T): M3CG.T;
(* Return a code generator that writes LLVM IR for one unit to "wr".
   The IR is written when the unit ends (end_unit).  "Target" must
   already be initialized. *)

PROCEDURE TargetTriple (): TEXT;
PROCEDURE DataLayout (): TEXT;
(* The LLVM target triple and data layout for Target.System_name, or
   NIL if the target is not supported yet. *)

END M3LLVMIR.
