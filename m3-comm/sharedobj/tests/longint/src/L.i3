(* The shared object of Main.m3. *)
INTERFACE L;
IMPORT SharedObj, Thread;
<*PRAGMA SHARED *>
TYPE
  Sub = [1L .. 16_1ffffffffL];
  Vals = RECORD d: LONGINT; h: Sub END;
  T <: S;
  S <: Public;
  Public = SharedObj.T OBJECT
  METHODS
    init (): T RAISES {SharedObj.Error};
    set (d: LONGINT; h: Sub) RAISES {SharedObj.Error};
    get (): Vals RAISES {SharedObj.Error, Thread.Alerted};
    <* SHARED UPDATE METHODS T.set, T.init *>
  END;
END L.
