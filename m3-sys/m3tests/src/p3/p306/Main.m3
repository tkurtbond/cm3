(* ConvertPacking converts fixed-width fields between packings;
   see readme. *)

UNSAFE MODULE Main;
IMPORT ConvertPacking, RTPacking, Pickle2, RuntimeError, IO, Fmt, Long,
       Word8, Word16, Word32, Word64, Signed8, Signed16, Signed32, Signed64;

TYPE
  TI   = REF RECORD a: INTEGER END;
  TL   = REF RECORD a: LONGINT END;
  TLS  = REF RECORD a: [0L..16_1ffffffffL] END;
  TW8  = REF RECORD a: Word8.T END;
  TW16 = REF RECORD a: Word16.T END;
  TW32 = REF RECORD a: Word32.T END;
  TW64 = REF RECORD a: Word64.T END;
  TS8  = REF RECORD a: Signed8.T END;
  TS16 = REF RECORD a: Signed16.T END;
  TS32 = REF RECORD a: Signed32.T END;
  TS64 = REF RECORD a: Signed64.T END;

  (* Hands the converter the bytes in buf. *)
  Source = ConvertPacking.ReadVisitor OBJECT
    buf := ARRAY [0 .. 15] OF CHAR {'\000', ..};
    pos := 0;
  OVERRIDES
    readData := ReadData;
    skipData := SkipData;
    readRef := ReadRef;
    readChar := ReadChar;
    getReader := GetReader;
  END;

PROCEDURE ReadData (s: Source; VAR data: ARRAY OF CHAR) =
  BEGIN
    FOR i := 0 TO LAST (data) DO data[i] := s.buf[s.pos];  INC (s.pos) END;
  END ReadData;

PROCEDURE SkipData (s: Source; length: INTEGER) =
  BEGIN
    INC (s.pos, length);
  END SkipData;

PROCEDURE ReadRef (<*UNUSED*> s: Source;
                   <*UNUSED*> type: ConvertPacking.RefType): REFANY =
  BEGIN
    <* ASSERT FALSE *>
  END ReadRef;

PROCEDURE ReadChar (s: Source): CHAR =
  BEGIN
    INC (s.pos);
    RETURN s.buf[s.pos - 1];
  END ReadChar;

PROCEDURE GetReader (<*UNUSED*> s: Source): Pickle2.Reader =
  BEGIN
    RETURN NIL;
  END GetReader;

VAR fails := 0;

(* Converts the low "bytes" bytes of v, laid out as "from" would, into
   the field at "dest" (an object of typecode tc).  Returns FALSE, after
   printing why, if the conversion fails. *)
PROCEDURE Convert (tc: INTEGER;  dest: ADDRESS;  v: LONGINT;
                   bytes: INTEGER;  READONLY from: RTPacking.T): BOOLEAN =
  VAR s := NEW (Source);  n, fe, te: INTEGER;  c: ConvertPacking.T;
  BEGIN
    FOR i := 0 TO bytes - 1 DO
      WITH b = VAL (Long.Extract (v, 8 * i, 8), INTEGER) DO
        IF from.little_endian THEN
          s.buf[i] := VAL (b, CHAR);
        ELSE
          s.buf[bytes - 1 - i] := VAL (b, CHAR);
        END;
      END;
    END;
    TRY
      c := ConvertPacking.New (tc, from, RTPacking.Local (), n, fe, te);
      EVAL c.convertRead (dest, s, 1);
    EXCEPT
    | ConvertPacking.Error (t) =>
        IO.Put (" Error (" & t & ")");  RETURN FALSE;
    | RuntimeError.E (e) =>
        IO.Put (" RuntimeError " & RuntimeError.Tag (e));  RETURN FALSE;
    ELSE
        IO.Put (" exception");  RETURN FALSE;
    END;
    RETURN TRUE;
  END Convert;

