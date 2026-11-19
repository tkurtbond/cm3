(* This fork: the shared object of ../src/Main.m3. *)
INTERFACE FW;
IMPORT SharedObj, Thread, Word8, Word32, Word64, Signed8, Signed64;
<*PRAGMA SHARED *>
TYPE
  WSub = [VAL(10, Word32.T) .. VAL(1000, Word32.T)];
  W64Sub = [VAL(0, Word64.T) .. VAL(16_ffffffffff, Word64.T)];
  LSub = [-5L .. 5L];
  Vals = RECORD
    a: Word8.T; b: Signed64.T; c: Word64.T; d: LONGINT;
    e: WSub; f: W64Sub; g: Signed8.T; h: LSub;
  END;
  T <: S;
  S <: Public;
  Public = SharedObj.T OBJECT
  METHODS
    init (): T RAISES {SharedObj.Error};
    set (a: Word8.T; b: Signed64.T; c: Word64.T; d: LONGINT;
         e: WSub; f: W64Sub; g: Signed8.T; h: LSub) RAISES {SharedObj.Error};
    get (): Vals RAISES {SharedObj.Error, Thread.Alerted};
    <* SHARED UPDATE METHODS T.set, T.init *>
  END;
END FW.
