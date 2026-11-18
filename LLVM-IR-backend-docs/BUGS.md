# Bugs found while working on this fork

This lists bugs found while working on this fork, the ones fixed and the
ones still open. Most were found while comparing the C back end with
`LlvmIR` or while running m3tests. Each bug keeps its number for good;
a newly found bug gets the next one.

Each bug says where it lives (upstream code, or code this fork added),
its status, and how it was found or checked. "Upstream" means the bug
is in upstream cm3 too, so the fix may be worth offering there. Where a
claim comes from reading code rather than from a test, the entry says
so.

Bugs 1 to 10, 12, 14, 24 and 25 are fixed; 23 turned out not to be a bug; the
others are open.

## Bug 1: C back end: set and word operations give wrong results

- **Where:** upstream, `m3-sys/m3back/src/M3C.m3`.
- **Status:** fixed in 8be996c90 (marked "This fork" in the source).
- **Found by:** the mixed-linking tests in `m3-sys/m3llvmir/tests/`,
  which link C-built and `LlvmIR`-built code and compare output, and
  then by m3tests. With the fixes, m3tests with C fails 22 tests instead
  of 27 (GCC 16, AMD64_LINUX); p053, p156, p159, p160 and p162 pass.

### Bug 1.1: `Word.Extract` and `Word.Insert` with a count of 64

`Word.Extract (x, 0, 64)` and `Word.Insert (x, y, 0, 64)` shifted by
64, which is undefined in C. They now compute in `UINT64` and handle
the full-width count.

### Bug 1.2: `shift_right` on signed types is arithmetic

`shift_right` used C's `>>` on signed types, which shifts in copies of
the sign bit, so one-word set ranges came out wrong. It now shifts as
unsigned.

### Bug 1.3: Set `<=` and `<` reversed on multi-word sets

`m3_set_le` and `m3_set_lt` named their parameters in the opposite
order to the call, so `<=` and `<` on sets longer than one word gave
reversed results.

### Bug 1.4: Set `=` and `#` inverted for sets in memory

`=` and `#` on sets held in memory gave inverted results.

### Bug 1.5: Missing `SET` typedef

