(* This fork: the procedures of the builtin interfaces Signed8 ..
   Signed64, and Wrap from the other integer types. *)

MODULE Main;
IMPORT Exercise8, Exercise16, Exercise32, Exercise64;
IMPORT Signed8, Signed16, Signed32, Signed64;
IMPORT Word8, Word32, Word64;
IMPORT IO, Fmt;

CONST
  (* folded *)
  F1 = Signed32.Wrap (Word32.Wrap (16_ffffffff));    (* -1 *)
  F2 = Signed8.Wrap (Word8.Wrap (200));              (* -56 *)
  F3 = Signed16.Wrap (Word8.Wrap (255));             (* 255 *)
  F4 = Signed64.Wrap (Word64.Wrap (-1));             (* -1 *)
  F5 = Signed8.Wrap (Signed64.Wrap (300));           (* 44 *)
  F6 = Signed16.Wrap (Signed8.Wrap (-128));          (* -128 *)
  F7 = Signed32.Wrap (Word64.Wrap (16_180000000L));  (* FIRST (Signed32.T) *)

PROCEDURE P (name: TEXT;  v: LONGINT) =
  BEGIN
    IO.Put (name & " = " & Fmt.LongInt (v) & "\n");
  END P;

VAR
  w32 := Word32.Wrap (16_ffffffff);  w8 := Word8.Wrap (200);
  w8b := Word8.Wrap (255);  w64 := Word64.Wrap (-1);
  s64 := Signed64.Wrap (300);  s8 := Signed8.Wrap (-128);
  w64b := Word64.Wrap (16_180000000L);
BEGIN
  Exercise8.Run ();
  Exercise16.Run ();
  Exercise32.Run ();
  Exercise64.Run ();

  IO.Put ("== Wrap from the other types, folded\n");
  P ("Signed32.Wrap (Word32 16_ffffffff)", VAL (F1, LONGINT));
  P ("Signed8.Wrap (Word8 200)", VAL (F2, LONGINT));
  P ("Signed16.Wrap (Word8 255)", VAL (F3, LONGINT));
  P ("Signed64.Wrap (Word64 LAST)", VAL (F4, LONGINT));
  P ("Signed8.Wrap (Signed64 300)", VAL (F5, LONGINT));
  P ("Signed16.Wrap (Signed8 -128)", VAL (F6, LONGINT));
  P ("Signed32.Wrap (Word64 16_180000000)", VAL (F7, LONGINT));

  IO.Put ("== Wrap from the other types, inline\n");
  P ("Signed32.Wrap (Word32 16_ffffffff)", VAL (Signed32.Wrap (w32), LONGINT));
  P ("Signed8.Wrap (Word8 200)", VAL (Signed8.Wrap (w8), LONGINT));
  P ("Signed16.Wrap (Word8 255)", VAL (Signed16.Wrap (w8b), LONGINT));
  P ("Signed64.Wrap (Word64 LAST)", VAL (Signed64.Wrap (w64), LONGINT));
  P ("Signed8.Wrap (Signed64 300)", VAL (Signed8.Wrap (s64), LONGINT));
  P ("Signed16.Wrap (Signed8 -128)", VAL (Signed16.Wrap (s8), LONGINT));
  P ("Signed32.Wrap (Word64 16_180000000)", VAL (Signed32.Wrap (w64b), LONGINT));
END Main.
