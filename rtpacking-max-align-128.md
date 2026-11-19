# RTPacking.Encode overflows on a max_align of 128

## What happens

`RTPacking.Encode` packs `long_size`, `word_size`, `max_align` and
`struct_align` into two-bit fields that hold `BitSize` 0 .. 3, which means
8 .. 64 bits. Commit 2b3c5a6506 ("extend bits for packing sizes") added 128 to
`Bits` for the 128-bit EXTENDED. On AMD64_LINUX, `RTPacking.Local ().max_align`
is 128, and `BitSize (128)` is 4. That value doesn't fit in the field, and its
high bit is added to the word-size field. As a result:

- A max_align of 128 decodes as 8.
- A 32-bit word size, together with a max_align of 128, decodes as 64.

Pickle2 writes `Encode (Local ())` into every pickle header, and `ConvertPacking`
keys its cache of converters by `Encode`.

## Reproducer

```
MODULE Main;
IMPORT RTPacking, IO, Fmt;
PROCEDURE Show (word, maxa: INTEGER) =
  VAR t := RTPacking.Local ();  d: RTPacking.T;
  BEGIN
    t.word_size := word;  t.max_align := maxa;
    d := RTPacking.Decode (RTPacking.Encode (t));
    IO.Put ("word " & Fmt.Int (word) & ", max_align " & Fmt.Int (maxa)
            & " -> word " & Fmt.Int (d.word_size) & ", max_align "
            & Fmt.Int (d.max_align) & "\n");
  END Show;
BEGIN
  Show (32, 64); Show (32, 128); Show (64, 64); Show (64, 128);
END Main.
```

On master (AMD64_LINUX):

```
word 32, max_align 64 -> word 32, max_align 64
word 32, max_align 128 -> word 64, max_align 8
word 64, max_align 64 -> word 64, max_align 64
word 64, max_align 128 -> word 64, max_align 8
```

## What is not shown

On one host, a pickle of a record with CHAR, INTEGER, subrange and LONGINT fields
reads back correctly, whether it is read in the same process or in another one.
Writer and reader compute the same wrong code, so no conversion is attempted.
It also reads back correctly between master and a library whose `Encode` stores
128 correctly. A case where the wrong code makes a pickle unreadable has not
been found yet. Such a case would most likely involve two platforms whose
packings differ.

## Possible fix, for discussion

Changing `Encode` changes the pickle header, so it should be agreed on before
a PR. One compatible encoding:

- Write a size of 128 as 64 in its two-bit field, so an older `Decode` reads 64.
- Set a flag bit per size above the existing fields. The header has 32 bits for
  the code, and `Decode` already ignores bits it doesn't know.

Pickles written by the current master would still carry the wrong code.
