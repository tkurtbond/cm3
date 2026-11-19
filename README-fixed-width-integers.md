# Fixed-Width Integer Types (`Word8.T` .. `Word64.T`, `Signed8.T` .. `Signed64.T`)

This fork adds eight integer types of fixed size to Modula-3:

| Type | Values | Arithmetic |
|------|--------|------------|
| `Word8.T`, `Word16.T`, `Word32.T`, `Word64.T` | `0 .. 2^N - 1` | wraps around (modulo `2^N`) |
| `Signed8.T`, `Signed16.T`, `Signed32.T`, `Signed64.T` | `-2^(N-1) .. 2^(N-1) - 1` | checked: a result out of range is a run-time error |

They are for code whose sizes are fixed by something outside the
program: hashes and checksums, binary file formats and network
protocols, and C interfaces. `Word8.T` is 8 bits on every target, and
`Word32.T + Word32.T` wraps at `2^32` without any masking. The
ordinary operators work on them, comparisons and `DIV` on the `WordN`
types are unsigned, and each type stays separate from INTEGER, LONGINT
and the others. Mixing them is a compile-time error, not a silent
conversion.

This is a language extension. Programs that use these types build only
with this fork's compiler, not with upstream cm3. The design, the
decisions behind it and the record of the work are in
[`LLVM-IR-backend-docs/fixed-width-integer-types-plan.md`](LLVM-IR-backend-docs/fixed-width-integer-types-plan.md).

Every example below has been compiled and run, with this fork's compiler
on AMD64_LINUX.

---

## Using them

The types live in interfaces, as `Word.T` and `Long.T` do. There are no
new reserved words.

```modula-3
IMPORT Word8, Word32, Word64, Signed8;

TYPE Byte = Word8.T;
CONST One = VAL (1, Word32.T);
VAR
  a := VAL (200, Word8.T);
  b := VAL (100, Word8.T);
  x := VAL (16_ffffffff, Word32.T);
```

The compiler predefines the interfaces and compiles calls on their
procedures inline. `m3core` also has real units for them (in
`m3-libs/m3core/src/word/`), so the procedures can be used as procedure
values, and a `WordN.T` can instantiate generics that need `Brand`,
`Equal` and `Hash`. A `Table` keyed on `Word32.T` works:

```
table ("W32Int", "Word32", "Integer")       % in the m3makefile
```

## Constants

There are no literals of these types. Write a constant with `VAL`, or
with `Wrap` when the value should be reduced modulo `2^N`:

```modula-3
CONST One = VAL (1, Word32.T);
      Mask = VAL (16_ff, Word8.T);
      Max = LAST (Word32.T);           (* 2^32 - 1 *)

Word32.Wrap (-1)                       (* 4294967295 *)
Word8.Wrap (300)                       (* 44 *)
```

`VAL` is checked. `VAL (300, Word8.T)` is a run-time error,
"An enumeration or subrange value was out of range", not a compile-time
error (as with `VAL (300, [0..255])` today). `Wrap` never fails.

## Operators

Both operands must be of the same type. Any of these is a compile-time
error:

```modula-3
a := 5;                  (* Types are not assignable *)
x := x + 1;              (* illegal operand(s) for '+'; write x + One *)
y := x;                  (* Word32.T to Word64.T: not assignable *)
i := x;                  (* Word32.T to INTEGER: not assignable *)
b := a < 1;              (* illegal operand(s) for '<' *)
```

The same holds for `MIN`, `MAX`, `INC`, `DEC`, `FOR` bounds and
parameter passing.

**`WordN.T`** (unsigned, wrapping):

- `+`, `-`, `*` and unary `-` wrap modulo `2^N`.
  `VAL (200, Word8.T) + VAL (100, Word8.T)` is 44, `-VAL (100, Word8.T)`
  is 156, and `LAST (Word32.T) + One` is 0, so `x + One > x` is `FALSE`
  at `LAST`.
- `<`, `<=`, `>`, `>=`, `DIV` and `MOD` are unsigned, at every width,
  including values of `2^63` and above in a `Word64.T`.
- `ABS` is a compile-time error.
- Constant expressions fold to the same values as at run time.

**`SignedN.T`** (signed, checked):

