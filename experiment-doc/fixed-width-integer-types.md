# Fixed-Width Integer Types for Modula-3: A Sketch

Nov 16, 2026 · T. Kurt Bond; Drafted with assistance from Claude (Anthropic).

## Goals and principles

The goal is fixed-width integer types with defined overflow, added through the built-in operator table alone, so hashing and binary-format code stops calling `Word.Plus` and masking by hand.

Today's behavior, from tests on cm3 d5.11.4 (AMD64\_LINUX):

- `Word.T` is declared as `INTEGER`, so unsigned is not a distinct type and `<` cannot pick an unsigned compare.
- `LAST(INTEGER) + 1` wraps, but the C backend compiles signed `+` as C signed arithmetic. GCC folded `x + 1 > x` to TRUE at the maximum value, even at `-O0`.
- `INTEGER + LONGINT` and `REAL + LONGREAL` are rejected as illegal operands.
- Storing an out-of-range value into a `BITS 32 FOR` subrange is a checked runtime error, not a wrap.

Principles for the extension:

1. **No user-defined overloading.** Only the language's own operator table grows, the same way LONGINT was added.
2. **No implicit conversions.** Mixed-type arithmetic stays illegal, matching today's rule.
3. **Overflow policy is part of the type**, never an optimizer's choice.
4. **Existing programs keep their meaning.** `INTEGER`, `LONGINT`, `Word` and `Long` stay as they are, apart from the one decision flagged in the open questions.

## The new types

Two predeclared families cover most needs: wrapping unsigned types `WORD8` to `WORD64`, and checked signed types `INT8` to `INT64`. These names are proposals, not settled syntax.

| Type | Bits | Range | Overflow in `+ - *` |
| --- | --- | --- | --- |
| `WORD8` | 8 | 0 .. 255 | wraps modulo 2^8 |
| `WORD16` | 16 | 0 .. 65,535 | wraps modulo 2^16 |
| `WORD32` | 32 | 0 .. 4,294,967,295 | wraps modulo 2^32 |
| `WORD64` | 64 | 0 .. 2^64 - 1 | wraps modulo 2^64 |
| `INT8` | 8 | -128 .. 127 | checked runtime error |
| `INT16` | 16 | -32,768 .. 32,767 | checked runtime error |
| `INT32` | 32 | -2^31 .. 2^31 - 1 | checked runtime error |
| `INT64` | 64 | -2^63 .. 2^63 - 1 | checked runtime error |

Relationship to existing types:

- `INTEGER` and `LONGINT` are unchanged in size: 64 bits for both on AMD64\_LINUX. Their overflow rule is the open decision in the last section.
- `Word.T` stays `INTEGER` and `Long.T` stays `LONGINT`, so existing code compiles as before.
- Each new type is a distinct type. No two of them are assignable to each other or to `INTEGER` without a conversion.
- Subranges of the new types are allowed and keep today's rule: an out-of-range assignment is a checked runtime error.

A matching signed-wrapping or unsigned-checked family is possible, but I would add them only if real code needs them.

## Literals

A literal takes its type from a suffix, extending the existing `L` suffix for LONGINT, because that needs no change to how the compiler types expressions.

| Literal | Type |
| --- | --- |
| `255` | `INTEGER` (unchanged) |
| `255L` | `LONGINT` (unchanged, from the CM3 language definition) |
| `255W8`, `16_FFFFW32` | `WORD8`, `WORD32` |
| `-5I32` | `INT32` |

Rules:

- A literal outside its type's range is a static error, never a silent wrap.
- Constant expressions of a new type fold at compile time using that type's rules. Folding `255W8 + 1W8` gives `0W8`; folding `127I8 + 1I8` is a static error.
- The alternative, contextual typing of untyped constants as in Go or Ada, is nicer to write but changes how every expression is typed, so I would not start there.

## Operators

The built-in operators `+ - * DIV MOD < <= > >=` accept both operands of the same new type and return that type, with the rules below. This extends the existing built-in overloading of `+` across integers, floats and sets, and adds no new mechanism.

| Operation | `WORDn` (wrapping, unsigned) | `INTn` (checked, signed) |
| --- | --- | --- |
| `a + b`, `a - b`, `a * b` | result modulo 2^n | checked runtime error if the result is out of range |
| `-a` | `0 - a` modulo 2^n | checked error if `a` is `FIRST(INTn)` |
| `a DIV b`, `a MOD b` | unsigned division | floor semantics as for `INTEGER`; checked error for division by zero or `FIRST DIV -1` |
| `<`, `<=`, `>`, `>=` | unsigned compare | signed compare |
| `=`, `#` | bit equality | value equality |

Bit operations for `WORDn` reuse the existing generic interface. In the sources, `Word` is `GenWord(WordRep)` and `Long` is `GenWord(LongRep)`, so `Word8`, `Word16`, `Word32` and `Word64` interfaces are one-line instantiations offering `And`, `Or`, `Xor`, `Not`, `LeftShift`, `RightShift`, `Rotate`, `Extract` and `Insert` at the right width.

Mixed operands, for example `WORD32 + INTEGER`, remain illegal, as `INTEGER + LONGINT` is today.

## Conversions

All conversions are explicit, and the program chooses between a checked conversion and a wrapping one. The checked form reuses the existing `VAL`, which already works for `VAL(i, LONGINT)` in cm3 d5.11.4.

