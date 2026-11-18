MODULE Hash EXPORTS Main;
(* Multiplicative hashing over an INTEGER array: signed arithmetic that
   overflows on purpose, in the loop shapes GCC optimizes using signed
   overflow being undefined. *)
IMPORT IO, Fmt;

CONST N = 1000000; Passes = 1500;

VAR
  a := NEW (REF ARRAY OF INTEGER, N);
  h, s: INTEGER;

PROCEDURE Mix (x: INTEGER): INTEGER =
  BEGIN
    x := x * 6364136223846793005 + 1442695040888963407;
    RETURN x + x DIV 8;
  END Mix;

BEGIN
  FOR i := 0 TO N - 1 DO a[i] := Mix (i) END;
  h := 0; s := 0;
  FOR p := 1 TO Passes DO
    FOR i := 0 TO N - 1 DO
      h := h * 1000003 + a[i];
      s := s + a[i] * p;
    END;
    a[p] := h;
  END;
  IO.Put (Fmt.Int (h) & " " & Fmt.Int (s) & "\n");
END Hash.
