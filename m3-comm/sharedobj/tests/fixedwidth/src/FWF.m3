(* This fork: the implementation of FW.T. *)
MODULE FWF;
IMPORT Word8, Word64, Signed8, Signed64;
FROM FW IMPORT T, S, Vals, WSub, W64Sub, LSub;
PROCEDURE Init (self: S): T =
  BEGIN
    self.e := FIRST(WSub); self.h := 0L;
    RETURN self;
  END Init;
PROCEDURE Set (self: S; a: Word8.T; b: Signed64.T; c: Word64.T; d: LONGINT;
               e: WSub; f: W64Sub; g: Signed8.T; h: LSub) =
  BEGIN
    self.a := a; self.b := b; self.c := c; self.d := d;
    self.e := e; self.f := f; self.g := g; self.h := h;
  END Set;
PROCEDURE Get (self: S): Vals =
  BEGIN
    RETURN Vals{self.a, self.b, self.c, self.d, self.e, self.f, self.g, self.h};
  END Get;
BEGIN
END FWF.
