(* Hands the client the server's L.T, and checks it. *)
INTERFACE Holder;
IMPORT NetObj, L, Thread;
TYPE T = NetObj.T OBJECT METHODS
  get (): L.T RAISES {NetObj.Error, Thread.Alerted};
  check (): TEXT RAISES {NetObj.Error, Thread.Alerted};
  serverSet () RAISES {NetObj.Error, Thread.Alerted};
END;
END Holder.