PROCEDURE Report (ok: BOOLEAN) =
  BEGIN
    IF ok THEN IO.Put (" ok") ELSE IO.Put (" FAIL");  INC (fails) END;
  END Report;

PROCEDURE Packing (w: INTEGER;  le: BOOLEAN): RTPacking.T =
  VAR p := RTPacking.Local ();
  BEGIN
    p.word_size := w;
    p.little_endian := le;
    RETURN p;
  END Packing;

PROCEDURE Name (w: INTEGER;  le: BOOLEAN): TEXT =
  BEGIN
    RETURN ARRAY BOOLEAN OF TEXT {"BE", "LE"}[le] & Fmt.Int (w) & ":";
  END Name;

BEGIN
  FOR w := 32 TO 64 BY 32 DO
    FOR le := FALSE TO TRUE DO
      WITH p = Packing (w, le) DO
        IO.Put (Name (w, le) & "\n");

        IO.Put ("  INTEGER   ");
        WITH r = NEW (TI) DO
          Report (Convert (TYPECODE (TI), ADR (r^), -5L, w DIV 8, p)
                  AND r.a = -5);
        END;
        IO.Put ("\n  LONGINT   ");
        WITH r = NEW (TL) DO
          Report (Convert (TYPECODE (TL), ADR (r^), -16_123456789L, 8, p)
                  AND r.a = -16_123456789L);
        END;
        IO.Put ("\n  [0L..2^33)");
        WITH r = NEW (TLS) DO
          Report (Convert (TYPECODE (TLS), ADR (r^), 16_1fedcba98L, 8, p)
                  AND r.a = 16_1fedcba98L);
        END;

        IO.Put ("\n  Word8     ");
        WITH r = NEW (TW8) DO
          Report (Convert (TYPECODE (TW8), ADR (r^), 16_abL, 1, p)
                  AND r.a = Word8.Wrap (16_ab));
        END;
        IO.Put ("\n  Word16    ");
        WITH r = NEW (TW16) DO
          Report (Convert (TYPECODE (TW16), ADR (r^), 16_abcdL, 2, p)
                  AND r.a = Word16.Wrap (16_abcd));
        END;
        IO.Put ("\n  Word32    ");
        WITH r = NEW (TW32) DO
          Report (Convert (TYPECODE (TW32), ADR (r^), 16_89abcdefL, 4, p)
                  AND r.a = Word32.Wrap (16_89abcdef));
        END;
        IO.Put ("\n  Word64    ");
        WITH r = NEW (TW64) DO
          Report (Convert (TYPECODE (TW64), ADR (r^),
                           16_fedcba9876543210L, 8, p)
                  AND r.a = Word64.Wrap (16_fedcba9876543210L));
        END;

        IO.Put ("\n  Signed8   ");
        WITH r = NEW (TS8) DO
          Report (Convert (TYPECODE (TS8), ADR (r^), -2L, 1, p)
                  AND r.a = Signed8.Wrap (-2));
        END;
        IO.Put ("\n  Signed16  ");
        WITH r = NEW (TS16) DO
          Report (Convert (TYPECODE (TS16), ADR (r^), -300L, 2, p)
                  AND r.a = Signed16.Wrap (-300));
        END;
        IO.Put ("\n  Signed32  ");
        WITH r = NEW (TS32) DO
          Report (Convert (TYPECODE (TS32), ADR (r^), -16_12345678L, 4, p)
                  AND r.a = Signed32.Wrap (-16_12345678));
        END;
        IO.Put ("\n  Signed64  ");
        WITH r = NEW (TS64) DO
          Report (Convert (TYPECODE (TS64), ADR (r^),
                           -16_123456789abcdefL, 8, p)
                  AND r.a = Signed64.Wrap (-16_123456789abcdefL));
        END;
        IO.Put ("\n");
      END;
    END;
  END;
  IF fails = 0 THEN
    IO.Put ("all conversions ok\n");
  ELSE
    IO.Put (Fmt.Int (fails) & " conversions failed\n");
  END;
END Main.
