(* This fork: SHA256 on Word32.T (Sha256W32) against libm3's SHA256 and
   the published digests.  See the readme. *)

MODULE Main;

IMPORT IO, SHA256, Sha256W32, Text;

PROCEDURE Repeat (s: TEXT;  n: CARDINAL): TEXT =
  VAR a := NEW (REF ARRAY OF CHAR, n * Text.Length (s));
  BEGIN
    FOR i := 0 TO LAST (a^) DO a[i] := Text.GetChar (s, i MOD Text.Length (s)) END;
    RETURN Text.FromChars (a^);
  END Repeat;

PROCEDURE Bytes (): TEXT =
  VAR a: ARRAY [0 .. 255] OF CHAR;
  BEGIN
    FOR i := 0 TO 255 DO a[i] := VAL (i, CHAR) END;
    RETURN Text.FromChars (a);
  END Bytes;

PROCEDURE Check (name, txt, expected: TEXT) =
  VAR w32 := Sha256W32.FromText (txt);  lib := SHA256.FromText (txt);
  BEGIN
    IO.Put (name & ": " & w32 & "\n");
    IF NOT Text.Equal (w32, expected) THEN
      IO.Put ("  WRONG, expected " & expected & "\n");
    END;
    IF NOT Text.Equal (w32, lib) THEN
      IO.Put ("  differs from libm3's SHA256: " & lib & "\n");
    END;
  END Check;

BEGIN
  Check ("\"\"", "",
         "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
  Check ("\"abc\"", "abc",
         "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  Check ("448 bits",
         "abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
         "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1");
  Check ("896 bits",
         "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmn"
         & "hijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1");
  Check ("a x 1000000", Repeat ("a", 1000000),
         "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0");
  (* The lengths around where the padding needs a second block. *)
  Check ("a x 55", Repeat ("a", 55),
         "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318");
  Check ("a x 56", Repeat ("a", 56),
         "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a");
  Check ("a x 63", Repeat ("a", 63),
         "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34");
  Check ("a x 64", Repeat ("a", 64),
         "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb");
  Check ("bytes 0..255", Bytes (),
         "40aff2e9d2d8922e47afd4648e6967497158785fbd1da870e7110266bf944880");
END Main.
