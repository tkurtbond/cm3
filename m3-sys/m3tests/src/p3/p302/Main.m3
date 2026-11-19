(* This fork: Wrap round trips, and x + 1 > x at LAST, for Word8.T ..
   Word64.T.  See the readme. *)

MODULE Main;

IMPORT Fmt, IO, Word8, Word16, Word32, Word64;

VAR failures := 0;

PROCEDURE Hex (w: Word64.T): TEXT =
  BEGIN
    RETURN "16_" & Fmt.Unsigned (Word64.ToWord (w), 16);
  END Hex;

PROCEDURE Expect (what: TEXT;  ok: BOOLEAN) =
  BEGIN
    IF NOT ok THEN IO.Put ("FAILED: " & what & "\n");  INC (failures) END;
  END Expect;

PROCEDURE Int (x: INTEGER) =
  VAR
    w8  := Word8.Wrap (x);
    w16 := Word16.Wrap (x);
    w32 := Word32.Wrap (x);
    w64 := Word64.Wrap (x);
  BEGIN
    IO.Put (Fmt.Int (x) & ": " & Hex (Word64.Wrap (w8)) & " "
            & Hex (Word64.Wrap (w16)) & " " & Hex (Word64.Wrap (w32)) & " "
            & Hex (w64) & "\n");
    Expect ("Word8 " & Fmt.Int (x),
            Word64.Wrap (w8) = VAL (x MOD 16_100, Word64.T)
            AND VAL (w8, INTEGER) = x MOD 16_100);
    Expect ("Word16 " & Fmt.Int (x),
            Word64.Wrap (w16) = VAL (x MOD 16_10000, Word64.T)
            AND VAL (w16, INTEGER) = x MOD 16_10000);
    Expect ("Word32 " & Fmt.Int (x),
            Word64.Wrap (w32) = VAL (x MOD 16_100000000, Word64.T)
            AND VAL (w32, INTEGER) = x MOD 16_100000000);
    Expect ("Word64 " & Fmt.Int (x), Word64.ToWord (w64) = x);
    (* Wrapping a wider fixed type gives the same as wrapping x. *)
    Expect ("narrowing " & Fmt.Int (x),
            Word8.Wrap (w64) = w8 AND Word8.Wrap (w32) = w8
            AND Word8.Wrap (w16) = w8 AND Word16.Wrap (w64) = w16
            AND Word16.Wrap (w32) = w16 AND Word32.Wrap (w64) = w32);
  END Int;

PROCEDURE Long (x: LONGINT) =
  VAR
    w8  := Word8.Wrap (x);
    w16 := Word16.Wrap (x);
    w32 := Word32.Wrap (x);
    w64 := Word64.Wrap (x);
  BEGIN
    IO.Put (Fmt.LongInt (x) & "L: " & Hex (Word64.Wrap (w8)) & " "
            & Hex (Word64.Wrap (w16)) & " " & Hex (Word64.Wrap (w32)) & " "
            & Hex (w64) & "\n");
    Expect ("Word8 " & Fmt.LongInt (x) & "L",
            VAL (w8, LONGINT) = x MOD 16_100L);
    Expect ("Word16 " & Fmt.LongInt (x) & "L",
            VAL (w16, LONGINT) = x MOD 16_10000L);
    Expect ("Word32 " & Fmt.LongInt (x) & "L",
            VAL (w32, LONGINT) = x MOD 16_100000000L);
    Expect ("Word64 " & Fmt.LongInt (x) & "L", Word64.ToLong (w64) = x);
  END Long;

CONST
  Last8 = LAST (Word8.T);    One8 = VAL (1, Word8.T);
  Last16 = LAST (Word16.T);  One16 = VAL (1, Word16.T);
  Last32 = LAST (Word32.T);  One32 = VAL (1, Word32.T);
  Last64 = LAST (Word64.T);  One64 = VAL (1, Word64.T);

  (* Folded by the front end. *)
  Folded = ARRAY [0 .. 3] OF BOOLEAN {
    Last8 + One8 > Last8, Last16 + One16 > Last16,
    Last32 + One32 > Last32, Last64 + One64 > Last64 };

PROCEDURE Fmt4 (READONLY b: ARRAY [0 .. 3] OF BOOLEAN): TEXT =
  BEGIN
    RETURN Fmt.Bool (b[0]) & " " & Fmt.Bool (b[1]) & " " & Fmt.Bool (b[2])
             & " " & Fmt.Bool (b[3]);
  END Fmt4;

VAR
  v8 := Last8;  v16 := Last16;  v32 := Last32;  v64 := Last64;

CONST
  ints = ARRAY OF INTEGER {
    0, 1, -1, 127, 128, 255, 256, -128, -129, -256, 16_7fff, 16_8000,
    16_ffff, 16_10000, -16_8000, 16_7fffffff, 16_80000000, 16_ffffffff,
    16_100000000, -16_80000000, -16_80000001, 16_123456789abcdef,
    FIRST (INTEGER), LAST (INTEGER) };
  longs = ARRAY OF LONGINT {
    0L, -1L, 255L, 256L, -16_100000000L, 16_fedcba9876543210L,
    FIRST (LONGINT), LAST (LONGINT) };

BEGIN
  FOR i := FIRST (ints) TO LAST (ints) DO Int (ints[i]) END;
  FOR i := FIRST (longs) TO LAST (longs) DO Long (longs[i]) END;

  Expect ("Word64.Wrap (-1L) = LAST", Word64.Wrap (-1L) = LAST (Word64.T));
  Expect ("Word64.Wrap (-1) = LAST", Word64.Wrap (-1) = LAST (Word64.T));
  Expect ("Word8.Wrap (-1) = LAST", Word8.Wrap (-1) = LAST (Word8.T));

  IO.Put ("x + 1 > x at LAST, variables: "
          & Fmt4 (ARRAY [0 .. 3] OF BOOLEAN {
                    v8 + One8 > v8, v16 + One16 > v16,
                    v32 + One32 > v32, v64 + One64 > v64 }) & "\n");
  IO.Put ("x + 1 > x at LAST, constants: " & Fmt4 (Folded) & "\n");
  IO.Put ("x + 1 = 0 at LAST, variables: "
          & Fmt4 (ARRAY [0 .. 3] OF BOOLEAN {
                    v8 + One8 = FIRST (Word8.T), v16 + One16 = FIRST (Word16.T),
                    v32 + One32 = FIRST (Word32.T),
                    v64 + One64 = FIRST (Word64.T) }) & "\n");

  IO.Put (Fmt.Int (failures) & " failures\n");
END Main.
