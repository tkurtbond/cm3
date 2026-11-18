(* INTEGER and LONGINT overflow wraps; see readme. *)

MODULE Main;
IMPORT IO, Fmt;

(* Id hides constants from the front end's constant folding. *)
PROCEDURE Id (x: INTEGER): INTEGER = BEGIN RETURN x END Id;
PROCEDURE IdL (x: LONGINT): LONGINT = BEGIN RETURN x END IdL;

PROCEDURE AddGt (x: INTEGER): BOOLEAN = BEGIN RETURN x + 1 > x END AddGt;
PROCEDURE AddGtL (x: LONGINT): BOOLEAN = BEGIN RETURN x + 1L > x END AddGtL;
PROCEDURE SubLt (x: INTEGER): BOOLEAN = BEGIN RETURN x - 1 < x END SubLt;
PROCEDURE SubLtL (x: LONGINT): BOOLEAN = BEGIN RETURN x - 1L < x END SubLtL;
PROCEDURE MulGt (x: INTEGER): BOOLEAN = BEGIN RETURN x * 2 > x END MulGt;
PROCEDURE NegLt (x: INTEGER): BOOLEAN = BEGIN RETURN -x < 0 END NegLt;
PROCEDURE AbsLt (x: INTEGER): BOOLEAN = BEGIN RETURN ABS (x) < 0 END AbsLt;
PROCEDURE AbsLtL (x: LONGINT): BOOLEAN = BEGIN RETURN ABS (x) < 0L END AbsLtL;
PROCEDURE IncGt (x: INTEGER): BOOLEAN =
  VAR y := x; BEGIN INC (y); RETURN y > x END IncGt;

PROCEDURE B (name: TEXT; b: BOOLEAN) =
  BEGIN IO.Put (name & ": " & Fmt.Bool (b) & "\n") END B;

PROCEDURE I (name: TEXT; i: INTEGER) =
  BEGIN IO.Put (name & ": " & Fmt.Int (i) & "\n") END I;

PROCEDURE L (name: TEXT; i: LONGINT) =
  BEGIN IO.Put (name & ": " & Fmt.LongInt (i) & "\n") END L;

VAR
  max := Id (LAST (INTEGER));  min := Id (FIRST (INTEGER));
  maxL := IdL (LAST (LONGINT));  minL := IdL (FIRST (LONGINT));
BEGIN
  B ("LAST(INTEGER) + 1 > LAST(INTEGER)", AddGt (max));
  B ("LAST(LONGINT) + 1 > LAST(LONGINT)", AddGtL (maxL));
  B ("FIRST(INTEGER) - 1 < FIRST(INTEGER)", SubLt (min));
  B ("FIRST(LONGINT) - 1 < FIRST(LONGINT)", SubLtL (minL));
  B ("LAST(INTEGER) * 2 > LAST(INTEGER)", MulGt (max));
  B ("-FIRST(INTEGER) < 0", NegLt (min));
  B ("ABS(FIRST(INTEGER)) < 0", AbsLt (min));
  B ("ABS(FIRST(LONGINT)) < 0", AbsLtL (minL));
  B ("INC(LAST(INTEGER)) > LAST(INTEGER)", IncGt (max));
  I ("LAST(INTEGER) + 1", max + Id (1));
  I ("FIRST(INTEGER) - 1", min - Id (1));
  I ("LAST(INTEGER) * 3", max * Id (3));
  I ("-FIRST(INTEGER)", -min);
  I ("ABS(FIRST(INTEGER))", ABS (min));
  L ("LAST(LONGINT) + 1", maxL + IdL (1L));
END Main.
