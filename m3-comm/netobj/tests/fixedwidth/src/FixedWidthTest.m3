(* This fork: a network-object test of the fixed-width integer types
   (Word8.T .. Word64.T, Signed8.T .. Signed64.T), subranges of them, a
   VAR pair and a record.

   "fixedwidthtest server [port]" exports an object; "fixedwidthtest
   client [port]", in another process, calls it on 127.0.0.1 and checks
   the results, including that the server's unmarshaling rejects an
   out-of-range value.  The client prints "ok" or "WRONG" for each
   check and exits with status 1 if any is wrong.  The default port is
   18878.  ../../run-netobj-tests.sh runs both. *)

UNSAFE MODULE FixedWidthTest EXPORTS Main;
IMPORT F, NetObj, TCPNetObj, IP, IO, Fmt, Params, Process, Scan, Text, Thread,
       Word8, Word16, Word32, Word64, Signed8, Signed16, Signed32, Signed64, Lex, FloatMode;
<* FATAL IP.Error, NetObj.Error, Thread.Alerted, Lex.Error, FloatMode.Trap *>
CONST DefaultPort = 18878;
VAR failures := 0;
TYPE Impl = F.T OBJECT OVERRIDES
    w8 := W8; w16 := W16; w32 := W32; w64 := W64;
    s8 := S8; s16 := S16; s32 := S32; s64 := S64;
    wsub := WS; ssub := SS; w64sub := W64S; swap := Swap; rec := Rec;
    s8wide := S8Wide; asub := ASubM; wrapped := WrappedM; packed := PackedM END;
(* Word results wrap; signed ones negate. *)
PROCEDURE W8 (<*UNUSED*>s: Impl; x: Word8.T): Word8.T = BEGIN RETURN x + VAL(1, Word8.T) END W8;
PROCEDURE W16 (<*UNUSED*>s: Impl; x: Word16.T): Word16.T = BEGIN RETURN x + VAL(1, Word16.T) END W16;
PROCEDURE W32 (<*UNUSED*>s: Impl; x: Word32.T): Word32.T = BEGIN RETURN x + VAL(1, Word32.T) END W32;
PROCEDURE W64 (<*UNUSED*>s: Impl; x: Word64.T): Word64.T = BEGIN RETURN x + VAL(1, Word64.T) END W64;
PROCEDURE S8 (<*UNUSED*>s: Impl; x: Signed8.T): Signed8.T = BEGIN RETURN -x END S8;
PROCEDURE S16 (<*UNUSED*>s: Impl; x: Signed16.T): Signed16.T = BEGIN RETURN -x END S16;
PROCEDURE S32 (<*UNUSED*>s: Impl; x: Signed32.T): Signed32.T = BEGIN RETURN -x END S32;
PROCEDURE S64 (<*UNUSED*>s: Impl; x: Signed64.T): Signed64.T = BEGIN RETURN -x END S64;
PROCEDURE WS (<*UNUSED*>s: Impl; x: F.WSub): F.WSub = BEGIN RETURN x END WS;
PROCEDURE SS (<*UNUSED*>s: Impl; x: F.SSub): F.SSub = BEGIN RETURN x END SS;
PROCEDURE W64S (<*UNUSED*>s: Impl; x: F.W64Sub): F.W64Sub = BEGIN RETURN x END W64S;
PROCEDURE Swap (<*UNUSED*>s: Impl; VAR a: Word64.T; VAR b: Signed8.T) =
  VAR t := a; BEGIN a := VAL(b, Word64.T); b := VAL(t, Signed8.T) END Swap;
PROCEDURE Rec (<*UNUSED*>s: Impl; r: F.Rec): F.Rec =
  BEGIN RETURN F.Rec{r.a + VAL(1, Word8.T), -r.b, r.c} END Rec;
PROCEDURE S8Wide (<*UNUSED*>s: Impl; x: Signed16.T): Signed8.T =
  BEGIN RETURN VAL(x, Signed8.T) END S8Wide;
PROCEDURE ASubM (<*UNUSED*>s: Impl; x: F.ASub): F.ASub = BEGIN RETURN x END ASubM;
PROCEDURE WrappedM (<*UNUSED*>s: Impl; x: F.Wrapped): F.Wrapped = BEGIN RETURN x END WrappedM;
PROCEDURE PackedM (<*UNUSED*>s: Impl; x: F.PByte; y: F.PWrapped): F.PWrapped =
  BEGIN RETURN y + x END PackedM;

PROCEDURE Check (what: TEXT; got, want: LONGINT) =
  BEGIN
    IO.Put(what & " = " & Fmt.LongInt(got));
    IF got = want THEN IO.Put(" ok\n") ELSE IO.Put(" WRONG, want " & Fmt.LongInt(want) & "\n"); INC(failures) END;
  END Check;

