MODULE Sieve EXPORTS Main;
IMPORT IO, Fmt;
CONST N = 20000000;
VAR flags := NEW (REF ARRAY OF BOOLEAN, N + 1);  count, total := 0;
BEGIN
  FOR rep := 1 TO 10 DO
    count := 0;
    FOR i := 2 TO N DO flags[i] := TRUE END;
    FOR i := 2 TO N DO
      IF flags[i] THEN
        INC (count);
        IF i <= N DIV i THEN
          VAR j := i * i; BEGIN WHILE j <= N DO flags[j] := FALSE; INC (j, i) END END;
        END;
      END;
    END;
    INC (total, count);
  END;
  IO.Put ("primes: " & Fmt.Int (count) & " total " & Fmt.Int (total) & "\n");
END Sieve.