A unit whose only set operations were comparisons didn't get the `SET`
typedef, so its C++ failed to compile ("'SET' was not declared in this
scope"; p053, p160).

## Bug 2: C back end: signed `INTEGER` and `LONGINT` overflow is undefined

- **Where:** upstream, `m3-sys/m3back/src/M3C.m3`.
- **Status:** fixed in 547d4f16b (Phase 0 of
  [`fixed-width-integer-types-plan.md`](fixed-width-integer-types-plan.md)).
  A new test, p296, checks wrapping at the limits. The cost is measured
  in that plan and in [`fwint-phase0/`](fwint-phase0/).

### Bug 2.1: `+`, `-`, `*` and unary minus

These were emitted as C signed arithmetic, whose overflow is undefined
behavior. GCC folded `x + 1 > x` to TRUE at `LAST(INTEGER)`, even at
`-O0`. Signed operands are now cast to the unsigned type, operated on
and cast back, so overflow wraps.

### Bug 2.2: `ABS (FIRST (INTEGER))`

`ABS` negated in the signed type, with the same undefined overflow.
A new `m3_iabs_T` helper negates through the unsigned type, so
`ABS (FIRST (INTEGER))` wraps as well.

## Bug 3: `cm3 -ship` in `m3-sys/cm3` doesn't update `bin/cm3`

- **Where:** upstream behavior, by design: `program ("cm3")` installs
  into `INSTALL/pkg/cm3/`, not `INSTALL/bin/`, so shipping never
  replaces the running compiler. Only `concierge.py` copied it to
  `bin/`, and only as part of a full build.
- **Status:** worked around in 2a7330d19. `concierge.py ship-compiler`
  copies the driver already built in `m3-sys/cm3` to `bin/` without
  rebuilding anything.

## Bug 4: m3tests ignores `-DM3_BACKEND_MODE=C`

- **Where:** `m3-sys/m3tests/src/m3makefile`. Upstream doesn't pass
  `-DM3_BACKEND_MODE` to each test's `cm3` at all; this fork added it
  only for `LlvmIR`.
- **Status:** fixed in 2a7330d19. The makefile now always passes
  `M3_BACKEND_MODE`.
- **Effect before the fix:** with an install whose `cm3.cfg` defaults
  to `LlvmIR`, `cm3 -DHTML -DM3_BACKEND_MODE=C` silently tested
  `LlvmIR`.

## Bug 5: ex_stack: an uncaught exception prints only "terminate called"

- **Where:** upstream, the zero-cost exception model (`RTStackC.c`,
  `RTExStack`).
- **Status:** fixed in f437aeef3.
- **Detail:** an uncaught Modula-3 exception made the C++ runtime call
  `std::terminate`, which printed "terminate called after throwing an
  instance of '_M3Exc'" and nothing else. A `std::terminate` handler
  now calls the backstop while the stack is intact, so the report is
  the same as with ex_frame. r001, r003, r004 and r005 now pass with
  ex_stack, with both `LlvmIR` and C.

## Bug 6: concierge exits 0 after a fatal error

- **Where:** upstream, `scripts/concierge.py`.
- **Status:** fixed in 9cb01399d.
- **Detail:** concierge printed a `FatalError` and exited with status
  0, so a CI step went on until a later step failed for an unrelated
  reason. It now exits 1.

## Bug 7: `m3llvmir` built before `m3bundle` on a fresh install

- **Where:** this fork, `scripts/pkginfo.txt`.
- **Status:** fixed in cc06dde79.
- **Detail:** the Phase 5 bundling of `m3printers.py` needs
  `m3bundle`, which a bootstrap install doesn't have yet. Every fresh
  build failed, upstream's CI jobs included. `m3llvmir` now comes after
  `m3bundle` and `mklib`.

## Bug 8: `llvm22bindings` links libraries from `/lib`

- **Where:** upstream, `m3-sys/llvm/llvm22bindings`.
- **Status:** fixed in 992071694.
- **Detail:** on Fedora `/lib` holds 32-bit libraries, so gold warned
  "skipping incompatible /lib/libm.so", and `--fatal-warnings` failed
  the link. The package now finds `stdc++`, `z` and `zstd` through
  `llvm-config --libdir`.

## Bug 9: `RTTipe` sizes `[0..16_ffffffff]` at 64 bits

- **Where:** upstream, `m3-libs/m3core/src/runtime/common/RTTipe.m3`,
  `FixSizes`.
- **Status:** fixed (marked "This fork" in the source), together with
  bugs 10 and 24. Regression test: m3tests p297, which compares
  `RTTipe`'s size of 21 subrange fields with `BITSIZE` under 32- and
  64-bit packings. Before the fix, 11 of them differed.
- **Detail:** the subrange case tests
  `Word.LT (sub.max.Lo, 16_ffffffff)` where it needs `Word.LE`. So
  `[0..16_ffffffff]` and `[0L..16_ffffffffL]` get 64 bits, while the
  compiler (`SubrangeType.SetRep`) gives them 32. A test program showed
  a field size of 32 from `BITSIZE` and 64 from `RTTipe`, with the next
  field placed 32 bits too late.
- **Effect:** pickles are the only user of `RTTipe`. A pickle written
  and read on the same machine still round-trips (tested). Converting a
  pickle between byte orders or word sizes would use the wrong layout
  (not tested). The planned `Word32.T` would hit this.
- **Fix:** `FixSizes` now sizes subranges the way `SubrangeType.SetRep`
  does, comparing the whole two-word bounds rather than their low
  words. That fixes this bug and bug 24.

## Bug 10: `RTTipe` on 32-bit hosts misreads bounds of `2^63` and above

- **Where:** upstream, `RTTipe.m3`, `GetDoubleInt` and `FixSizes`.
- **Status:** fixed, with bug 9. There's no 32-bit host here, so the fix
  was checked by emulating, with 32-bit arithmetic, the 32-bit branch of
  `GetDoubleInt` and the new `FixSizes`: for every valid pair of 43
  bounds, from -2^63 to 2^64 - 1, the size matched the compiler's.
- **Detail:** the 32-bit branch of `GetDoubleInt` decodes the 8-byte
  value `2^64 - 1` as `{Hi := -1, Lo := -1}`, which is -1. `FixSizes`
  would then size a subrange with that upper bound at 8 bits. No type
  has such a bound today; the planned `Word64.T` would.
- **Fix:** `GetDoubleInt` reads a positive value of 2^63 or more as
  2^63 - 1. That's not its value, but only sizes depend on it, and any
  such bound needs 64 bits.

## Bug 11: `cm3 -keep` doesn't keep M3CG IR in C mode

- **Where:** upstream, `m3-sys/cm3/src/Builder.m3`.
- **Status:** open (worked around by
  [`gen_m3cg_corpus.sh`](gen_m3cg_corpus.sh)).
- **Detail:** `PushOneM3` sets `m3env.sideIRName`, then `RunM3Front`
  calls `ResetEnv`, which clears it before `M3Backend.Open` sees it. So
  `-keep` writes no `.mc`/`.ic` side files. From reading the code,
  confirmed by the missing files; a one-line fix looks possible.

## Bug 12: C back end output triggers GCC 16's `-Wvolatile` warning

- **Where:** upstream, the `m3_pop_T` macro in `M3C.m3`'s generated
  C++.
- **Status:** fixed (marked "This fork" in the source).
- **Detail:** GCC 16 warns "'volatile'-qualified parameter is
  deprecated". The programs are fine, but the warning lands in
  `stderr.build`, so m3tests fail on it: p039, p085, p100, p117, p137,
  p140, p184, p189, p205, p265, p283 and e020, most of the C back
  end's remaining failures.
- **Why `volatile`:** `cg_pop` (`EVAL e`) calls `m3_pop_T (e)`; the
  `volatile` parameter (2012, "don't discard pop side effects") was
  meant to keep `e` evaluated. It didn't at `gcc -O2`: `EVAL p^.a` with
  `p` NIL ran on without faulting (tested 2026-11-18, with
  `LLVM-IR-backend-docs/phase4/gcc-O2-wrapper`).
- **Fix:** `m3_pop_T` takes a plain parameter and stores it in a
  `volatile` local, which C++20 allows and which keeps the load:
  `EVAL p^.a` now faults at `-O0` and `-O2`, and the warning is gone.
  m3tests with C (GCC 16): 8 failures, down from 22; the 8 are bugs
  13, 15 and 16.

## Bug 13: C back end emits C++ that doesn't compile

- **Where:** upstream, `M3C.m3`.
- **Status:** open. All three tests pass with `LlvmIR`.

### Bug 13.1: `FIRST`/`LAST` of enumerations in record constants (p109)

"invalid cast from type 'const Main_m_4_L_5_t'".

### Bug 13.2: Nested array constructors (p269)

"expected initializer before 'temp'".

### Bug 13.3: Recursive values (p201)

`M3C.m3` stops with "DeclareTypes not progressing".

## Bug 14: C back end: `FIRST(INTEGER) * NotConstI(0)` (p227)

- **Where:** upstream, the C back end or GCC's treatment of its output.
- **Status:** fixed. Both of p227's checks pass with C (m3tests,
  2026-11-18). Most likely bug 2's fix did it: C failed 22 tests
  before that fix and 8 after it and bug 12's, which accounts for
  bug 12's 12 tests and p227's 2 checks. Not confirmed by rerunning
  p227 with the old compiler.
