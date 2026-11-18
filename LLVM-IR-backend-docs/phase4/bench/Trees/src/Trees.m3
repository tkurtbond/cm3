MODULE Trees EXPORTS Main;
IMPORT IO, Fmt, Word;
TYPE Node = REF RECORD l, r: Node END;
PROCEDURE Make (d: INTEGER): Node =
  BEGIN
    IF d = 0 THEN RETURN NEW (Node) END;
    RETURN NEW (Node, l := Make (d - 1), r := Make (d - 1));
  END Make;
PROCEDURE Check (n: Node): INTEGER =
  BEGIN
    IF n.l = NIL THEN RETURN 1 END;
    RETURN 1 + Check (n.l) + Check (n.r);
  END Check;
CONST MaxD = 18;
VAR long := Make (MaxD); d := 4; iters, c: INTEGER;
BEGIN
  WHILE d <= MaxD DO
    iters := Word.Shift (1, MaxD - d + 4); c := 0;
    FOR i := 1 TO iters DO INC (c, Check (Make (d))) END;
    IO.Put (Fmt.Int (iters) & " trees of depth " & Fmt.Int (d) & " check " & Fmt.Int (c) & "\n");
    INC (d, 2);
  END;
  IO.Put ("long lived check " & Fmt.Int (Check (long)) & "\n");
END Trees.