- **`VAL (x, T)`** converts any integer-typed `x` to `T` and is a checked runtime error if the value does not fit. Widening within a signedness never fails.
- **`WRAP (x, T)`** (a proposed new built-in) converts any integer-typed `x` to `WORDn` modulo 2^n, or to `INTn` in two's complement, and never fails. It replaces today's `Word.Extract (x, 0, 32)` and `Word.And (x, 16_FF)` idioms.
- `ORD` of a new-type value returns `INTEGER`, a checked error if it does not fit. A `WORD64` above `LAST(INTEGER)` needs `WRAP` to reach a signed type.
- Conversions between `INTEGER`, `LONGINT` and the new types go through `VAL` or `WRAP`, never through assignment.

The cost model is plain: `VAL` into a smaller or differently signed type emits a range check, and `WRAP` emits a mask or sign-extension only.

## Compatibility

No existing program changes meaning, and the library gains types without losing any.

- **`Word`, `Long`:** unchanged. They remain `GenWord` instances over `INTEGER` and `LONGINT`.
- **`Int32`, `Int64`:** these library interfaces are `BITS n FOR` subrange types and stay. The new `INT32` and `INT64` are separate predeclared types, so a program can use either.
- **Packing:** `BITS 32 FOR WORD32` and `BITS 8 FOR WORD8` fit exactly. That makes binary-format records, the use case `BinIO` handles with hand-declared subranges, one type each.
- **`Cstdint`:** its `uint32_t` is today an alias of the C `unsigned` type. Re-aliasing it to `WORD32` is the natural follow-up, but it changes type identity for existing C-binding code, so it should be optional and late.
- **Existing hand-masked code:** `SHA256` in `libm3` masks with `Mask32 = 16_FFFFFFFF` after each `Plus`. It keeps working, and becomes the first candidate for a rewrite on `WORD32`.
- **Pickles and network objects:** both need type codes and packing rules for the new types. I have not read that code beyond seeing sized-word names in `ConvertPacking`, so I treat its effort as unknown.

## Backend implications

Wrapping types need no new intermediate operation, because the front end already emits a plain `add` tagged with an unsigned type for `Word.Plus`. Checked types need either a range-check sequence or an overflow-aware operation.

| Operation | C backend | LLVM emission |
| --- | --- | --- |
| `WORDn` `+ - *` | unsigned C arithmetic, wrap is defined | plain `add`, `sub`, `mul` with no flags |
| `INTn` `+ - *` (checked) | widen, operate, range-check, or `__builtin_*_overflow` | `llvm.sadd.with.overflow` and friends, branch to the runtime-error path |
| `INTEGER`, `LONGINT` if made wrapping | cast through unsigned, or compile with `-fwrapv` | plain `add`, no `nsw` |
| `WRAP (x, T)` | mask or sign-extend | `trunc`, `zext` or `sext`, or an `and` mask |
| `VAL (x, T)` narrowing | range check, then convert | compare and branch, then `trunc` |

Three notes from reading the sources:

- The existing LLVM translator builds word-type `add`, `sub` and `mul` with the `NUW` (no unsigned wrap) flag, and signed ones with `NSW`. That contradicts `Word.Plus` being modular, and it must change before wrapping types are correct. I read this code but did not run it.
- The IR already has `check_range` (the LLVM translator implements it), so checked narrowing can reuse it.
- In the sources I read, the IR's integer operator types (`IType`) start at 32 bits. If that holds, 8- and 16-bit arithmetic would be done at 32 bits, then masked or sign-extended on store.

## Open questions and tests

The biggest decision is what plain `INTEGER` and `LONGINT` overflow should mean, because both choices break something.

- **Overflow of `INTEGER` and `LONGINT`.** Make it wrapping (defined, matches what the code does in practice, removes undefined behavior, but hides bugs) or checked (matches Modula-3's safety goals, but breaks code that relies on wrap, such as hashes written with plain `+`). My lean is wrapping now, with checked types available through `INTn`.
- **Names and suffixes.** `WORDn`, `INTn` and `W8`, `I32` are placeholders; the choice must not collide with existing identifiers.
- **Signed-wrapping and unsigned-checked families.** Skip until real code asks for them.
- **8- and 16-bit arithmetic in the IR.** Widen to 32 bits in the front end, or add 8- and 16-bit operator types to the IR.
- **Aliasing `Word.T` to `WORD64`.** Cleaner long term, but it changes `Word`'s type on 32-bit targets, where it is 32 bits.

A minimal test plan, each run on both the C and LLVM backends:

1. `Word.Plus (LAST (INTEGER), 1)` and `LAST (WORD64) + 1W64` compile to IR with no `nuw` or `nsw` flag and wrap to zero or the minimum.
2. `x + 1 > x` evaluated at the maximum of a wrapping type is FALSE at every optimization level.
3. `INT32` overflow, narrowing `VAL` and out-of-range literals raise the checked runtime error or the static error as specified.
4. `WRAP` round-trips: `WRAP (WRAP (x, WORD8), WORD64)` equals `x MOD 256` for sample values across the range.
5. `SHA256` rewritten on `WORD32` reproduces the digests of the existing masked version on the standard test vectors.
