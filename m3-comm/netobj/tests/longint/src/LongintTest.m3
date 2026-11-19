(* A network-object test of LONGINT and LONGINT subrange arguments,
   results and VAR parameters.

   "longinttest server [port]" exports an object; "longinttest
   client [port]", in another process, calls it on 127.0.0.1 and checks
   the results, including that the server's unmarshaling rejects an
   out-of-range value.  The client prints "ok" or "WRONG" for each
   check and exits with status 1 if any is wrong.  The default port is
   18877. *)

UNSAFE MODULE LongintTest EXPORTS Main;
IMPORT L, NetObj, TCPNetObj, IP, IO, Fmt, Params, Process, Scan, Text, Thread, Lex, FloatMode;
<* FATAL IP.Error, NetObj.Error, Thread.Alerted, Lex.Error, FloatMode.Trap,
         TCPNetObj.Failed *>
CONST DefaultPort = 18877;
VAR failures := 0;
TYPE Impl = L.T OBJECT OVERRIDES
    add := Add; neg := Neg; half := Half; swap := Swap END;
PROCEDURE Add (<*UNUSED*>s: Impl; x: LONGINT; y: L.Sub): LONGINT =
  BEGIN RETURN x + y END Add;
PROCEDURE Neg (<*UNUSED*>s: Impl; x: LONGINT): LONGINT =
  BEGIN RETURN -x END Neg;
PROCEDURE Half (<*UNUSED*>s: Impl; x: L.Sub): L.Sub =
  BEGIN RETURN x DIV 2L END Half;
PROCEDURE Swap (<*UNUSED*>s: Impl; VAR a: LONGINT; VAR b: L.Sub) =
  VAR t := a; BEGIN a := b; b := t END Swap;

PROCEDURE Check (what: TEXT; got, want: LONGINT) =
  BEGIN
    IO.Put(what & " = " & Fmt.LongInt(got));
    IF got = want THEN IO.Put(" ok\n") ELSE IO.Put(" WRONG, want " & Fmt.LongInt(want) & "\n"); INC(failures) END;
  END Check;

VAR addr: IP.Address; port := DefaultPort;
BEGIN
  IF Params.Count > 2 THEN port := Scan.Int(Params.Get(2)) END;
  IF Params.Count > 1 AND Text.Equal(Params.Get(1), "server") THEN
    NetObj.Export("L", NEW(Impl), TCPNetObj.Listen(port));
    IO.Put("server ready\n");
    LOOP Thread.Pause(1.0D0) END;
  ELSE
    EVAL IP.GetHostByName("127.0.0.1", addr);
    WITH t = NARROW(NetObj.Import("L", TCPNetObj.Locate(IP.Endpoint{addr, port})), L.T) DO
      Check("add(2^40, 16_1ffffffff)", t.add(16_10000000000L, 16_1ffffffffL), 16_10000000000L + 16_1ffffffffL);
      Check("add(-2^40, 5)", t.add(-16_10000000000L, 5L), -16_10000000000L + 5L);
      Check("neg(LAST)", t.neg(LAST(LONGINT)), -LAST(LONGINT));
      Check("neg(-2^62)", t.neg(-16_4000000000000000L), 16_4000000000000000L);
      Check("half(16_1ffffffff)", t.half(16_1ffffffffL), 16_ffffffffL);
      Check("half(0)", t.half(0L), 0L);
      VAR a := 16_123456789L; b: L.Sub := 16_1fffffffeL; BEGIN
        t.swap(a, b);
        Check("swap a", a, 16_1fffffffeL);
        Check("swap b", b, 16_123456789L);
      END;
      (* Out of range for Sub: the server's unmarshaling must reject it.
         LOOPHOLE gets the value past the client's own check. *)
      TRY
        EVAL t.half(LOOPHOLE(16_200000000L, L.Sub));
        IO.Put("half out of range: NOT rejected WRONG\n"); INC(failures);
      EXCEPT NetObj.Error => IO.Put("half out of range: rejected ok\n");
      END;
      (* The server must still be alive. *)
      Check("neg(1) after rejection", t.neg(1L), -1L);
    END;
    IF failures > 0 THEN Process.Exit(1) END;
  END;
END LongintTest.
