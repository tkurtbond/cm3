(* This fork: SHA256 (FIPS PUB 180-4) on Word32.T, for test p301.  It
   follows libm3's SHA256, by Peter McKinna, but needs no masking: a
   Word32.T sum wraps modulo 2^32 by itself.  The constants are written
   with VAL, since a Word32.T can't be written as a literal. *)

MODULE Sha256W32;

IMPORT Fmt, Text, Word32, Word64;
FROM Word32 IMPORT And, Or, Xor, Not, LeftShift, RightShift, RightRotate;

TYPE
  W = Word32.T;
  State = ARRAY [0 .. 7] OF W;
  Block = ARRAY [0 .. 63] OF [0 .. 255];

CONST
  (* The first 32 bits of the fractional parts of the cube roots of the
     first 64 primes. *)
  K = ARRAY [0 .. 63] OF W {
    VAL (16_428a2f98, W), VAL (16_71374491, W), VAL (16_b5c0fbcf, W),
    VAL (16_e9b5dba5, W), VAL (16_3956c25b, W), VAL (16_59f111f1, W),
    VAL (16_923f82a4, W), VAL (16_ab1c5ed5, W), VAL (16_d807aa98, W),
    VAL (16_12835b01, W), VAL (16_243185be, W), VAL (16_550c7dc3, W),
    VAL (16_72be5d74, W), VAL (16_80deb1fe, W), VAL (16_9bdc06a7, W),
    VAL (16_c19bf174, W), VAL (16_e49b69c1, W), VAL (16_efbe4786, W),
    VAL (16_0fc19dc6, W), VAL (16_240ca1cc, W), VAL (16_2de92c6f, W),
    VAL (16_4a7484aa, W), VAL (16_5cb0a9dc, W), VAL (16_76f988da, W),
    VAL (16_983e5152, W), VAL (16_a831c66d, W), VAL (16_b00327c8, W),
    VAL (16_bf597fc7, W), VAL (16_c6e00bf3, W), VAL (16_d5a79147, W),
    VAL (16_06ca6351, W), VAL (16_14292967, W), VAL (16_27b70a85, W),
    VAL (16_2e1b2138, W), VAL (16_4d2c6dfc, W), VAL (16_53380d13, W),
    VAL (16_650a7354, W), VAL (16_766a0abb, W), VAL (16_81c2c92e, W),
    VAL (16_92722c85, W), VAL (16_a2bfe8a1, W), VAL (16_a81a664b, W),
    VAL (16_c24b8b70, W), VAL (16_c76c51a3, W), VAL (16_d192e819, W),
    VAL (16_d6990624, W), VAL (16_f40e3585, W), VAL (16_106aa070, W),
    VAL (16_19a4c116, W), VAL (16_1e376c08, W), VAL (16_2748774c, W),
    VAL (16_34b0bcb5, W), VAL (16_391c0cb3, W), VAL (16_4ed8aa4a, W),
    VAL (16_5b9cca4f, W), VAL (16_682e6ff3, W), VAL (16_748f82ee, W),
    VAL (16_78a5636f, W), VAL (16_84c87814, W), VAL (16_8cc70208, W),
    VAL (16_90befffa, W), VAL (16_a4506ceb, W), VAL (16_bef9a3f7, W),
    VAL (16_c67178f2, W) };

  (* The first 32 bits of the fractional parts of the square roots of
     the first 8 primes. *)
  H0 = State {
    VAL (16_6a09e667, W), VAL (16_bb67ae85, W), VAL (16_3c6ef372, W),
    VAL (16_a54ff53a, W), VAL (16_510e527f, W), VAL (16_9b05688c, W),
    VAL (16_1f83d9ab, W), VAL (16_5be0cd19, W) };

PROCEDURE Transform (VAR h: State;  READONLY blk: Block) =
  VAR
    m: ARRAY [0 .. 63] OF W;
    a, b, c, d, e, f, g, hh, t1, t2, s0, s1: W;
  BEGIN
    FOR i := 0 TO 15 DO
      m[i] := Or (Or (LeftShift (VAL (blk[4 * i], W), 24),
                      LeftShift (VAL (blk[4 * i + 1], W), 16)),
                  Or (LeftShift (VAL (blk[4 * i + 2], W), 8),
                      VAL (blk[4 * i + 3], W)));
    END;
    FOR i := 16 TO 63 DO
      s0 := Xor (Xor (RightRotate (m[i - 15], 7),
                      RightRotate (m[i - 15], 18)),
                 RightShift (m[i - 15], 3));
      s1 := Xor (Xor (RightRotate (m[i - 2], 17),
                      RightRotate (m[i - 2], 19)),
                 RightShift (m[i - 2], 10));
      m[i] := m[i - 16] + s0 + m[i - 7] + s1;
    END;

    a := h[0];  b := h[1];  c := h[2];  d := h[3];
    e := h[4];  f := h[5];  g := h[6];  hh := h[7];
    FOR i := 0 TO 63 DO
      s1 := Xor (Xor (RightRotate (e, 6), RightRotate (e, 11)),
                 RightRotate (e, 25));
      t1 := hh + s1 + Xor (And (e, f), And (Not (e), g)) + K[i] + m[i];
      s0 := Xor (Xor (RightRotate (a, 2), RightRotate (a, 13)),
                 RightRotate (a, 22));
      t2 := s0 + Xor (Xor (And (a, b), And (a, c)), And (b, c));
      hh := g;  g := f;  f := e;  e := d + t1;
      d := c;  c := b;  b := a;  a := t1 + t2;
    END;

    INC (h[0], a);  INC (h[1], b);  INC (h[2], c);  INC (h[3], d);
    INC (h[4], e);  INC (h[5], f);  INC (h[6], g);  INC (h[7], hh);
  END Transform;

PROCEDURE FromText (txt: TEXT): TEXT =
  VAR
    len  := Text.Length (txt);
    h    := H0;
    blk  : Block;
    n    := 0;                          (* bytes in blk *)
    bits := VAL (len, Word64.T) * VAL (8, Word64.T);
    res  := "";
  BEGIN
    FOR i := 0 TO len - 1 DO
      blk[n] := ORD (Text.GetChar (txt, i));  INC (n);
      IF n = 64 THEN Transform (h, blk);  n := 0 END;
    END;

    (* Pad with 16_80 and zeros, then the length in bits, big-endian,
       in the last 8 bytes; a second block if they don't fit. *)
    blk[n] := 16_80;  INC (n);
    IF n > 56 THEN
      WHILE n < 64 DO blk[n] := 0;  INC (n) END;
      Transform (h, blk);  n := 0;
    END;
    WHILE n < 56 DO blk[n] := 0;  INC (n) END;
    FOR j := 0 TO 7 DO
      blk[56 + j] := VAL (Word64.And (Word64.RightShift (bits, 56 - 8 * j),
                                      VAL (16_ff, Word64.T)), INTEGER);
    END;
    Transform (h, blk);

    FOR i := 0 TO 7 DO
      res := res & Fmt.Pad (Fmt.Unsigned (Word32.ToWord (h[i]), 16), 8, '0');
    END;
    RETURN res;
  END FromText;

BEGIN
END Sha256W32.
