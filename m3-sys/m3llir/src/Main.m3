(* See the file COPYRIGHT for a full description. *)

(* m3llir [-a] [-g] [-t TARGET] [-o OUTPUT] [INPUT]

   Read the M3CG IR of one unit (binary by default, ASCII with -a) from
   INPUT or standard input, and write it as textual LLVM IR to OUTPUT
   or standard output.  The target comes from -t, or else from the
   TARGET in the cm3 configuration.  -g adds debug information. *)

MODULE Main;

IMPORT FileRd, FileWr, OSError, Params, Process, Rd, Stdio, Text, Wr;
IMPORT Thread, M3CG_Rd, M3CG_BinRd, MxConfig, Target, M3LLVMIR;

<*FATAL Wr.Failure, Thread.Alerted*>

VAR
  ascii   := FALSE;
  debug   := FALSE;
  target  : TEXT := NIL;
  inName  : TEXT := NIL;
  outName : TEXT := NIL;

PROCEDURE Die (msg: TEXT) =
  BEGIN
    Wr.PutText (Stdio.stderr, "m3llir: " & msg & Wr.EOL);
    Wr.Flush (Stdio.stderr);
    Process.Exit (1);
  END Die;

PROCEDURE Usage () =
  BEGIN
    Die ("usage: m3llir [-a] [-g] [-t TARGET] [-o OUTPUT] [INPUT]");
  END Usage;

PROCEDURE GetParams () =
  VAR i := 1;  p: TEXT;
  BEGIN
    WHILE i < Params.Count DO
      p := Params.Get (i);
      IF Text.Equal (p, "-a") THEN
        ascii := TRUE;
      ELSIF Text.Equal (p, "-g") THEN
        debug := TRUE;
      ELSIF Text.Equal (p, "-b") THEN
        ascii := FALSE;
      ELSIF Text.Equal (p, "-o") OR Text.Equal (p, "-t") THEN
        IF i + 1 >= Params.Count THEN Usage () END;
        IF Text.Equal (p, "-o")
          THEN outName := Params.Get (i + 1);
          ELSE target := Params.Get (i + 1);
        END;
        INC (i);
      ELSIF Text.Length (p) > 1 AND Text.GetChar (p, 0) = '-' THEN
        Usage ();
      ELSIF inName = NIL THEN
        inName := p;
      ELSE
        Usage ();
      END;
      INC (i);
    END;
  END GetParams;

PROCEDURE DoIt () =
  VAR rd: Rd.T := Stdio.stdin;  wr: Wr.T := Stdio.stdout;
  BEGIN
    IF target = NIL THEN target := MxConfig.Get ("TARGET") END;
    IF target = NIL THEN Die ("no TARGET; use -t") END;
    IF NOT Target.Init (target, "POSIX",
                        Target.M3BackendMode_t.LlvmIR) THEN
      Die ("unknown target: " & target);
    END;
    IF M3LLVMIR.TargetTriple () = NIL THEN
      Die ("target not supported yet: " & target);
    END;
    TRY
      IF inName # NIL AND NOT Text.Equal (inName, "-") THEN
        rd := FileRd.Open (inName);
      END;
      IF outName # NIL AND NOT Text.Equal (outName, "-") THEN
        wr := FileWr.Open (outName);
      END;
    EXCEPT OSError.E =>
      Die ("cannot open " & inName & " or " & outName);
    END;
    WITH cg = M3LLVMIR.New (wr, debug) DO
      IF ascii
        THEN M3CG_Rd.Inhale (rd, cg);
        ELSE M3CG_BinRd.Inhale (rd, cg);
      END;
    END;
    Wr.Close (wr);
  END DoIt;

BEGIN
  GetParams ();
  DoIt ();
END Main.
