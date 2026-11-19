(* The implementation of L.T. *)
INTERFACE LF;
FROM L IMPORT T, S, Public, Vals, Sub;
REVEAL
  S = Public BRANDED "L.S" OBJECT
    d: LONGINT; h: Sub;
  OVERRIDES
    init := Init; set := Set; get := Get;
  END;
PROCEDURE Init (self: S): T;
PROCEDURE Set (self: S; d: LONGINT; h: Sub);
PROCEDURE Get (self: S): Vals;
END LF.
