INTERFACE L;
IMPORT NetObj, Thread;
TYPE
  Sub = [-5L .. 16_1ffffffffL];
  T = NetObj.T OBJECT METHODS
    add (x: LONGINT; y: Sub): LONGINT RAISES {NetObj.Error, Thread.Alerted};
    neg (x: LONGINT): LONGINT RAISES {NetObj.Error, Thread.Alerted};
    half (x: Sub): Sub RAISES {NetObj.Error, Thread.Alerted};
    swap (VAR a: LONGINT; VAR b: Sub) RAISES {NetObj.Error, Thread.Alerted};
  END;
END L.
