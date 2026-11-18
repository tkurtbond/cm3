(* RTTipe sizes subranges the way the compiler does; see readme. *)

MODULE Main;
IMPORT RTTipe, RTPacking, IO, Fmt;

TYPE
  T1  = REF RECORD a: [0..255] END;
  T2  = REF RECORD a: [0..256] END;
  T3  = REF RECORD a: [-63..63] END;
  T4  = REF RECORD a: [-1..255] END;
  T5  = REF RECORD a: [-256..0] END;
  T5a = REF RECORD a: [-129..0] END;
  T5b = REF RECORD a: [-200..-64] END;
  T5c = REF RECORD a: [-255..16_ffffff] END;
  T6  = REF RECORD a: [0..65535] END;
  T7  = REF RECORD a: [0..65536] END;
  T8  = REF RECORD a: [-32768..32767] END;
  T9  = REF RECORD a: [-1..32768] END;
  T10 = REF RECORD a: [0..16_ffffffff] END;
  T11 = REF RECORD a: [0..16_100000000] END;
  T12 = REF RECORD a: [-16_80000000..16_7fffffff] END;
  T13 = REF RECORD a: [-1..16_80000000] END;
  T14 = REF RECORD a: [0L..16_ffffffffL] END;
  T15 = REF RECORD a: [0L..16_1ffffffffL] END;
  T16 = REF RECORD a: [-16_80000001L..0L] END;
  T17 = REF RECORD a: [0L..LAST (LONGINT)] END;
  T18 = REF RECORD a: [FIRST (LONGINT)..0L] END;
  T19 = REF RECORD a: [-1L..LAST (LONGINT)] END;
  T20 = REF RECORD a: [0..LAST (INTEGER)] END;
  T21 = REF RECORD a: [FIRST (INTEGER)..LAST (INTEGER)] END;

PROCEDURE Check (name: TEXT;  tc, bits: INTEGER) =
  VAR p := RTPacking.Local ();  size: INTEGER;  ok := TRUE;
  BEGIN
    FOR w := 32 TO 64 BY 32 DO
      p.word_size := w;
      size := NARROW (RTTipe.Get (tc, p), RTTipe.Record).fields.type.size;
      IF size # bits THEN
        ok := FALSE;
        IO.Put (name & ", word size " & Fmt.Int (w) & ": RTTipe "
          & Fmt.Int (size) & ", BITSIZE " & Fmt.Int (bits) & "\n");
      END;
    END;
    IF ok THEN IO.Put (name & ": ok\n"); END;
  END Check;

PROCEDURE CheckBounds (name: TEXT;  tc, min, max: INTEGER) =
  (* Bounds that fit in an INTEGER, as RTTipe reads them back. *)
  VAR f := NARROW (RTTipe.Get (tc, RTPacking.Local ()), RTTipe.Record).fields;
      sub := NARROW (f.type, RTTipe.Subrange);
  BEGIN
    IF sub.min.Lo = min AND sub.max.Lo = max THEN
      IO.Put (name & " bounds: ok\n");
    ELSE
      IO.Put (name & " bounds: RTTipe [" & Fmt.Int (sub.min.Lo) & ".."
        & Fmt.Int (sub.max.Lo) & "]\n");
    END;
  END CheckBounds;

VAR
  v1: T1;  v2: T2;  v3: T3;  v4: T4;  v5: T5;  v6: T6;  v7: T7;  v8: T8;
  v9: T9;  v10: T10;  v11: T11;  v12: T12;  v13: T13;  v14: T14;
  v15: T15;  v16: T16;  v17: T17;  v18: T18;  v19: T19;  v20: T20;
  v21: T21;  v5a: T5a;  v5b: T5b;  v5c: T5c;
BEGIN
  Check ("[0..255]", TYPECODE (T1), BITSIZE (v1.a));
  Check ("[0..256]", TYPECODE (T2), BITSIZE (v2.a));
  Check ("[-63..63]", TYPECODE (T3), BITSIZE (v3.a));
  Check ("[-1..255]", TYPECODE (T4), BITSIZE (v4.a));
  Check ("[-256..0]", TYPECODE (T5), BITSIZE (v5.a));
  Check ("[-129..0]", TYPECODE (T5a), BITSIZE (v5a.a));
  Check ("[-200..-64]", TYPECODE (T5b), BITSIZE (v5b.a));
  Check ("[-255..16_ffffff]", TYPECODE (T5c), BITSIZE (v5c.a));
  Check ("[0..65535]", TYPECODE (T6), BITSIZE (v6.a));
  Check ("[0..65536]", TYPECODE (T7), BITSIZE (v7.a));
  Check ("[-32768..32767]", TYPECODE (T8), BITSIZE (v8.a));
  Check ("[-1..32768]", TYPECODE (T9), BITSIZE (v9.a));
  Check ("[0..16_ffffffff]", TYPECODE (T10), BITSIZE (v10.a));
  Check ("[0..16_100000000]", TYPECODE (T11), BITSIZE (v11.a));
  Check ("[-16_80000000..16_7fffffff]", TYPECODE (T12), BITSIZE (v12.a));
  Check ("[-1..16_80000000]", TYPECODE (T13), BITSIZE (v13.a));
  Check ("[0L..16_ffffffffL]", TYPECODE (T14), BITSIZE (v14.a));
  Check ("[0L..16_1ffffffffL]", TYPECODE (T15), BITSIZE (v15.a));
  Check ("[-16_80000001L..0L]", TYPECODE (T16), BITSIZE (v16.a));
  Check ("[0L..LAST(LONGINT)]", TYPECODE (T17), BITSIZE (v17.a));
  Check ("[FIRST(LONGINT)..0L]", TYPECODE (T18), BITSIZE (v18.a));
  Check ("[-1L..LAST(LONGINT)]", TYPECODE (T19), BITSIZE (v19.a));
  Check ("[0..LAST(INTEGER)]", TYPECODE (T20), BITSIZE (v20.a));
  Check ("[FIRST(INTEGER)..LAST(INTEGER)]", TYPECODE (T21), BITSIZE (v21.a));
  CheckBounds ("[-63..63]", TYPECODE (T3), -63, 63);
  CheckBounds ("[-256..0]", TYPECODE (T5), -256, 0);
  CheckBounds ("[-129..0]", TYPECODE (T5a), -129, 0);
  CheckBounds ("[-200..-64]", TYPECODE (T5b), -200, -64);
  CheckBounds ("[-255..16_ffffff]", TYPECODE (T5c), -255, 16_ffffff);
  CheckBounds ("[-32768..32767]", TYPECODE (T8), -32768, 32767);
END Main.
