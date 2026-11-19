# Fixed-Width Integer Types: Assessment and Plan

Nov 18, 2026 · Temporary working notes on
[`fixed-width-integer-types.md`](fixed-width-integer-types.md) (the
"sketch"). Drafted with assistance from Claude (Anthropic).

## Summary

- **Does it make sense?** Yes, with two changes. The wrapping unsigned
  family solves a real, recurring problem (hashes, checksums, binary
  formats, C interop). The checked signed family is useful but less
  urgent. The sketch's principles (no user overloading, no implicit
  conversions, overflow policy in the type) fit Modula-3, and LONGINT
  is the precedent for every step.
- **Change 1: no new reserved words.** Predeclared identifiers are
  reserved in Modula-3. `INT8` to `INT64` are already declared in
  `m3core` (`win32/WinBaseTypes.i3:24-27`, `win32/WinDef.i3:27-30`)
  and in packages built on every platform, including the compiler
  itself (see correction 1). Making them predeclared breaks all of
  these. Put the types in builtin interfaces instead, as `Word` and
  `Long` already are: `Word8.T` to `Word64.T` (unsigned, wrapping) and
  `Signed8.T` to `Signed64.T` (signed, checked). The ordinary operators
  `+ - * DIV MOD < <= > >=` apply to them; where a type's name is
  declared doesn't affect which operators it accepts. 128-bit types
  are out of scope.
- **Change 2: lower everything in the front end, using M3CG operations
  that already exist.** Then no back end needs a new operation, and the
  work is mostly in `m3front`.
- **How hard?** Medium-large, mostly front end. LONGINT touches 71
  places in 33 `m3front` files, and the new types touch about the same
  places plus constant folding. A rough guess: 3 to 6 person-weeks for
  the unsigned family, 2 to 3 more for the checked family, and an
  unknown amount for pickles, network objects and the `m3tk`-based
  tools.
- **Would it break existing programs?** Not with the changes above,
  apart from three narrow risks listed under "Compatibility". One part
  can be done right away and fixes a real bug: the C back end compiles
  `INTEGER` `+` as C signed `+`, which is undefined behavior on
  overflow (Phase 0).

## Corrections to the sketch

Checked against the sources on branch `dev` (commit 992071694).

