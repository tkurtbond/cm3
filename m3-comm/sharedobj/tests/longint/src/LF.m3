MODULE LF;
FROM L IMPORT T, S, Vals, Sub;
PROCEDURE Init (self: S): T =
  BEGIN
    self.h := FIRST(Sub);
    RETURN self;
  END Init;
PROCEDURE Set (self: S; d: LONGINT; h: Sub) =
  BEGIN
    self.d := d; self.h := h;
  END Set;
PROCEDURE Get (self: S): Vals =
  BEGIN
    RETURN Vals{self.d, self.h};
  END Get;
BEGIN
END LF.