- `+`, `-`, `*`, unary `-`, `DIV` and `ABS` raise the run-time error
  `IntegerOverflow` ("Integer result too large to represent") when the
  result doesn't fit. That covers `FIRST (T) DIV -1` and
  `ABS (FIRST (T))`. `MOD -1` gives 0. Like any run-time error, it can
  be caught as `RuntimeError.E`:

  ```modula-3
  VAR s := VAL (100, Signed8.T);
  TRY s := s + s
  EXCEPT RuntimeError.E (e) => IO.Put (RuntimeError.Tag (e))
  END;                     (* Integer result too large to represent. *)
  ```

- Comparisons, `DIV` and `MOD` are signed and round as for INTEGER.
- A constant expression that overflows isn't folded, as with INTEGER:
  in a `CONST` declaration it is the error "Value of CONST is not
  constant".

**`INC`, `DEC` and `FOR`** take a step of the variable's own type or an
INTEGER, so `INC (x)`, `INC (x, 2)` and `BY -1` need no `VAL`. The step
is applied exactly and then wrapped (`WordN`) or checked (`SignedN`). A
`FOR` loop up to `LAST (T)`, or down to `FIRST (T)`, ends; it doesn't
wrap around:

```modula-3
FOR j := FIRST (Byte) TO LAST (Byte) DO ... END;     (* 256 iterations *)
FOR j := VAL (3, Word8.T) TO VAL (0, Word8.T) BY -1 DO ... END;
```

## Ordinal uses

The types are ordinal, like LONGINT: `FIRST`, `LAST`, `NUMBER`, `ORD`,
`VAL`, subranges, `BITS FOR`, `CASE`, array index types and set base
types all accept them.

```modula-3
TYPE Small = [VAL (0, Word8.T) .. VAL (9, Word8.T)];
VAR hist: ARRAY Byte OF INTEGER;
    set: SET OF Small;

CASE a OF
| VAL (200, Word8.T) => ...
ELSE ...
END;
```

A subrange's base type is the fixed type, so values of `Small` mix with
`Word8.T`, not with INTEGER. `ARRAY Word64.T OF ...` and
`SET OF Word64.T` are rejected as too large, as `ARRAY LONGINT OF` is.

`ORD (x)` returns `x`'s own type, as `ORD` of a LONGINT returns LONGINT.
To get an INTEGER, use `VAL (x, INTEGER)` (checked) or `WordN.ToWord (x)`
(keeps the bits).

## Conversions

| From | To | How | Out of range |
|------|----|-----|--------------|
| any integer type | any integer type | `VAL (x, T)` | run-time error |
| INTEGER, LONGINT or any fixed type | `WordN.T`, `SignedN.T` | `WordN.Wrap (x)`, `SignedN.Wrap (x)` | keeps the low N bits |
| `Word.T` | `WordN.T` | `WordN.FromWord (w)` | keeps the low N bits |
| `Long.T` | `WordN.T` | `WordN.FromLong (l)` | keeps the low N bits |
| `WordN.T` | `Word.T`, `Long.T` | `WordN.ToWord (x)`, `WordN.ToLong (x)` | zero-extends, or keeps the bits when N is the full width |

`Signed32.Wrap (w)` reinterprets the bits of a `Word32.T`:
`Signed32.Wrap (LAST (Word32.T))` is -1. `Word64.ToLong` of a value of
`2^63` or more is negative, which is the usual way to pass a `Word64.T`
to code that takes a LONGINT bit pattern, such as `Fmt.LongUnsigned`.

Printing: `Fmt` has no procedures for these types. Convert first:

```modula-3
Fmt.Int (VAL (b, INTEGER))
Fmt.Unsigned (Word32.ToWord (x))               (* hexadecimal by default *)
Fmt.LongUnsigned (Word64.ToLong (y))
```

## `Word.T` is not `WordN.T`

`Word.T` is a name for INTEGER. The `Word` procedures are unsigned
operations on INTEGERs, but the operators on a `Word.T` are INTEGER's,
and so signed. A `WordN.T` is a separate unsigned type, so its operators
are unsigned:

```modula-3
VAR w: Word.T := -1;                         (* all bits set *)

w < 1                                        (* TRUE: signed *)
Word.LT (w, 1)                               (* FALSE: unsigned *)
Word64.FromWord (w) < VAL (1, Word64.T)      (* FALSE: unsigned *)
```

So that this never changes meaning silently, `Word.T` and `WordN.T` are
not assignable to each other; converting takes `FromWord` or `ToWord`.
Each `WordN` interface has the same procedures as `Word`, so code
written as `Word.LT (a, b)` keeps its meaning when `a` and `b` become
`Word32.T`s and `Word.LT` becomes `Word32.LT`.

