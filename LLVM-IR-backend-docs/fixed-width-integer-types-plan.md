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
   described as an `Enum`. The new types need a decision here (see
   Phase 1).
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
     (16_FFFFFFFFFFFFFFFFL, Word64.T)` is a static error, because the
     literal's value is -1.
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
- **Binary:** new `TipeDesc` opcodes, if chosen, need everything
  rebuilt together, which a cm3 release already requires. Old pickles
  contain no new types and still read.
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

Status (2026-11-18): done, except the build-time and benchmark
comparison.

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
- Running m3tests with C needs care: the installed `cm3.cfg` defaults to
  `LlvmIR`, and `m3tests/src/m3makefile` passes only `LlvmIR` down to
  each test's `cm3`, so `cm3 -DHTML -DM3_BACKEND_MODE=C` still builds
  the tests with `LlvmIR`. A `cm3.cfg` with `M3_BACKEND_MODE = "C"`,
  named by `M3CONFIG`, works.

### Phase 1: Decisions (written down before coding)

1. Names (decided). Builtin interfaces `Word8`, `Word16`, `Word32` and
   `Word64`, and `Signed8`, `Signed16`, `Signed32` and `Signed64`. Each
   exports `T`; `Brand`, `Equal`, `Hash` and `Compare`, so `T` can
   instantiate generics such as `Table`; `Wrap`; and, for `WordN`, the
   `Word` operations at that width plus `FromWord`, `ToWord`,
   `FromLong` and `ToLong`. No 128-bit types.
2. Ordinal rules. Recommendation: follow LONGINT. The types are
   ordinal for `FIRST`, `LAST`, `ORD`, `VAL`, `INC`, `DEC`, `FOR` and
   subranges, but not allowed as an array index type or set base type
   at first.
3. Front-end representation. Recommendation: one new `Type.Class`
   (say `Fixed`, appended after `Subrange`) and one parametrized module
   `builtinTypes/FixedType.m3` holding bit width, signedness and
   overflow policy, with one instance per type. That is one class to
   audit, not eight.
4. Type descriptions. Either new `TipeDesc` opcodes (coordinated with
   `RTTipe` and pickles), or describe the new types with existing
   opcodes (`Packed` around `Subrange`, which may not hold `2^64 - 1`).
   The `TipeDesc` integer encoding needs checking before choosing.
5. The wrap conversion. Recommendation: `WordN.Wrap (x)` and
   `SignedN.Wrap (x)`, builtin procedures that accept any integer type,
   not a predeclared `WRAP`.
6. Literal suffixes: later, or never. Constants are written with `VAL`
   and `Wrap` (correction 5).

### Phase 2: Front end, wrapping unsigned family

- `types/Type.i3`, `Type.m3`: new class. Update `IsOrdinal`, `Number`,
  `Base`, `GetBounds` and every `CASE` over the class (a rough grep
  finds about 28).
- `builtinTypes/FixedType.m3`: size, alignment, `mem_type`
  (`Word8` to `Word64`), `stk_type` (`Word32` for 8 to 32 bits,
  `Word64` for 64), fingerprint, `TipeMap` (`Word_1` to `Word_8`
  exist), type description per Phase 1.
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
- `e*` static-error tests in `m3tests` for mixed operands, assignment
  between types and out-of-range constants, including
  `VAL (16_FFFFFFFFFFFFFFFFL, Word64.T)`. Matching `p*` tests check
  that `Word64.Wrap (16_FFFFFFFFFFFFFFFFL) = LAST (Word64.T)`.

To find every place: `grep -rn "LInt\.T\|Class\.Longint" m3-sys/m3front/src`.

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
  is unknown until this code is read.
- `Cstdint`: re-aliasing `uint32_t` to `Word32.T` changes type identity
  for C-binding code, so leave it for last and make it optional.
- Documentation: the language reference additions, and the `Word`
  interface documentation, including the `Word.T` versus `WordN.T`
  rule above.
- The optional `Word.T` comparison warning, if wanted.

## Open questions

- Is upstream interested? A language extension kept only in this fork
  makes programs that use it unportable to upstream cm3.
- `TipeDesc`: new opcodes or an encoding with existing ones.
- Whether array index and set base types should accept the new types
  (for example `ARRAY Word8.T OF ...` for a byte table).
