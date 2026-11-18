MODULE QSort EXPORTS Main;
IMPORT IO, Fmt;
CONST N = 5000000;
VAR a := NEW (REF ARRAY OF INTEGER, N); seed := 12345; sum := 0;
PROCEDURE Rand (): INTEGER =
  BEGIN seed := (seed * 1103515245 + 12345) MOD 2147483648; RETURN seed END Rand;
PROCEDURE Sort (VAR a: ARRAY OF INTEGER; lo, hi: INTEGER) =
  VAR i, j, p, t: INTEGER;
  BEGIN
    WHILE lo < hi DO
      p := a[(lo + hi) DIV 2]; i := lo; j := hi;
      WHILE i <= j DO
        WHILE a[i] < p DO INC (i) END;
        WHILE a[j] > p DO DEC (j) END;
        IF i <= j THEN t := a[i]; a[i] := a[j]; a[j] := t; INC (i); DEC (j) END;
      END;
      IF j - lo < hi - i THEN Sort (a, lo, j); lo := i ELSE Sort (a, i, hi); hi := j END;
    END;
  END Sort;
BEGIN
  FOR rep := 1 TO 5 DO
    FOR i := 0 TO N - 1 DO a[i] := Rand () END;
    Sort (a^, 0, N - 1);
    FOR i := 1 TO N - 1 DO <*ASSERT a[i-1] <= a[i]*> END;
    INC (sum, a[N DIV 2]);
  END;
  IO.Put ("median sum " & Fmt.Int (sum) & "\n");
END QSort.
