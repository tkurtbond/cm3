(* This fork: see Exercise.mg. *)

GENERIC INTERFACE Exercise (W);

TYPE T = W.T;  (* W must be used, or the compiler warns *)

PROCEDURE Run ();

END Exercise.