- **Detail:** p227 fails `<*ASSERT*> (FIRST(INTEGER) * NotConstI(0)) = 0`
  at line 250, and its output stops there. `LlvmIR` passes.

## Bug 15: Constructor tests differ with the C back end (p268, p270, p277, p280)

- **Where:** upstream; not yet narrowed down.
- **Status:** open; not investigated. All four pass with `LlvmIR`.
- **Detail:** debugging output (`TIntLiteral:type=UINT64 i=-8 ok1=FALSE
  ok2=TRUE`) appears, the "N warnings encountered" line is missing,
  and the expected run-time errors appear in a different form.

## Bug 16: p047 fails with every back end

- **Where:** upstream, probably the test's expected output.
- **Status:** open; the one known failure with `LlvmIR` on every
  platform.
- **Detail:** Real/Integer `LOOPHOLE` prints `1067316150 instead of 1`
  and so on. Probably an expected-output problem now that EXTENDED is
  128 bits on AMD64_LINUX; not confirmed.

## Bug 17: e041 overflows the front end's stack

- **Where:** upstream, `m3-sys/m3front`.
- **Status:** open; a known failure in this fork's CI.
- **Detail:** e041's mutually recursive REVEALs make the front end
  recurse until it crashes with a segmentation fault, whatever the
  back end. Under bash (Fedora's `/bin/sh`) the shell reports the
  crash on its own stderr and the test passes; under dash (Ubuntu's)
  the message lands in the captured stderr and the test fails.

## Bug 18: Front-end failures with atomics

- **Where:** upstream, `m3-sys/m3front` and `m3-libs/m3core`.
- **Status:** open; found in Phase 3 (see `PLAN.md`).

### Bug 18.1: `AtomicLongint.FetchInc` with a LONGINT increment crashes the front end

### Bug 18.2: An atomic call can't be a boolean operand

The front end rejects it with "CallExpr.NotBoolean".

### Bug 18.3: The builtin `Atomic*` interfaces have no exporter

`m3core/src/atomic` is disabled, so any program that imports them
(p226, which is commented out) fails cm3's version-stamp check with
every back end.

## Bug 19: Grisu's single-precision path fails its own assertion

- **Where:** upstream, `m3-libs/m3core/src/float/`, `IEEE.m3`,
  `NormalizedBoundaries_S`.
- **Status:** open; avoided by building with `no_grisu` for both C and
  `LlvmIR`.
- **Detail:** fails its `<*ASSERT*>` with either back end. With Grisu,
  p003, p040, p113 and p118 fail.

## Bug 20: The parallel back end ignores failed compiles

- **Where:** upstream, quake's `try_exec` under `M3_PARALLEL_BACK`, as
  used by `compile_c` and `compile_llvm_ir` in `Unix.common`.
- **Status:** open; left alone as upstream behavior. This fork's
  `M3_LLVM_IR_VERIFY` step uses `exec` to avoid it.
- **Detail:** each back-end command becomes a promise, and `try_exec`
  promises ignore their exit status. A failed compile shows up only
  when the link can't find the object.

## Bug 21: `cm3 -O` doesn't optimize C back end output

- **Where:** upstream, `m3-sys/cm3/src/Builder.m3`.
- **Status:** open; may be deliberate.
- **Detail:** `Builder.m3` compiles the C back end's output with
  `optimize := FALSE`, so `cm3 -O` in C mode still runs `gcc -O0`.
  Measured in [`phase4-results.md`](phase4-results.md), which uses
  `phase4/gcc-O2-wrapper` to get `-O2`.

## Bug 22: cm3 doesn't recompile when the compiler changes

- **Where:** upstream, `m3-sys/cm3`.
- **Status:** open; may be deliberate.
- **Detail:** a unit whose source hasn't changed isn't recompiled
  after the compiler or a back end changes. To test a back-end change,
  delete the `AMD64_LINUX` directory or touch the sources.

## Bug 23: p283 has no expected `stderr.build`

- **Where:** upstream, `m3-sys/m3tests/src/p2/p283`.
- **Status:** not a bug; it's bug 12. Checked 2026-11-18.
- **Detail:** p283 has no expected files at all, and that's fine:
  `cmp_file` in `m3tests/src/m3makefile` compares a missing expected
  file as an empty one. The test failed with C because GCC 16's
  `-Wvolatile` warning (bug 12) made `stderr.build` non-empty. With
  `LlvmIR` the build writes nothing to stderr and p283 passes. Adding
  an empty `stderr.build` would change nothing.

## Bug 24: `RTTipe` sizes wide `LONGINT` subranges at 32 bits for 32-bit packings

- **Where:** upstream, `RTTipe.m3`, `FixSizes`.
- **Status:** fixed, with bug 9; test p297.
- **Found by:** the probe for bug 9, on AMD64_LINUX, 2026-11-18.
- **Detail:** for a packing with `word_size = 32`, `FixSizes` gave
  every subrange wider than 16 bits 32 bits. The compiler gives
  `[0L..16_1ffffffffL]`, `[-16_80000001L..0L]` and other `LONGINT`
  subranges that don't fit in 32 bits 64 bits, whatever the target.
  So would a 32-bit target's `RTTipe` reading a 64-bit target's
  pickle with such fields.

## Bug 25: The front end encodes subrange bounds in -255..-64 wrongly

- **Where:** upstream, `m3-sys/m3front/src/misc/TipeDesc.m3`, `AddI`.
- **Status:** fixed (marked "This fork" in the source). Found while
  writing p297, 2026-11-18. p297 now also checks the bounds `RTTipe`
  reads back for `[-129..0]`, `[-200..-64]` and `[-255..16_ffffff]`;
  with the old front end they came back as `[-127..0]`, `[-56..-192]`
  and `[-1..16_ffffff]`.
- **Detail:** for a value from -255 to -64, `AddI` writes
  `Stuff (16_c1); Stuff (i)`. That stores the low byte of the negative
  number, where `GetDoubleInt` in `RTTipe` (and the encoding of every
  other value) expects its magnitude, `-i`. So -129 is written as byte
  16_7f and read back as -127, and `RTTipe` sizes `[-129..0]` at 8 bits
  where the compiler uses 16. -200 reads back as -56. The code dates
  from the 2001 import.
- **Effect:** wrong bounds and sizes in `RTTipe` for subranges with
  such a lower bound, so wrong layouts in pickles of records with such
  fields. Same-machine round trips are probably unaffected, as for
  bug 9 (not tested).
- **Fix:** `Stuff (-i)`. It takes effect only for code compiled by the
  fixed front end. `RTTipe` can't work around it for code already
  compiled: the wrong bytes are also valid encodings of other values
  (both -129 and -127 came out as 16_7f).