VAR addr: IP.Address; port := DefaultPort;
BEGIN
  IF Params.Count > 2 THEN port := Scan.Int(Params.Get(2)) END;
  IF Params.Count > 1 AND Text.Equal(Params.Get(1), "server") THEN
    NetObj.Export("F", NEW(Impl), TCPNetObj.Listen(port));
    IO.Put("server ready\n");
    LOOP Thread.Pause(1.0D0) END;
  ELSE
    EVAL IP.GetHostByName("127.0.0.1", addr);
    WITH t = NARROW(NetObj.Import("F", TCPNetObj.Locate(IP.Endpoint{addr, port})), F.T) DO
      Check("w8(255)", VAL(t.w8(VAL(255, Word8.T)), LONGINT), 0L);
      Check("w8(7)", VAL(t.w8(VAL(7, Word8.T)), LONGINT), 8L);
      Check("w16(65535)", VAL(t.w16(VAL(65535, Word16.T)), LONGINT), 0L);
      Check("w32(16_ffffffff)", VAL(t.w32(VAL(16_ffffffffL, Word32.T)), LONGINT), 0L);
      Check("w32(16_fffffffe)", VAL(t.w32(VAL(16_fffffffeL, Word32.T)), LONGINT), 16_ffffffffL);
      Check("w64(max)", Word64.ToLong(t.w64(Word64.FromLong(-1L))), 0L);
      Check("w64(2^63-1)", Word64.ToLong(t.w64(Word64.FromLong(LAST(LONGINT)))), FIRST(LONGINT));
      Check("w64(2^63)", Word64.ToLong(t.w64(Word64.FromLong(FIRST(LONGINT)))), FIRST(LONGINT) + 1L);
      Check("s8(-127)", VAL(t.s8(VAL(-127, Signed8.T)), LONGINT), 127L);
      Check("s16(-32767)", VAL(t.s16(VAL(-32767, Signed16.T)), LONGINT), 32767L);
      Check("s32(-2147483647)", VAL(t.s32(VAL(-2147483647, Signed32.T)), LONGINT), 2147483647L);
      Check("s64(LAST)", VAL(t.s64(VAL(LAST(LONGINT), Signed64.T)), LONGINT), -LAST(LONGINT));
      Check("wsub(1000)", VAL(t.wsub(VAL(1000, Word32.T)), LONGINT), 1000L);
      Check("ssub(-100)", VAL(t.ssub(VAL(-100, Signed16.T)), LONGINT), -100L);
      Check("w64sub(16_ffffffffff)", Word64.ToLong(t.w64sub(VAL(16_ffffffffffL, Word64.T))), 16_ffffffffffL);
      VAR a := VAL(100, Word64.T); b := VAL(7, Signed8.T); BEGIN
        t.swap(a, b);
        Check("swap a", Word64.ToLong(a), 7L);
        Check("swap b", VAL(b, LONGINT), 100L);
      END;
      (* Out of range for W64Sub: the server's unmarshaling must reject
         it.  LOOPHOLE gets the value past the client's own check. *)
      TRY
        EVAL t.w64sub(LOOPHOLE(Word64.FromLong(-1L), F.W64Sub));
        IO.Put("w64sub(max) NOT rejected WRONG\n"); INC(failures);
      EXCEPT NetObj.Error => IO.Put("w64sub(max): rejected ok\n");
      END;
      (* The server must still be alive. *)
      Check("w8(1) after rejection", VAL(t.w8(VAL(1, Word8.T)), LONGINT), 2L);
      WITH r = t.rec(F.Rec{VAL(255, Word8.T), VAL(FIRST(LONGINT) + 1L, Signed64.T), VAL(10, Word32.T)}) DO
        Check("rec.a", VAL(r.a, LONGINT), 0L);
        Check("rec.b", VAL(r.b, LONGINT), LAST(LONGINT));
        Check("rec.c", VAL(r.c, LONGINT), 10L);
      END;
      (* A Signed16 argument narrowed by the server. *)
      Check("s8wide(-128)", VAL(t.s8wide(VAL(-128, Signed16.T)), LONGINT), -128L);
      (* Bounds folded by m3tk; see F.i3. *)
      Check("asub(LAST - 10)", VAL(t.asub(LAST(Word32.T) - VAL(10, Word32.T)), LONGINT), 16_fffffff5L);
      Check("wrapped(44)", VAL(t.wrapped(VAL(44, Word8.T)), LONGINT), 44L);
      TRY
        EVAL t.wrapped(LOOPHOLE(VAL(45, Word8.T), F.Wrapped));
        IO.Put("wrapped(45) NOT rejected WRONG\n"); INC(failures);
      EXCEPT NetObj.Error => IO.Put("wrapped(45): rejected ok\n");
      END;
      Check("packed(4, 40)", VAL(t.packed(VAL(4, Word8.T), VAL(40, Word8.T)), LONGINT), 44L);
    END;
    IF failures > 0 THEN Process.Exit(1) END;
  END;
END FixedWidthTest.
