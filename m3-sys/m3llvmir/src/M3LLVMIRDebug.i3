(* See the file COPYRIGHT for a full description. *)

(* M3LLVMIRDebug: DWARF debug information, as LLVM metadata, for the
   LlvmIR back end (PLAN.md, Phase 5).

   The back end forwards the M3CG type declarations (declare_record,
   declare_field, ...) here; they are recorded and turned into DI
   nodes ("!N = !DIBasicType(...)") lazily, when something refers to
   the type.  Nodes that refer to types (subprograms, variables,
   globals) are reserved when the back end needs their number and
   defined by Finish, when every type of the unit is known.

   Metadata references are TEXTs of the form "!N". *)

INTERFACE M3LLVMIRDebug;

IMPORT Wr, Target;
FROM M3CG IMPORT TypeUID;

TYPE T <: REFANY;

PROCEDURE New (): T;

(*---------------------------------------------- M3CG type declarations ---*)

PROCEDURE Typename   (t: T; id: TypeUID; name: TEXT);
PROCEDURE Array      (t: T; id, index, elt: TypeUID; bits: INTEGER);
PROCEDURE OpenArray  (t: T; id, elt: TypeUID; bits: INTEGER);
PROCEDURE Enum       (t: T; id: TypeUID; n_elts, bits: INTEGER);
PROCEDURE EnumElt    (t: T; name: TEXT);
PROCEDURE Packed     (t: T; id: TypeUID; bits: INTEGER; base: TypeUID);
PROCEDURE Record     (t: T; id: TypeUID; bits, n_fields: INTEGER);
PROCEDURE Field      (t: T; name: TEXT; offset, bits: INTEGER;
                      type: TypeUID);
PROCEDURE Set        (t: T; id, domain: TypeUID; bits: INTEGER);
PROCEDURE Subrange   (t: T; id, domain: TypeUID;
                      READONLY min, max: Target.Int; bits: INTEGER);
PROCEDURE Pointer    (t: T; id, target: TypeUID);
PROCEDURE Indirect   (t: T; id, target: TypeUID);
PROCEDURE ProcType   (t: T; id: TypeUID; n_formals: INTEGER;
                      result: TypeUID);
PROCEDURE Formal     (t: T; type: TypeUID);
PROCEDURE Object     (t: T; id, super: TypeUID; n_fields: INTEGER;
                      field_size, field_offset: INTEGER);
PROCEDURE Opaque     (t: T; id, super: TypeUID);
PROCEDURE Reveal     (t: T; lhs, rhs: TypeUID);
PROCEDURE WidecharSize (t: T; bits: INTEGER);

(*----------------------------------------------------------- metadata ---*)

PROCEDURE Reserve (t: T): TEXT;
(* A fresh metadata number "!N", to be defined later. *)

PROCEDURE Node (t: T; node: TEXT): TEXT;
(* A new numbered node with the given body. *)

PROCEDURE File (t: T; path: TEXT): TEXT;
(* The DIFile for a source path, relative to the working directory. *)

PROCEDURE Subprogram (t: T; ref: TEXT; linkage_name: TEXT; file: TEXT;
                      line: INTEGER; local: BOOLEAN; result: TypeUID;
                      READONLY params: ARRAY OF TypeUID);
(* Define "ref" as the DISubprogram of a procedure definition.
   "linkage_name" is the symbol without the "@". *)

PROCEDURE Variable (t: T; ref, expr: TEXT; name: TEXT; arg: INTEGER;
                    scope, file: TEXT; line: INTEGER; type: TypeUID);
(* Define "ref" as a DILocalVariable (a parameter if "arg" > 0) and
   "expr" as the DIExpression that locates it, given the address of
   its storage. *)

PROCEDURE Globals (t: T; file: TEXT): TEXT;
(* The "!dbg" attachments, starting with ", ", that describe the
   module's global variables, as declared by the last record with
   typeid -1 (the module's data segment).  "" if there are none. *)

PROCEDURE Finish (t: T; wr: Wr.T; file: TEXT);
(* Define the deferred nodes and write all the metadata, the compile
   unit (for "file") and the module flags. *)

END M3LLVMIRDebug.
