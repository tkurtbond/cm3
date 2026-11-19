(* Shared-object stubs (sharedobjgen) for LONGINT and a LONGINT subrange.

   "longinttest" alone runs the local checks: an update method, and
   pickling the object.
   "longinttest server [PORT [DEBUGLEVEL]]" makes itself the sequencer,
   runs the local checks, and exports its object space and a Holder.
   "longinttest client [PORT [DEBUGLEVEL]]", in another process, gets
   the server's local-check results and a replica of the server's L.T
   through the Holder, and calls an update method on it: its stubs
   marshal the arguments (SharedObjStubLib) and the server's unmarshal
   them, which the server checks.  Then the server calls the update
   method, and the client waits for its replica to see the values.
   The client prints "ok" or "WRONG" for each check and exits with
   status 1 if any is wrong.  The default port is 18879. *)
MODULE Main;
IMPORT L, Holder, IO, Fmt, Pickle2 AS Pickle, TextRd, TextWr, SharedObj,
       SharedObjRT, Thread, Rd, Wr, Process, Params, Scan, Text, NetObj,
       TCPNetObj, IP, Lex, FloatMode, ObjectSpace;
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

(* Values that don't fit in 32 bits, so a truncated or misplaced LONGINT
   shows. *)
PROCEDURE Set1 (o: L.T) =
  BEGIN
    o.set(FIRST(LONGINT) + 1L, 16_1ffffffffL);
  END Set1;
PROCEDURE Check1 (what: TEXT; v: L.Vals) =
  BEGIN
    Check(what & ".d", v.d, FIRST(LONGINT) + 1L);
    Check(what & ".h", v.h, 16_1ffffffffL);
  END Check1;
PROCEDURE Set2 (o: L.T) =
  BEGIN
    o.set(16_123456789L, 16_100000000L);
  END Set2;
PROCEDURE Check2 (what: TEXT; v: L.Vals) =
  BEGIN
    Check(what & ".d", v.d, 16_123456789L);
    Check(what & ".h", v.h, 16_100000000L);
  END Check2;

TYPE HolderImpl = Holder.T OBJECT o: L.T OVERRIDES
    get := HGet; check := HCheck; serverSet := HServerSet END;
PROCEDURE HGet (h: HolderImpl): L.T = BEGIN RETURN h.o END HGet;
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
    WITH o = NEW(L.T).init() DO
      Set1(o);
      Check1("get", o.get());
      WITH wr = TextWr.New() DO
        Pickle.Write(wr, o);
        Check1("pickled", NARROW(Pickle.Read(TextRd.New(TextWr.ToText(wr))), L.T).get());
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
      NetObj.Export("holder", NEW(HolderImpl, o := NEW(L.T).init()), listen);
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
          WHILE o.get().d # 16_123456789L AND tries < 100 DO
            Thread.Pause(0.1D0); INC(tries)
          END;
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