`cm3 -w0` points out the signed operators on `Word.T` and `Long.T`. It
reports `<`, `<=`, `>`, `>=`, `DIV` and `MOD` with an operand declared
as `Word.T` or `Long.T`, as in

```
"../src/Main.m3", line 8: info: '<' on Word.T is signed; Word.LT is unsigned
```

Signed use is legal, so this is an informational message, and only
`-w0` shows it (the default is `-w1`). The operand can be a variable,
a parameter, a record or object field, an array element, a REF's
referent, a procedure or method result, or a `WITH` name bound to any
of these, and its type can be `Word.T`, a name for it
(`TYPE Hash = Word.T`) or `BITS n FOR Word.T`.

## The interfaces

`Word8` .. `Word64` (`m3-libs/m3core/src/word/GenWordN.ig`):

- `T`, `Size`
- `Word`'s procedures, at width N: `Plus`, `Times`, `Minus`, `Divide`,
  `Mod`, `LT`, `LE`, `GT`, `GE`, `And`, `Or`, `Xor`, `Not`, `Shift`,
  `Rotate`, `Extract`, `Insert`
- `LeftShift`, `RightShift`, `LeftRotate` and `RightRotate`, whose
  count is a `[0 .. Size-1]`
- `Wrap`, `FromWord`, `ToWord`, `FromLong`, `ToLong`
- `Brand`, `Equal`, `Hash`, `Compare`

`Signed8` .. `Signed64` (`GenSignedN.ig`): `T`, `Size`, `Wrap`, `Brand`,
`Equal`, `Hash` and `Compare`. The operators do the arithmetic.

## Libraries and tools

- **Pickles** read and write records with fields of these types, and
  convert them between byte orders and word sizes (test `p306`).
- **Network objects**: `stubgen` accepts the types, and subranges of
  them, as arguments, results, `VAR` parameters and record fields. They
  go over the wire as LONGINTs, and the receiver checks the range.
  Tests: `m3-comm/netobj/tests/fixedwidth`, run with
  `m3-comm/netobj/tests/run-netobj-tests.sh WORKDIR`.
- **`m3tk`**, the front end of `stubgen` and other tools, knows the
  types. It rejects mixed operands such as `Word32.T + Word64.T`, and
  folds constant expressions as the compiler does: `WordN` results
  wrap, and a `SignedN` result out of range is an error. Its limits,
  tested with `stubgen`:
  - Its values are LONGINTs, so it takes `LAST (Word64.T)` to be
    `LAST (LONGINT)`. A network-object argument of type
    `[VAL (0, Word64.T) .. LAST (Word64.T)]` gets the bounds
    `0 .. 2^63 - 1` in the stubs, so values of `2^63` and above are
    rejected (`Word64.T` itself has no such limit). A constant
    `Word64.T` expression whose value is outside `0 .. 2^63 - 1` is
    the error "expression cannot be evaluated".
  - It doesn't fold calls on the `WordN` procedures (nor on `Long`'s),
    so `Word32.And (...)` in a subrange bound is "expression is not
    constant". Use the operators, or a literal.
- **Shared objects**: `sharedobjgen` accepts the types, and subranges
  of them, as arguments of update methods and as fields of a shared
  object, marshaled as LONGINTs as `stubgen` does. Test:
  `m3-comm/sharedobj/tests/fixedwidth`, run with
  `m3-comm/netobj/tests/run-netobj-tests.sh WORKDIR
  sharedobj/tests/fixedwidth` (with no test named, the script runs it
  along with the network-object tests).

## Notes

- Division by zero on a `WordN.T` gives 0 with the C back end and
  SIGFPE with `LlvmIR`. This isn't new: `Word.Divide (1, 0)` upstream
  behaves the same way.
- Building `m3core` with a compiler older than these types (a bootstrap
  compiler, say) leaves the `WordN` and `SignedN` units out. The
  compiler defines the quake variables `M3_FIXED_WIDTH_INTEGERS` and
  `M3_FIXED_WIDTH_SIGNED`, and `m3core` builds the units only when they
  are defined. `scripts/concierge.py upgrade` builds `m3core` again with
  the new compiler, which puts them in.
- The compiler's tests for the types: `p298` to `p306`, `e042`, `e043`
  and `r006` to `r012` in `m3-sys/m3tests`.
