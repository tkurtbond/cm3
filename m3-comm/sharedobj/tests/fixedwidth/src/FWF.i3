(* This fork: the implementation of FW.T. *)
INTERFACE FWF;
IMPORT Word8, Word64, Signed8, Signed64;
FROM FW IMPORT T, S, Public, Vals, WSub, W64Sub, LSub;
REVEAL
  S = Public BRANDED "FW.S" OBJECT
    a: Word8.T; b: Signed64.T; c: Word64.T; d: LONGINT;
    e: WSub; f: W64Sub; g: Signed8.T; h: LSub;
  OVERRIDES
    init := Init; set := Set; get := Get;
  END;
PROCEDURE Init (self: S): T;
PROCEDURE Set (self: S; a: Word8.T; b: Signed64.T; c: Word64.T; d: LONGINT;
               e: WSub; f: W64Sub; g: Signed8.T; h: LSub);
PROCEDURE Get (self: S): Vals;
END FWF.
