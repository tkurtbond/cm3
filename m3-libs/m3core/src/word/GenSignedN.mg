(* See the file COPYRIGHT for a full description. *)

(* This fork: like GenWordN.mg, instantiated with its own interface as
   Impl.  The compiler compiles the calls below inline, so these are
   wrappers for when the procedures are used as values. *)

GENERIC MODULE GenSignedN(Impl);

IMPORT Word;

PROCEDURE Wrap (x: LONGINT): T  = BEGIN RETURN Impl.Wrap (x)      END Wrap;

PROCEDURE Equal (a, b: T): BOOLEAN = BEGIN RETURN Impl.Equal (a, b) END Equal;
PROCEDURE Hash (a: T): Word.T   = BEGIN RETURN Impl.Hash (a)      END Hash;
PROCEDURE Compare (a, b: T): [-1..1]
 = BEGIN RETURN Impl.Compare (a, b) END Compare;

BEGIN
END GenSignedN.
