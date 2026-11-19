(* This fork: hands the client the server's FW.T, and checks it. *)
INTERFACE Holder;
IMPORT NetObj, FW, Thread;
TYPE T = NetObj.T OBJECT METHODS
  get (): FW.T RAISES {NetObj.Error, Thread.Alerted};
  check (): TEXT RAISES {NetObj.Error, Thread.Alerted};
  serverSet () RAISES {NetObj.Error, Thread.Alerted};
END;
END Holder.
