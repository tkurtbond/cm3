(* This fork: shared-object stubs (sharedobjgen) for the fixed-width
   integer types (Word8.T .. Word64.T, Signed8.T .. Signed64.T),
   subranges of them, LONGINT and a LONGINT subrange.

   "fixedwidthtest" alone runs the local checks: an update method, and
   pickling the object (its fields go through PickleStubs).
   "fixedwidthtest server PORT [DEBUGLEVEL]" makes itself the sequencer,
   runs the local checks, and exports its object space and a Holder.
   (The client can't run them: pickling an object makes the client's
   space a sequencer, and then it can't use the server's.)
   "fixedwidthtest client PORT [DEBUGLEVEL]", in another process, gets
   the server's local-check results and a replica of the server's FW.T
   through the Holder, and calls an update
   method on it: its stubs marshal the arguments (SharedObjStubLib) and
   the server's unmarshal them, which the server checks.  Then the
   server calls the update method, and the client waits for its replica
   to see the values.  The client prints "ok" or "WRONG" for each check
   and exits with status 1 if any is wrong.
   ../../../../netobj/tests/run-netobj-tests.sh runs both. *)
MODULE Main;
IMPORT FW, Holder, IO, Fmt, Pickle2 AS Pickle, TextRd, TextWr, Word8, Word32,
       Word64, Signed8, Signed64, SharedObj, SharedObjRT, Thread, Rd, Wr,
       Process, Params, Scan, Text, NetObj, TCPNetObj, IP, Lex, FloatMode,
       ObjectSpace;
<* FATAL SharedObj.Error, Thread.Alerted, Pickle.Error, Rd.Failure, Wr.Failure,
         Rd.EndOfFile, NetObj.Error, IP.Error, Lex.Error, FloatMode.Trap,
         TCPNetObj.Failed *>
VAR failures := 0; log, localLog: TEXT := "";
PROCEDURE Check (what: TEXT; got, want: LONGINT) =
  VAR line := what & " = " & Fmt.LongInt(got);
  BEGIN
    IF got = want THEN line := line & " ok\n"
    ELSE line := line & " WRONG, want " & Fmt.LongInt(want) & "\n"; INC(failures)
    END;
    log := log & line;
  END Check;

PROCEDURE Set1 (o: FW.T) =
  BEGIN
    o.set(VAL(255, Word8.T), VAL(FIRST(LONGINT), Signed64.T), Word64.FromLong(-2L),
          FIRST(LONGINT) + 1L, VAL(1000, Word32.T), VAL(16_ffffffffffL, Word64.T),
          VAL(-128, Signed8.T), -5L);
  END Set1;
PROCEDURE Check1 (what: TEXT; v: FW.Vals) =
  BEGIN
    Check(what & ".a", VAL(v.a, LONGINT), 255L);
    Check(what & ".b", VAL(v.b, LONGINT), FIRST(LONGINT));
    Check(what & ".c", Word64.ToLong(v.c), -2L);
    Check(what & ".d", v.d, FIRST(LONGINT) + 1L);
    Check(what & ".e", VAL(v.e, LONGINT), 1000L);
    Check(what & ".f", Word64.ToLong(v.f), 16_ffffffffffL);
    Check(what & ".g", VAL(v.g, LONGINT), -128L);
    Check(what & ".h", v.h, -5L);
  END Check1;
PROCEDURE Set2 (o: FW.T) =
  BEGIN
    o.set(VAL(1, Word8.T), VAL(LAST(LONGINT), Signed64.T), Word64.FromLong(FIRST(LONGINT)),
          7L, VAL(10, Word32.T), VAL(0, Word64.T), VAL(127, Signed8.T), 5L);
  END Set2;
PROCEDURE Check2 (what: TEXT; v: FW.Vals) =
  BEGIN
    Check(what & ".a", VAL(v.a, LONGINT), 1L);
    Check(what & ".b", VAL(v.b, LONGINT), LAST(LONGINT));
    Check(what & ".c", Word64.ToLong(v.c), FIRST(LONGINT));
    Check(what & ".d", v.d, 7L);
    Check(what & ".e", VAL(v.e, LONGINT), 10L);
    Check(what & ".f", Word64.ToLong(v.f), 0L);
    Check(what & ".g", VAL(v.g, LONGINT), 127L);
    Check(what & ".h", v.h, 5L);
  END Check2;

TYPE HolderImpl = Holder.T OBJECT o: FW.T OVERRIDES
    get := HGet; check := HCheck; serverSet := HServerSet END;
PROCEDURE HGet (h: HolderImpl): FW.T = BEGIN RETURN h.o END HGet;
(* The server's local checks and its check of the client's update;
   returns the lines for the client to print. *)
PROCEDURE HCheck (h: HolderImpl): TEXT =
  BEGIN
    VAR tries := 0; BEGIN
      WHILE h.o.get().d = 0L AND tries < 50 DO Thread.Pause(0.1D0); INC(tries) END;
    END;
    log := localLog; Check1("server sees client's set", h.o.get());
    RETURN log;
  END HCheck;
PROCEDURE HServerSet (h: HolderImpl) = BEGIN Set2(h.o) END HServerSet;

PROCEDURE Local () =
  BEGIN
    WITH o = NEW(FW.T).init() DO
      Set1(o);
      Check1("get", o.get());
      WITH wr = TextWr.New() DO
        Pickle.Write(wr, o);
        Check1("pickled", NARROW(Pickle.Read(TextRd.New(TextWr.ToText(wr))), FW.T).get());
      END;
    END;
  END Local;

VAR port := 18879; addr: IP.Address;
BEGIN
  IF Params.Count > 3 THEN SharedObjRT.DebugLevel(Scan.Int(Params.Get(3))) END;
  IF Params.Count > 2 THEN port := Scan.Int(Params.Get(2)) END;
  IF Params.Count > 1 AND Text.Equal(Params.Get(1), "server") THEN
    WITH space = SharedObjRT.LocalSpace(), listen = TCPNetObj.Listen(port) DO
      SharedObjRT.SetDfltSequencer(space);
      Local(); localLog := log; log := "";
      NetObj.Export("space", space, listen);
      NetObj.Export("holder", NEW(HolderImpl, o := NEW(FW.T).init()), listen);
    END;
    IO.Put("server ready\n");
    LOOP Thread.Pause(1.0D0) END;
  ELSIF Params.Count > 1 AND Text.Equal(Params.Get(1), "client") THEN
    EVAL IP.GetHostByName("127.0.0.1", addr);
    WITH agent = TCPNetObj.Locate(IP.Endpoint{addr, port}),
         space = NARROW(NetObj.Import("space", agent), ObjectSpace.T),
         h = NARROW(NetObj.Import("holder", agent), Holder.T) DO
      SharedObjRT.SetDfltSequencer(space);
      WITH o = h.get() DO
        Set1(o);
        WITH t = h.check() DO
          IO.Put(t);
          IF Text.FindChar(t, 'W') >= 0 THEN INC(failures) END; (* WRONG *)
        END;
        h.serverSet();
        (* The update reaches the replica asynchronously. *)
        VAR tries := 0; BEGIN
          WHILE o.get().d # 7L AND tries < 100 DO Thread.Pause(0.1D0); INC(tries) END;
        END;
        Check2("client sees server's set", o.get());
        IO.Put(log);
      END;
    END;
  ELSE
    Local(); IO.Put(log);
  END;
  IF failures > 0 THEN Process.Exit(1) END;
  IO.Put("all ok\n");
END Main.