1. **Names.** A predeclared name is reserved (`Tipe.Define (name,
   type, TRUE)` calls `Scanner.NoteReserved`), and `INTn` is already
   declared in several places:

   | Where | Declaration | Built on |
   | --- | --- | --- |
   | `m3-libs/m3core/src/win32/WinBaseTypes.i3:24-27`, `WinDef.i3:27-30` | `INT8` .. `INT64` = `Cstdint` types | Windows |
   | `m3-sys/m3back/src/M3CC.i3:4` | `INT32 = Ctypes.int` | all platforms |
   | `m3-sys/m3objfile/src/Coff.i3:14-15` | `INT16`, `INT32` as `BITS n FOR` subranges | all platforms (compiler) |
   | `m3-ui/ui`, `m3-ui/PEX` | `INTn` uses | varies |
   | `m3-sys/llvm/llvm13`, `llvm18` | `INTn` uses | old copies |

   The names appear in 32 files in all (about 1,600 uses). Each of these
   declarations is an INTEGER subrange used with plain INTEGER
   arithmetic and literals. For example, `WinDef.MAKELONG` returns
   `Word.Or (...)` as an `INT32`, and `WinError.i3` has
   `CONST NO_ERROR: INT32 = 0`. So converting them to the new,
   distinct types is no fix either: it would need a `VAL` at each
   mixed use, here and in every Win32 caller outside the tree. It
   would also be a large Windows-only edit to upstream files that
   can't be tested here.

   A predeclared `WRAP` adds one more reserved word. The builtin-interface route (`Module.NewDefn`, as in
   `builtinWord/Module.mg`) adds none. Interface names must still be
   free, and several obvious ones are taken:

   | Names | Status |
   | --- | --- |
   | `Int32`, `Int64` | `m3core/src/types/`: INTEGER subranges with `Brand`, `Equal`, `Hash`, `Compare`, used to instantiate generics |
   | `Integer8` .. `Integer32`, `Cardinal8` .. `Cardinal32` | `m3-libs/arithmetic/src/basictypes/integer/` |
   | `Word8` .. `Word64` | free |
   | `Signed8` .. `Signed64` | free |
   | `Card8` .. `Card64` | free as interfaces (`Card32` is a local type name in a few modules, which doesn't clash) |

   Decision: `WordN` for the unsigned wrapping family, because in
   Modula-3 "Word" already means unsigned arithmetic modulo 2^n (see
   `GenWord.ig`). `SignedN` for the signed checked family. "Card"
   suggests CARDINAL, a checked subrange, which is the opposite
   overflow rule, so `CardN` is kept for a possible unsigned checked
   family. Interface names are CamelCase; all-caps names look
   predeclared.
2. **The `nuw`/`nsw` note is about the old back end.** `NUW` and `NSW`
   appear in `m3-sys/llvm/llvm22/src/M3CG_LLVM.m3:3400-3415` (upstream's
   LLVM-library back end). This fork's `m3llvmir` emits plain `add`,
   `sub` and `mul` with no flags (`M3LLVMIR.m3:1908-1915`), so it is
   already wrapping. The real hazard on AMD64_LINUX is the C back end:
   `M3C.m3` `op2` (line 6930) emits a C `+` on the signed type, and the
   config passes no `-fwrapv` (`SYSTEM_CC = "gcc -g -m64 -fPIC"`).
3. **`Word` and `Long` are front-end builtins**, not only `GenWord`
   instances. `m3front/src/builtinWord/` generates them
   (`word("Int", "Word")`, `word("LInt", "Long")` in its `m3makefile`),
   and the front end inlines their operations. A `Word32` interface
   needs a front-end instantiation plus a matching `m3core` interface.
   The selector table already has room: `TargetMap.Word_types` is
   `ARRAY [0..3]` (8, 16, 32, 64 bits).
4. **Type descriptions.** `TipeDesc.Op` (`m3front/src/misc/TipeDesc.i3`)
   encodes back-references as `Old0 + n`, so a new opcode shifts
   `Old0`. The comment there says this needs a coordinated change with
   `RTTipe` and invalidates compiled code. That is why WIDECHAR is
   described as an `Enum`. Phase 1 decides to describe the new types
   with the existing `Subrange` opcode instead.
5. **Literal suffixes are optional.** `VAL` and `Wrap` both fold at
   compile time, so every constant of the new types can be written
   with today's literals, without touching the scanner:

   ```modula3
   CONST
     K: Word32.T = VAL (16_428A2F98, Word32.T);
     Max: Word64.T = Word64.Wrap (16_FFFFFFFFFFFFFFFFL);   (* 2^64 - 1 *)
     FnvOffset: Word64.T = Word64.Wrap (16_CBF29CE484222325L);
     FnvPrime: Word64.T = VAL (16_100000001B3L, Word64.T);
   ```

   - **`VAL` checks the value; `Wrap` keeps the bits.** Use `VAL` for
     a number and `Wrap` for a bit pattern. `VAL
     (16_FFFFFFFFFFFFFFFFL, Word64.T)` fails, because the literal's
     value is -1. It fails at run time, not at compile time: see
     Phase 1, decision 7.
   - **`Word64.T` values of 2^63 and above** are written as a based
     LONGINT literal passed to `Wrap`. The scanner
     (`misc/Scanner.m3`, around line 546) accepts a based literal with
     an `L` suffix up to `Long.max` (2^64 - 1) as an unsigned bit
     pattern and sign-extends it, so `16_FFFFFFFFFFFFFFFFL` is -1L and
     `Wrap` turns it back into 2^64 - 1.
   - **Use the `L` suffix for portability.** Without it, a based
     literal is INTEGER and must fit `Word.max`, so
     `16_CBF29CE484222325` works on 64-bit targets and is an error on
     32-bit ones.
   - **Decimal stops at `LAST (LONGINT)`.** A decimal value above
     2^63 - 1 can't be written; write it in hex. Such constants are
     almost always masks or hash parameters, which are written in hex
     anyway.
   - `FIRST (Word64.T)` and `LAST (Word64.T)` work as for any ordinal
     type.

   Suffixes such as `16_FFFFFFFFFFFFFFFFW64` remain a possible later
   convenience. With suffixes, `-128I8` would be a static error (the
   literal `128I8` is out of range before negation), as decimal
   `FIRST(INTEGER)` is today.
6. **Checked overflow needs no new IR operation.** The front end can
   emit the wrapped operation in the unsigned M3CG type and test the
   sign bits (for `+`: overflow if `(a XOR r) AND (b XOR r)` is
   negative). For 8, 16 and 32 bits it can widen and use the existing
   `check_range`. Using the unsigned M3CG type also avoids C undefined
   behavior.
7. **Error code.** Reuse `RuntimeError.ValueOutOfRange`. Adding a code
   would mean appending to the `RuntimeError` enum and the runtime's
   tables.

## Compatibility

With builtin-interface names and front-end lowering:

- **Source:** existing programs compile unchanged. A user interface
  named `Word8` to `Word64` or `Signed8` to `Signed64` would clash with
  the builtin one. This is the same risk `Word` and `Long`
  carry, and it is checkable with a search before release.
- **Binary:** no new `TipeDesc` opcodes (Phase 1, decision 4), so
  type descriptions keep their format. Old pickles contain no new
  types and still read.
- **Tools:** `m3tk` (used by `stubgen` for network objects and by
  `m3browser`) has its own parser and type checker. Until it learns
  the new types it will reject or mistype only programs that use them.
- **`INTEGER` overflow:** defining it as wrapping only removes
  undefined behavior. It can cost a little C optimization (loop
  induction), which needs measuring. Making it checked would break
  hashes written with plain `+`, so it is not part of this plan.

## `Word.T` versus `WordN.T`

`Word.T` is INTEGER and `Long.T` is LONGINT, so their operators are the
signed ones: `a < b` on two `Word.T` values is a signed compare, and
only `Word.LT` compares them as unsigned. On `Word64.T`, `<` is
unsigned. The same source text means different things depending on
which type the operands have.

Making `Word.T` an alias of `Word64.T` (or `Word32.T` on 32-bit
targets) would remove the difference, but it is rejected:

- Existing code assigns `Word.T` to and from INTEGER, does arithmetic
  on it, and indexes arrays with it. All of that would need
  conversions, in the tree and in users' code.
- `Word.T` would be a different type on 32-bit and 64-bit targets,
  so code that compiles on one could fail to compile on the other.

So the plan keeps `Word.T` and `Long.T` as they are and handles the
difference this way:

1. **One rule, documented.** Operators follow the operand's type.
   `Word.T` is a name for INTEGER, and the `Word` procedures are
   unsigned operations on INTEGER. `WordN.T` is its own unsigned type.
   The `Word` interface documentation and the language additions both
   say this, with the `<` example.
2. **Mixing is a compile error, never a silent change.** `Word.T` and
   `Word64.T` are not assignable to each other, and `Word64.T + Word.T`
   is illegal. A program can't move a value from one to the other
   without writing a conversion.
3. **Safe, bit-preserving conversions.** `LOOPHOLE` needs an UNSAFE
   module, so each `WordN` interface provides `FromWord (w: Word.T): T`
   (keep the low N bits) and `ToWord (x: T): Word.T` (zero-extend; on
   a target where `Word.Size` < N, keep the low `Word.Size` bits).
   `FromLong` and `ToLong` do the same for `Long.T`.
4. **Same procedures on both.** Each `WordN` interface offers the
   `Word` procedures (`Plus`, `LT`, `Extract`, and the rest), so code
   written with `Word.LT (a, b)` keeps its meaning when the variables
   change to `Word32.T`, and code can be converted gradually.
5. **Optional warning (later).** The front end could warn when
   `< <= > >= DIV MOD` is applied to operands declared as `Word.T` or
   `Long.T`, which probably means the author wanted the unsigned
   operation. This depends on the declared name surviving until the
   operator is checked (`Word.T` is a `NamedType` of INTEGER), which
   needs checking. It must stay optional, because signed use of
   `Word.T` is legal.

## Plan

Each phase is reviewable and useful on its own. Phase 0 fits this
fork's back-end goal. Phases 1 onward are a language change in
`m3front`. `AGENTS.md` says to leave `m3front` alone for back-end work,
so they need an explicit decision, and ideally an upstream discussion
(modula3/cm3), before any code is written.

### Phase 0: Define `INTEGER` and `LONGINT` overflow as wrapping in the C back end

- In `M3C.m3`, emit signed `add`, `subtract`, `multiply` and `negate`
  through the unsigned C type and cast back. Alternatively, add
  `-fwrapv` to `SYSTEM_CC` in `cminstall/src/config/AMD64_LINUX` (and
  the other C-backend configs). The `M3C.m3` change holds even when a
  user overrides the C flags.
- Test: `x + 1 > x` at `LAST(INTEGER)` is FALSE with the C and `LlvmIR`
  back ends, at `-O0` and `-O`. Add a FileCheck to
  `m3llvmir/tests/Ops.check` that `add`, `sub` and `mul` carry no
  `nsw` or `nuw`.
- Check that the m3tests baseline is unchanged, and compare build time
  and the speed of a few benchmarks at `-O`.
- Effort: a day or two.

Status (2026-11-18): done.

- `M3C.m3`: `op2` and `op1` cast signed operands to the unsigned type
  (`typeToUnsigned`) before `+ - *`, unary `-` (and `~ & |`, harmless),
  and cast the result back. ABS of a signed integer uses a new helper,
  `m3_iabs_T`, which negates through the unsigned type; REAL types keep
  `m3_abs_T`.
- New test `m3tests` p296 (wrapping of `+ - *`, unary `-`, ABS and INC
  at the limits). With the C back end the old compiler fails it at `-O0`
  and `-O` (`x + 1 > x` was TRUE; `-FIRST(INTEGER) < 0` was FALSE); the
  new one passes.
- `m3llvmir/tests`: mixlib's `Ops` has `AddGt`, `LongAddGt`, `SubLt`,
  `MulGt`, `NegLt` and `AbsLt`, which mixprog runs in every C/`LlvmIR`
  combination, and `Ops.check` checks that their `add`, `sub` and `mul`
  carry no flags. `run-tests.sh` passes with and without `-O`.
- m3tests with the C back end, old compiler against new, at `-O0` and
  with `-DM3TESTS_OPTIMIZE`: the same 22 failures apart from p296, which
  only the old compiler fails. With `LlvmIR` only p047 fails.
- m3tests used to pass only `LlvmIR` down to each test's `cm3`, so
  `cm3 -DHTML -DM3_BACKEND_MODE=C` built the tests with the installed
  default; it now passes any mode (2a7330d19).
- Cost, measured with two drivers that differ only in `M3C.m3`
  (scripts and raw numbers in [`fwint-phase0/`](fwint-phase0/)). Same
  machine as [Phase 4](phase4-results.md); C mode; the generated C
  compiled at `gcc -O0` (what cm3 does, even with `cm3 -O`) and at
  `gcc -O2` (through Phase 4's wrapper).
  - Building the 15 compiler packages (`m3core` to `cm3`), minimum of
    3 runs: the generated C grows 0.2% (311.6 to 312.3 MB) and object
    text 0.1% at `-O0`, 0.2% at `-O2`. CPU time grows 0.7% at `-O0`
    (76.7 to 77.2 s) and 0.4% at `-O2` (156.6 to 157.2 s), about the
    run-to-run spread.
  - Runtime, minimum of 3 runs pinned to one P-core; `m3core` and
    `libm3` are the installed ones in every column, so only the
    program's own code differs. Outputs are identical.

    | Program | old `-O0` | new `-O0` | old `-O2` | new `-O2` |
    |---------|------:|------:|------:|------:|
    | Sieve | 2.90 s | 2.90 s | 0.77 s | 0.77 s |
    | NBody | 3.29 s | 3.28 s | 0.72 s | 0.73 s |
    | Trees | 4.15 s | 4.17 s | 3.78 s | 3.71 s |
    | QSort | 3.34 s | 3.32 s | 1.70 s | 1.84 s |
    | Hash | 9.68 s | 9.58 s | 2.14 s | 2.16 s |

  - At `gcc -O0` there is no difference. At `-O2` only QSort moves:
    8% slower (1.70 against 1.84 s, steady over 7 more runs each).
    Undoing single casts in its generated C shows the cost is entirely
    the wrapped `INC (i)` and `DEC (j)` in
    `WHILE a[i] < p DO INC (i) END` and its mirror; with those two
    reverted it runs in 1.69 s. The only difference between the two
    forms is that signed overflow is undefined in C, so the old code's
    speed came from GCC being allowed to assume `i + 1` never
    overflows: the same license that folded `x + 1 > x` to TRUE. Here
    `i` and `j` are kept in range by the array bounds, but GCC can't
    see that in the generated C. Getting the speed back safely would
    take facts the front end has (such as a checked range), not
    undefined behavior. Hash, which overflows on purpose, is
    unaffected.

### Phase 1: Decisions (written down before coding)

1. Names (decided). Builtin interfaces `Word8`, `Word16`, `Word32` and
   `Word64`, and `Signed8`, `Signed16`, `Signed32` and `Signed64`. Each
   exports `T`; `Brand`, `Equal`, `Hash` and `Compare`, so `T` can
   instantiate generics such as `Table`; `Wrap`; and, for `WordN`, the
   `Word` operations at that width plus `FromWord`, `ToWord`,
   `FromLong` and `ToLong`. No 128-bit types.
Status (2026-11-18): decisions 2, 3 and 5 to 8 are written down below
as proposed defaults, checked against the front end and the installed
compiler; they stand unless the maintainer changes them. Decision 6
is deliberately left open until Phase 4.

2. Ordinal rules (decided): follow LONGINT, which is allowed wherever
   an ordinal type is. A test with the installed compiler accepts
   `ARRAY [0L..3L] OF INTEGER`, `SET OF [0L..3L]`, `BITS 16 FOR
   [0L..9L]`, `a[1L]`, `CASE` on a LONGINT and `FOR i := 0L TO 3L`.
   Only the size stops it: `ARRAY LONGINT OF` fails in
   `Type.Number` with "type has too many elements". So the new types
   are ordinal everywhere: `FIRST`, `LAST`, `NUMBER`, `ORD`, `VAL`,
   `INC`, `DEC`, `FOR`, `CASE`, subranges, `BITS FOR`, array index
   types and set base types. `ARRAY Word8.T OF ...` and
   `SET OF Word8.T` are legal; `ARRAY Word64.T OF ...` is rejected
   for its size, as `ARRAY LONGINT OF` is. This answers the open
   question below. Phase 2 may reject index and set uses with a "not
   yet implemented" error and enable them in Phase 4, so the rule
   doesn't wait on the code.
   - **Subranges** of a fixed type have that type as their base
     (`SubrangeType` already keeps a base type), and their bounds are
     constants of that type, such as
     `[VAL (0, Word8.T) .. VAL (9, Word8.T)]`.
   - **`ORD (x)`** returns `x`'s base type, as `ORD` of a LONGINT
     returns LONGINT (`builtinOps/Ord.m3`). It is the identity, the
     same on every target, and never fails. Getting an INTEGER takes
     `VAL (x, INTEGER)`, which is checked, or `WordN.ToWord (x)`,
     which keeps the bits.
3. Front-end representation (decided): one new `Type.Class`,
   `Fixed`, appended after `Subrange`, and one module
   `builtinTypes/FixedType.m3` whose objects hold the bit width,
   signedness and overflow policy, with one instance per type. That
   is one class to audit, not eight. What was checked:
   - `Type.Class` is used only in `m3front` (a search of `m3-sys`
     finds no other user), and no array is indexed by it, so
     appending is safe.
   - The front end recognizes LONGINT in two ways: by class (12
     places in 5 files, mostly in `types/Type.m3`: `IsOrdinal`,
     `Number`, `GetBounds`) and by `Type.IsSubtype (t, LInt.T)` or
     `= LInt.T` (56 places in 27 files). Each LONGINT test needs a
     matching test for the new class. `FixedType.Split (t, VAR info)`
     answers "is `t`, or its base, a fixed type, and which one", so
     the code doesn't compare against eight type constants. There are
     41 `CASE` statements over a class; each needs a look, though
     most fall into an `ELSE`.
   - `Target.Int` (`TInt.Int`) is 9 bytes, so every bound of the new
     types, including `2^64 - 1`, fits in `GetBounds`. `Type.Number`
     returns an INTEGER-sized count, so it rejects `Word64.T`,
     `Signed64.T` and, on 32-bit targets, `Word32.T` and
     `Signed32.T` as index or set types, the same way it rejects
     LONGINT.
4. Type descriptions (decided, 2026-11-18): describe each new type
   with the existing `Subrange` opcode and its bounds, for example
   `Word32.T` as `Subrange 0 16_ffffffff` and `Signed8.T` as
   `Subrange -128 127`. No new opcodes and no `Packed`, so
   `TipeDesc.Op`, `Old0` and code already compiled stay as they are.
   What was checked:
   - **The encoding holds `2^64 - 1`.** An integer is a sign bit plus
     up to 8 magnitude bytes. `TipeDesc.AddX` takes a 72-bit
     `Target.Int`, and for `2^64 - 1` `AddBigX` writes `16_48` and
     eight `16_ff` bytes. Every other bound of the eight types is
     already written today, by `INTEGER` and `LONGINT` subranges.
   - **Only `RTTipe` reads type descriptions**
     (`m3core/src/runtime/common/RTTipe.m3`). `RT0` and `RTType` only
     hold the pointer. The only user of `RTTipe` is pickles
     (`ConvertPacking`), which need just the size of each field and
     whether it is signed. Telling `Word8.T` apart from `[0..255]` is
     the fingerprint's job (Phase 2), not the type description's.
   - **On 64-bit hosts `RTTipe` already decodes `2^64 - 1`.**
     `GetDoubleInt` gives `{Hi := 0, Lo := -1}`, which is the right
     two-word value, and `FixSizes` gives it 64 bits.
   - **`RTTipe.FixSizes` has an existing off-by-one** that would size
     `Word32.T` wrong. It tests `Word.LT (sub.max.Lo, 16_ffffffff)`
     where it needs `LE`, so `[0..16_ffffffff]` gets 64 bits while the
     compiler (`SubrangeType.SetRep`) gives it 32. A test program
     shows this on AMD64_LINUX: field size 32 according to `BITSIZE`,
     64 according to `RTTipe`. `[0L..16_ffffffffL]` has the same
     problem; `[0..16_fffffffe]` and `[-2^31..2^31-1]` are right.
     Pickles written and read on one machine still round-trip, which
     was also tested. Converting a pickle between byte orders or word
     sizes would use the wrong layout, but that hasn't been tried.
     This is a one-character fix, worth making (and offering upstream)
     whatever happens to this plan.
   - **On 32-bit hosts `RTTipe` would misread `2^64 - 1`** (from
     reading the code, not tested). The 32-bit branch of
     `GetDoubleInt` gives `{Hi := -1, Lo := -1}`, which is `-1`, and
     `FixSizes` would then give `Word64.T` 8 bits. The fix is for a
     positive value with a negative `Hi` to stay "big": clamp it, or
     have `FixSizes` give 64 bits to any upper bound decoded from 8
     bytes.

   Both `RTTipe` fixes change only the runtime, not the format.
   **Both are now made** (`BUGS.md`, bugs 9 and 10), with a third
   (bug 24: `LONGINT` subranges sized at 32 bits for 32-bit
   packings); test p297. A fourth, in the front end, is fixed too:
   bounds in -255..-64 were encoded wrongly (bug 25). It didn't touch
   the new types' bounds.
5. The wrap conversion (decided): `WordN.Wrap (x)` and
   `SignedN.Wrap (x)`, builtin procedures, not a predeclared `WRAP`.
   `x` may be of any integer type: INTEGER, LONGINT, any of the eight
   new types, or a subrange of one. The result is `x`'s value modulo
   `2^N`, read as unsigned for `WordN` and as two's complement for
   `SignedN`; that equals keeping the low N bits. So
   `Word32.Wrap (x64)` truncates and `Signed32.Wrap (w32)`
   reinterprets. It folds when `x` is constant and never fails.
6. Literal suffixes (open until Phase 4). Constants are written with
   `VAL` and `Wrap` (correction 5). Decision 8 removes the commonest
   case, `INC (x)` and `INC (x, 1)`, but `x + 1` still has to be
   written `x + One`, with `CONST One = VAL (1, Word32.T)`. Phase 4's
   SHA256 rewrite will show how often that matters; decide then.
7. `VAL` (decided). `VAL (x, T)` accepts any integer type for `x`,
   not only INTEGER and LONGINT (`builtinOps/Val.m3` allows only
   those two today), and any ordinal type for `T`. It is checked the
   way it is today: `Val.m3` compares the argument's possible range
   with `T`'s and inserts a check where they differ, so a value
   outside `T`'s range raises `ValueOutOfRange` at run time. So
   `VAL (w, INTEGER)` fails for a `Word64.T` of `2^63` or more.
   - **A constant out of range is not a static error today.** Checked
     with the installed compiler: `VAL (10, [0..9])` compiles without
     a message and fails at run time, as does `VAL (l, [0..9])` with
     a LONGINT `l` of 10 (`Val.m3` has a TODO to warn). So
     `VAL (16_FFFFFFFFFFFFFFFFL, Word64.T)` also fails only at run
     time. Phase 2 may add the warning for all types; making it an
     error would reject code that compiles today.
8. Steps of `INC`, `DEC` and `FOR` (decided): the amount may be of
   the variable's own type or an INTEGER. For a LONGINT it must be a
   LONGINT (`builtinOps/Dec.m3`, `stmts/ForStmt.m3`), but for an
   enumeration it is an INTEGER, so there is a precedent. The INTEGER
   is allowed because an unsigned step can't be negative: without it
   `FOR i := hi TO lo BY -1` couldn't be written over a `WordN.T`,
   and `INC (w, 1)` would need `VAL`. `INC (x, n)` means
   `x := x + n` computed exactly and then made to fit: wrapped for
   `WordN`, checked for `SignedN`. Phase 2 must check that a
   `WordN` loop up to `LAST (T)` (or down to 0) ends, rather than
   wrapping around forever; a `p*` test covers it.

### Phase 2: Front end, wrapping unsigned family

- `types/Type.i3`, `Type.m3`: new class. Update `IsOrdinal`, `Number`,
  `Base`, `GetBounds` and every `CASE` over the class (a rough grep
  finds about 28).
- `builtinTypes/FixedType.m3`: size, alignment, `mem_type`
  (`Word8` to `Word64`), `stk_type` (`Word32` for 8 to 32 bits,
  `Word64` for 64; as built, `Target.Word`'s type for widths up to
  the word size, so `Word64` for all four on 64-bit targets),
  fingerprint, `TipeMap` (`Word_1` to `Word_8` exist), type
  description per Phase 1.
- Operators in `exprs/`: `AddExpr`, `SubtractExpr`, `MultiplyExpr`,
  `DivExpr`, `ModExpr`, `NegateExpr`, `CompareExpr`, `EqualExpr`. Both
  operands must be the same fixed type. Code: emit the M3CG operation
  in the unsigned type; for 8 and 16 bits, mask the 32-bit result with
  `and`. Compare and divide in the unsigned type, which `Word.LT` and
  `Word.Divide` already do (`builtinWord/LT.mg`, `Divide.mg`).
- Constant folding: `IntegerExpr` values carry their type, and folding
  wraps with `TWord` at the type's width. `TInt.Int` has 9 bytes, so
  `2^64 - 1` is representable.
- `builtinOps/`: `First`, `Last`, `Val`, `Ord`, `Inc`, `Dec`, `Min`,
  `Max`, `Number`. `VAL` narrowing uses `check_range` or
  `check_lo`/`check_hi`.
- `types/SubrangeType.m3`: subranges with a fixed base type. Also
  `AssignStmt`, `CheckExpr`, `ForStmt`, `Formal`, `Variable`: the
  places that special-case LONGINT today (the list in the grep below).
- `e*` static-error tests in `m3tests` for mixed operands and
  assignment between types; an `r0` test that
  `VAL (16_FFFFFFFFFFFFFFFFL, Word64.T)` fails at run time. Matching `p*` tests check
  that `Word64.Wrap (16_FFFFFFFFFFFFFFFFL) = LAST (Word64.T)`.

To find every place: `grep -rn "LInt\.T\|Class\.Longint" m3-sys/m3front/src`.

Status (2026-11-18): done, uncommitted at the time of writing. How it
was built, and where it departs from the bullets above:

- **Representation.** `Type.Class.Fixed` and `builtinTypes/FixedType`,
  one object per width. Values sit on the M3CG stack in the word type
  (`stk_type` above). After `+`, `-`, `*`, unary `-`, `INC` and `DEC`,
  `FixedType.Mask` ANDs the result down to the type's width when the
  width is less than the stack type's. DIV, MOD and comparisons need
  no mask: their operands are already in range and the stack type is
  unsigned. The back ends see each type as a subrange of INTEGER or
  LONGINT with its own UID (`FixedType.Compiler`), so neither back
  end changed.
- **Interfaces and linking.** `Word8` to `Word64` are builtin
  interfaces made by the front end (`FixedType.InitializeInterfaces`),
  each exporting only `T` and `Size` for now. No unit in `m3core`
  implements them, so the front end records no version stamps for
  them (`FixedType.IsInterface`, checked in `Module`, `Value` and
  `External`), and `Type.Compile` doesn't note the types. For Phase 3
  this means a choice: either every new procedure is an inline builtin
  that can't be used as a procedure value, or `m3core` gets real
  units and the stamps come back, as for `Word`. Decided
  (2026-11-18): real units in `m3core`.
- **Constant folding** uses `TWord` and then `FixedType.Wrap`, so
  `VAL (200, Word8.T) + VAL (100, Word8.T)` folds to 44, the same as
  the run-time sum.
- **`ORD`** returns the fixed type (decision 2), so
  `Fmt.Int (ORD (w))` is a static error; write `VAL (w, INTEGER)`.
- **`INC`, `DEC` and `FOR`** take a step of the same fixed type or an
  INTEGER (decision 8). A `FOR` over a fixed type has its own loop
  shape (`ForStmt.CompileFixed`): it tests for the last value before
  stepping, so a loop up to `LAST (T)` or down to `FIRST (T)` ends
  without wrapping around.
- **Mixing** fixed types with each other, with INTEGER or with LONGINT
  is a static error in assignment, arithmetic, comparison, `MIN`,
  `MAX`, `INC`, `DEC` and `FOR` bounds. `ABS` rejects a fixed type.
- **Two front-end fixes the new types needed.**
  - `CG.Load_integer`: the CG's lazy stack gives every integer
    constant a signed type, so a `Word64` constant above `2^63 - 1`
    (`LAST (Word64.T)`) reached the C back end as an out-of-range
    `Int64` and failed its `readonly_i = i` assertion. The constant
    is now converted to the signed value with the same bits when its
    type changes.
  - `SubscriptExpr`: an array indexed by a fixed subrange that
    doesn't start at 0 subtracts the lower bound in the fixed type,
    and its range check, since the subtraction wraps, is one unsigned
    comparison of the biased index against the array's last index.
- **Not done.** No compile-time warning for a constant out of range
  in `VAL`, as decision 7 allowed: `VAL (300, Word8.T)` fails only at
  run time, like `VAL (300, [0..255])` upstream.
- **A difference between back ends, not new.** Division by zero gives
  0 with C and SIGFPE with `LlvmIR`, for `Word64.T` as for
  `Word.Divide (1, 0)` upstream. No test depends on it.
- **Tests.** `p298` covers wrapping at each width, constant folding,
  unsigned DIV, MOD and comparisons above `2^63`, `INC`/`DEC`,
  `FOR` loops to `LAST` and down to 0 with constant, variable and
  run-time negative steps, subranges, packed fields, objects, arrays
  indexed by fixed types and their subranges, open arrays, sets and
  `CASE`. Its output is identical with C and `LlvmIR`, at `-O0` and
  `-O`. `e042` checks 21 static errors from mixing types. `r006`
  checks that `VAL` of a LONGINT `-1` to `Word64.T` fails at run time
  (`16_FFFFFFFFFFFFFFFFL` is that same LONGINT `-1`). The
  `Word64.Wrap` test waits for Phase 3.

### Phase 3: Builtin `Word8` to `Word64` interfaces

- `builtinWord/m3makefile`: `word(...)` instantiations for each width,
  with `T` set to the new type. Register them in `misc/M3Front.m3` as
  `Word` and `Long` are.
- Add `Wrap` (from any integer type), `FromWord`, `ToWord`,
  `FromLong`, `ToLong`, and `Brand`, `Equal`, `Hash`, `Compare`.
- `m3core/src/word/`: matching `WordNRep.i3` and `WordN.i3 =
  GenWord(WordNRep)`, in the same declaration order (the comment in
  `Module.mg` warns that the order affects version stamps).
- Check the C back end's `Word8` to `Word64` casts and that `LlvmIR`
  output passes `llvm-as` (`M3_LLVM_IR_VERIFY=1`). With only existing
  M3CG operations, neither back end should need changes; the
  integrated x86 back end already handles 64-bit word operations for
  LONGINT.

Status (2026-11-18): done, `Word32` first (ad1f23913), then `Word8`,
`Word16` and `Word64`. How it was built, and where it departs from
the bullets above:

- **Front end.** Not `builtinWord`'s generics: `GenWord.mg` computes
  in INTEGER or LONGINT and doesn't know about the mask a narrower
  width needs. A new module, `builtinTypes/FixedWord`, declares the
  procedures for every width from the type's `FixedType.Info`.
  `FixedType.InitializeInterfaces` calls it after `T` and `Size`.
  Calls compile inline in the type's stack type. `Plus`, `Times`
  and `Minus` are masked to the width, `Divide`, `Mod` and the
  comparisons are unsigned, and `LeftShift`, `RightShift`, `Extract`
  and `Insert` check their counts as `Word`'s do. `Rotate` uses
  `CG.Rotate` when the width fills the stack type, and otherwise two
  shifts and an OR. Calls with constant arguments fold. `Wrap` takes
  any INTEGER, LONGINT or fixed-width value, `ToWord` and `ToLong`
  zero-extend, `Compare` returns `[-1 .. 1]` and `Brand` is the
  interface's name.
- **`m3core`.** `src/word/GenWordN.ig` and `GenWordN.mg` (generic in
  `Rep`), and for each width `N`: `WordNRep.i3` (`T = WordN.T`,
  `Brand`), `WordN.i3 = GenWordN(WordNRep)` and `WordN.m3 =
  GenWordN(WordN)`. Each
  procedure of the module calls the builtin one, so calls inline and
  the module exists only for procedure values and version stamps.
  The declaration order of `GenWordN.ig` and of `FixedWord.Define`
  must match, or the stamps don't.
- **Which widths have a unit.** `FixedType.hasUnit`, now `TRUE` for
  all four. `FixedType.HasNoUnit` replaces `IsInterface` in `Value`
  and `External`, so stamps and link records are made only for
  widths with a unit. It stays for the signed family (Phase 5),
  whose interfaces may also start without units.
- **Driver.** `Word32Rep.i3` imports the builtin `Word32` for its
  type, and `cm3`'s builder followed that import to `m3core`'s
  `Word32.i3`, compiling and merging it before `Word32Rep.i3`
  ("missing export: Word32Rep.T"). `Builder.ImportsBuiltinFixed`
  makes `Pass0_CheckImports` and `CheckImp` skip exactly that edge,
  from `WordNRep` to `WordN`. (Skipping every import of `WordN`
  also skipped merging the library's `WordN.i3` into client
  programs, which then failed to link.)
- **Bootstrapping.** A compiler older than Phase 3 (the installed
  one, or the d5.12.0 bootstrap CI starts from) has no builtin
  `WordN`, so `WordNRep`'s import finds `m3core`'s own `WordN.i3`
  and reports a circular import. `cm3` now defines the quake
  variable `M3_FIXED_WIDTH_INTEGERS` (`Main.m3`), and
  `m3core/src/word/m3makefile` builds the units only when it is
  defined. Every pass of `concierge.py upgrade` rebuilds `m3core`
  with the `cm3` installed by the pass before, so the first pass
  leaves the units out and the later ones put them in. Checked by
  upgrading a copy of the pre-Phase 3 install with
  `--backend llvmir` and running `p299`, `p300` and `r007`.
- **Tests.** `p299` calls every `Word32` procedure inline, with
  constant arguments, and as a procedure value through `m3core`.
  `p300` instantiates a generic module with each of `Word8` to
  `Word64` and prints every procedure's result three times: from
  inline calls, from constants (which must fold, or the `CONST`
  declarations are rejected) and from procedure values. Its
  expected output was computed separately, by a Python model of
  the operations. `r007` checks that `Word32.LeftShift (x, 32)`
  fails at run time.

### Phase 4: First user, and tests

- Rewrite `libm3`'s SHA256 (or a copy of it) on `Word32.T` and check
  the standard test vectors against the masked version.
- `p*` program tests: wrap at each width, unsigned compare and divide,
  the `Wrap` round trip from the sketch (test 4), constant folding.
  `r0` runtime-error tests for `VAL` narrowing. All on C and `LlvmIR`,
  at `-O0` and `-O`.

### Phase 5: Checked signed family

- Same steps as Phases 2 and 3, for builtin interfaces `Signed8` to
  `Signed64` (`T`, `Wrap`, `Brand`, `Equal`, `Hash`, `Compare`), with the overflow sequences from
  correction 6. For 64-bit multiply, check with division (`a # 0` and
  `r DIV a # b`, plus the `FIRST DIV -1` case). It is slow but needs
  no new IR operation.
- Later, if profiling shows the cost matters: append an overflow-aware
  M3CG operation and implement it in every back end (`M3C` with
  `__builtin_*_overflow`, `m3llvmir` with `llvm.sadd.with.overflow`,
  the integrated back end, `M3CG_LLVM`) and in the M3CG tools
  (`M3CG_Wr`, `Rd`, `BinWr`, `BinRd`, `Check`, `MultiPass`, `Tee`).
  That is why it is last.

### Phase 6: The rest of the system

- Pickles (`libm3/src/pickle/ver2/ConvertPacking.m3`, `PickleStubs`),
  network objects (`stubgen`), `m3tk` (`ast/M3AST_AS.i3`,
  `syn/M3CParse.m3`, `fe/StandardAsText.m3`), `m3browser`. The effort
  is unknown until this code is read. For pickles, the two `RTTipe`
  fixes under Phase 1, decision 4, cover the type descriptions.
- `Cstdint`: re-aliasing `uint32_t` to `Word32.T` changes type identity
  for C-binding code, so leave it for last and make it optional.
- Documentation: the language reference additions, and the `Word`
  interface documentation, including the `Word.T` versus `WordN.T`
  rule above.
- The optional `Word.T` comparison warning, if wanted.

## Open questions

- Is upstream interested? A language extension kept only in this fork
  makes programs that use it unportable to upstream cm3.
- Literal suffixes (Phase 1, decision 6), after Phase 4.
- Answered: array index and set base types accept the new types, as
  they accept LONGINT subranges (Phase 1, decision 2).
