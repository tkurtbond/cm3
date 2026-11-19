(* This fork: every procedure of the interface W (one of Signed8 ..
   Signed64), called inline, folded into constants, and called through
   procedure values.  The three sections must print the same lines. *)

GENERIC MODULE Exercise (W);

IMPORT IO, Fmt, Long;

TYPE
  FromL = PROCEDURE (x: LONGINT): W.T;
  Cmp   = PROCEDURE (a, b: W.T): BOOLEAN;
  ToI   = PROCEDURE (a: W.T): INTEGER;
  Cmp3  = PROCEDURE (a, b: W.T): [-1 .. 1];

CONST
  Half = Long.Shift (1L, W.Size - 1);   (* 2^(N-1); FIRST (LONGINT) at 64 *)
  Full = Long.Shift (1L, W.Size);       (* 2^N; 0 at 64 *)
  MHalf = Long.Minus (0L, Half);        (* -2^(N-1), wrapping at 64 *)

  (* the inputs to Wrap *)
  I0 = 0L;  I1 = 1L;  I2 = -1L;  I3 = Long.Minus (Half, 1L);  I4 = Half;
  I5 = MHalf;  I6 = Long.Minus (MHalf, 1L);  I7 = Long.Minus (Full, 1L);
  I8 = Full;  I9 = Long.Plus (Full, 5L);  I10 = LAST (LONGINT);
  I11 = FIRST (LONGINT);  I12 = 16_123456789ABCDEF0L;
  I13 = -16_123456789ABCDEF0L;  I14 = 16_80L;

  Inputs = ARRAY [0 .. 14] OF LONGINT { I0, I1, I2, I3, I4, I5, I6, I7, I8, I9,
                              I10, I11, I12, I13, I14 };

  FoldWraps = ARRAY OF W.T {
    W.Wrap (I0), W.Wrap (I1), W.Wrap (I2), W.Wrap (I3), W.Wrap (I4),
    W.Wrap (I5), W.Wrap (I6), W.Wrap (I7), W.Wrap (I8), W.Wrap (I9),
    W.Wrap (I10), W.Wrap (I11), W.Wrap (I12), W.Wrap (I13),
    W.Wrap (I14) };

  (* Wrap of an INTEGER and of a W.T *)
  FoldMore = ARRAY OF W.T {
    W.Wrap (LAST (INTEGER)), W.Wrap (FIRST (INTEGER)), W.Wrap (-200),
    W.Wrap (FIRST (W.T)), W.Wrap (LAST (W.T)) };

  (* the pairs for Equal, Hash and Compare *)
  A0 = FIRST (W.T);  B0 = LAST (W.T);
  A1 = W.Wrap (-1);  B1 = W.Wrap (0);
  A2 = LAST (W.T);   B2 = FIRST (W.T);
  A3 = W.Wrap (-5);  B3 = W.Wrap (-5);

  FoldEqual = ARRAY OF BOOLEAN {
    W.Equal (A0, B0), W.Equal (A1, B1), W.Equal (A2, B2), W.Equal (A3, B3) };
  FoldHash = ARRAY OF INTEGER {
    W.Hash (A0), W.Hash (A1), W.Hash (A2), W.Hash (A3),
    W.Hash (B0), W.Hash (B1), W.Hash (B2), W.Hash (B3) };
  FoldCompare = ARRAY OF INTEGER {
    W.Compare (A0, B0), W.Compare (A1, B1), W.Compare (A2, B2),
    W.Compare (A3, B3) };

  As = ARRAY [0 .. 3] OF W.T { A0, A1, A2, A3 };
  Bs = ARRAY [0 .. 3] OF W.T { B0, B1, B2, B3 };

PROCEDURE L (x: W.T): TEXT =
  BEGIN
    RETURN Fmt.LongInt (VAL (x, LONGINT));
  END L;

