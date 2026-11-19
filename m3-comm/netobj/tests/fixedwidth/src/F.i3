INTERFACE F;
IMPORT NetObj, Thread, Word8, Word16, Word32, Word64,
       Signed8, Signed16, Signed32, Signed64;
TYPE
  WSub = [VAL(10, Word32.T) .. VAL(1000, Word32.T)];
  SSub = [VAL(-100, Signed16.T) .. VAL(100, Signed16.T)];
  W64Sub = [VAL(0, Word64.T) .. VAL(16_ffffffffff, Word64.T)];
  Rec = RECORD a: Word8.T; b: Signed64.T; c: WSub END;
  T = NetObj.T OBJECT METHODS
    w8 (x: Word8.T): Word8.T RAISES {NetObj.Error, Thread.Alerted};
    w16 (x: Word16.T): Word16.T RAISES {NetObj.Error, Thread.Alerted};
    w32 (x: Word32.T): Word32.T RAISES {NetObj.Error, Thread.Alerted};
    w64 (x: Word64.T): Word64.T RAISES {NetObj.Error, Thread.Alerted};
    s8 (x: Signed8.T): Signed8.T RAISES {NetObj.Error, Thread.Alerted};
    s16 (x: Signed16.T): Signed16.T RAISES {NetObj.Error, Thread.Alerted};
    s32 (x: Signed32.T): Signed32.T RAISES {NetObj.Error, Thread.Alerted};
    s64 (x: Signed64.T): Signed64.T RAISES {NetObj.Error, Thread.Alerted};
    wsub (x: WSub): WSub RAISES {NetObj.Error, Thread.Alerted};
    ssub (x: SSub): SSub RAISES {NetObj.Error, Thread.Alerted};
    w64sub (x: W64Sub): W64Sub RAISES {NetObj.Error, Thread.Alerted};
    swap (VAR a: Word64.T; VAR b: Signed8.T) RAISES {NetObj.Error, Thread.Alerted};
    rec (r: Rec): Rec RAISES {NetObj.Error, Thread.Alerted};
    s8wide (x: Signed16.T): Signed8.T RAISES {NetObj.Error, Thread.Alerted};
  END;
END F.