PROCEDURE Print (title: TEXT;
                 READONLY wraps, more: ARRAY OF W.T;
                 READONLY equal: ARRAY OF BOOLEAN;
                 READONLY hash, compare: ARRAY OF INTEGER) =
  BEGIN
    IO.Put ("-- " & W.Brand & " " & title & "\n");
    FOR i := FIRST (wraps) TO LAST (wraps) DO
      IO.Put ("wrap " & Fmt.LongInt (Inputs[i]) & " = " & L (wraps[i]) & "\n");
    END;
    FOR i := FIRST (more) TO LAST (more) DO
      IO.Put ("more " & Fmt.Int (i) & " = " & L (more[i]) & "\n");
    END;
    FOR i := FIRST (equal) TO LAST (equal) DO
      IO.Put ("equal " & L (As[i]) & " " & L (Bs[i]) & " = "
              & Fmt.Bool (equal[i]) & "\n");
    END;
    FOR i := FIRST (hash) TO LAST (hash) DO
      IO.Put ("hash " & Fmt.Int (i) & " = " & Fmt.Int (hash[i]) & "\n");
    END;
    FOR i := FIRST (compare) TO LAST (compare) DO
      IO.Put ("compare " & L (As[i]) & " " & L (Bs[i]) & " = "
              & Fmt.Int (compare[i]) & "\n");
    END;
  END Print;

PROCEDURE Inline () =
  VAR
    in := Inputs;  as := As;  bs := Bs;
    wraps: ARRAY [0 .. NUMBER (Inputs) - 1] OF W.T;
    li := LAST (INTEGER);  fi := FIRST (INTEGER);  m := -200;
    f := FIRST (W.T);  l := LAST (W.T);
  BEGIN
    FOR i := FIRST (in) TO LAST (in) DO wraps[i] := W.Wrap (in[i]) END;
    Print ("inline", wraps,
      ARRAY OF W.T { W.Wrap (li), W.Wrap (fi), W.Wrap (m), W.Wrap (f),
                     W.Wrap (l) },
      ARRAY OF BOOLEAN { W.Equal (as[0], bs[0]), W.Equal (as[1], bs[1]),
                         W.Equal (as[2], bs[2]), W.Equal (as[3], bs[3]) },
      ARRAY OF INTEGER { W.Hash (as[0]), W.Hash (as[1]), W.Hash (as[2]),
                         W.Hash (as[3]), W.Hash (bs[0]), W.Hash (bs[1]),
                         W.Hash (bs[2]), W.Hash (bs[3]) },
      ARRAY OF INTEGER { W.Compare (as[0], bs[0]), W.Compare (as[1], bs[1]),
                         W.Compare (as[2], bs[2]),
                         W.Compare (as[3], bs[3]) });
  END Inline;

PROCEDURE Values () =
  VAR
    wrap: FromL := W.Wrap;  equal: Cmp := W.Equal;  hash: ToI := W.Hash;
    compare: Cmp3 := W.Compare;
    wraps: ARRAY [0 .. NUMBER (Inputs) - 1] OF W.T;
    e: ARRAY [0 .. 3] OF BOOLEAN;
    h: ARRAY [0 .. 7] OF INTEGER;
    c: ARRAY [0 .. 3] OF INTEGER;
  BEGIN
    FOR i := FIRST (Inputs) TO LAST (Inputs) DO
      wraps[i] := wrap (Inputs[i]);
    END;
    FOR i := 0 TO 3 DO
      e[i] := equal (As[i], Bs[i]);
      h[i] := hash (As[i]);
      h[i + 4] := hash (Bs[i]);
      c[i] := compare (As[i], Bs[i]);
    END;
    Print ("values", wraps,
      ARRAY OF W.T { wrap (VAL (LAST (INTEGER), LONGINT)),
                     wrap (VAL (FIRST (INTEGER), LONGINT)), wrap (-200L),
                     wrap (VAL (FIRST (W.T), LONGINT)),
                     wrap (VAL (LAST (W.T), LONGINT)) },
      e, h, c);
  END Values;

PROCEDURE Run () =
  BEGIN
    IO.Put ("== " & W.Brand & ", Size " & Fmt.Int (W.Size) & "\n");
    Inline ();
    Print ("folded", FoldWraps, FoldMore, FoldEqual, FoldHash, FoldCompare);
    Values ();
  END Run;

BEGIN
END Exercise.
