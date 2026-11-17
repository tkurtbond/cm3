# Plan: an LLVM backend for cm3 that emits textual LLVM IR

Status: draft, 2026-11-16. Phases 0, 1, 2, 4 and 5 are done; Phase 3
is done except `ex_stack`, which is deferred (see Phase 3).

## Goal

Add a cm3 code generator that implements the M3CG interface and writes
**textual LLVM IR** (`.ll`). The system's LLVM tools (`clang`, or `llc`
plus the assembler) then compile that IR to object code. The compiler
never links against LLVM's libraries.

Success means:

- Programs compiled with the new backend behave identically to the
  same programs compiled with the C backend.
- `m3core`, `libm3`, and the compiler itself build with it.
- The compiler built with it can rebuild itself (self-hosting).
- It works with any LLVM from a stated minimum version through the
  current release, installed from distribution packages.

## Starting point: what already exists

**The M3CG interface** (`m3-sys/m3middle/src/M3CG_Ops.i3`). The front
end drives a stack-machine code generator object. A new backend is
another implementation of that object, so the front end stays unchanged.

**The C backend** (`m3-sys/m3back/src/M3C.m3`, about 8,300 lines). It is
the default on AMD64_LINUX. It runs in-process inside `cm3`, writes C
text, and `cm3` then calls the `compile_c` quake proc. It replays the
M3CG stream through `M3CG_MultiPass` so it can emit declarations
before use. Architecturally this is the closest template: a
text-emitting, in-process backend. It is also the **reference oracle**
for testing.

**The existing LLVM backend** (`m3-sys/llvm/llvm22/src/M3CG_LLVM.m3`,
about 7,100 lines, plus `llvm22bindings`). It is still maintained (the
latest commit is from May 2026, for LLVM 22). It builds IR in memory
through LLVM's C API (about 790 `LLVM.*` calls) and runs as a separate
`m3llvm` executable that reads binary M3CG IR files. It also handles
`start_try`, `invoke_direct` and `landing_pad`. It needs LLVM
development libraries to build, and its own README warns about
assert-enabled LLVM builds and opaque error messages. **It holds the
lowering knowledge we need**: how each M3CG operation maps to LLVM,
static links, atomics, debug info. We read it as a reference, not as a
dependency.

**The driver plumbing** (`m3-sys/cm3/src/Builder.m3`, `M3Backend.m3`,
`Target.i3`, `cminstall/src/config/Unix.common`). There are already
backend modes `IntLlvm*`, `ExtLlvm*` and `StAloneLlvm*`, with quake
procs `m3llvm`, `llvm_backend` (runs `llc`) and `llvm_opt`. The
concierge accepts `--backend llvm`, which builds and uses `m3llvm`.

**The tools on the development machine**: clang/LLVM 22.1 and GCC 16.
This fork's compiler goes in `/usr/local/sw/versions/cm3/git`, built
from the d5.12.0 bootstrap release (see `AGENTS.md`).

## Key design decisions

Decisions 4 (package name) and 6 (minimum LLVM version), and the mode
name in decision 2, were settled on 2026-11-16 as recommended below.
The rest are the working design.

1. **Write a new emitter; don't wrap the old one.** Two alternatives
   were considered:
   - *Reimplement the subset of the LLVM C API that `M3CG_LLVM.m3` uses*
     as a pure Modula-3 library that prints text. This would reuse the
     old backend nearly unchanged, but `M3CG_LLVM` also relies on
     LLVM's constant folding, type queries, `DIBuilder`, and verifier,
     so the shim would become a small LLVM clone that tracks the shape
     of LLVM's C++ API, which is exactly the coupling we want to escape.
   - *Turn `M3CG_LLVM.m3` into a printer in place.* The API calls are
     spread through every procedure, so this is a rewrite in disguise,
     and it would diverge from the upstream copy.

   So: a new backend structured like `M3C.m3` (an M3CG object writing
   text), porting lowering decisions from `M3CG_LLVM.m3` operation by
   operation.

2. **Run in-process, like the C backend.** Add one backend mode,
   appended to `Target.M3BackendMode_t` so existing numeric mode
   strings keep their meaning. The working name is `LlvmIR`. `cm3`
   writes `Foo.m3.ll` or `Foo.i3.ll`, following the C backend's
   naming (`CCodeName := M3Unit.FileName (u) & ".cpp"` in `PushOneM3`,
   `Builder.m3` around line 1597; the C backend actually emits C++ and
   compiles it with `gcc -x c++`), then calls a new
   quake proc, `compile_llvm_ir`,
   to produce the `.o`. No separate executable is needed in normal use,
   and no LLVM libraries are needed at build time.

3. **Also provide a standalone driver for development.** This is a
   small program (working name `m3llir`, like `m3llvm`'s `Main.m3`) that
   reads a binary or ASCII M3CG file with `M3CG_BinRd`/`M3CG_Rd` and
   runs the same emitter. It allows a fast edit-and-test loop on saved IR
   files without rebuilding and reshipping `cm3`. It also allows
   regression tests that pin an M3CG input to an expected `.ll`.

4. **Package layout.** A new library package, `m3-sys/m3llvmir/`,
   holds the emitter. `cm3` imports it, and a sibling program package
   holds the standalone driver. This keeps the fork's code apart from
   files upstream edits, so merges stay easy. Upstream could later move
   it into `m3back` if it wants.

5. **Use `clang` as the IR-to-object driver.** Use `clang -c -x ir Foo.ll
   -o Foo.o` with the target triple, `-fPIC`, `-O0`/`-O2`, `-g`, and
   `-fno-omit-frame-pointer`. This avoids a separate assembler step and
   matches how the C backend calls the C compiler. The quake proc can
   be overridden to use `llc` plus `as` instead.

6. **IR dialect: opaque pointers only, minimum LLVM 18** (settled). LLVM
   17 removed typed pointers, and LLVM 18 is the oldest version with an
   in-tree binding here. Test the minimum and the newest available LLVM.
   Emit only constructs that are stable in that range: no new intrinsics
   or attributes without a version gate.

7. **The emitter's internal shape.**
   - M3CG is a stack machine. The emitter keeps a **compile-time operand
     stack** of IR values (SSA names or constants, each with its LLVM
     type). Each M3CG operation pops operands, prints one or more
     instructions into the current function buffer, and pushes the
     result. Use fresh `%tN` names and never reuse them.
   - **Locals and parameters live in `alloca` slots** in the entry block.
     The emitter doesn't do its own register allocation or SSA
     construction. `mem2reg` (at `-O1` and above) cleans this up.
     Conservative GC stack scanning continues to work because nothing
     depends on precise pointer locations.
   - **Each procedure gets its own text buffer** and is flushed at
     `end_procedure`. This handles nested procedures, whose bodies can
     appear while the outer one is still open. Module-level items
     (globals, function declarations, named types, metadata) go in
     separate buffers that are assembled in `end_unit`. Textual LLVM IR
     allows forward references at module scope, so no full multi-pass
     replay should be needed. Fall back to `M3CG_MultiPass` only if a
     specific operation needs lookahead.
   - **Module data segments** (`declare_segment`, `init_int`,
     `init_chars`, `init_var`, `init_proc`, `init_label`, `init_offset`,
     `init_float`) become one global per segment with a packed-struct
     initializer `<{ ... }>` built from the byte offsets, with explicit
     `[N x i8] zeroinitializer` padding. Addresses into the segment are
     `getelementptr i8, ptr @seg, i64 off`.
   - **Keep a thin layer of value and type records** separate from the
     printing, so lowering logic reads like `M3CG_LLVM.m3` and the
     printing is in one place. That place will need to change when the
     IR syntax changes.

8. **Semantics where LLVM and Modula-3 differ.** Get these right from
   the start, and cross-check each one against `M3C.m3` and
   `M3CG_LLVM.m3`:
   - `Word.Shift`/`Rotate` with a count of at least the word size (or a
     negative count for the general forms): Modula-3 defines the result,
     while LLVM `shl`/`lshr` yield poison. Guard them with a `select`,
     or use `fshl`/`fshr` for rotates.
   - `DIV`/`MOD` round toward negative infinity, while `sdiv`/`srem`
     truncate. Emit the correction sequence, or call the same runtime
     helpers the C backend uses.
   - Bit-field `extract`/`insert` with variable offsets and widths, and
     sign extension.
   - Overflow and range checks (`check_*`, `abort`/runtime fault calls)
     must survive optimization: mark fault procedures `noreturn` and
     `cold`.
   - **`setjmp` must be declared `returns_twice`** for the default
     `ex_frame` exception model. Without it, optimized code silently
     miscompiles `TRY`.
   - Floating point: REAL is `float` and LONGREAL is `double`. On
     AMD64_LINUX, **EXTENDED is 128-bit `_Float128`**, which is LLVM
     `fp128` (see `Target.m3`; on every other target it is 64-bit).
     `fp128` arithmetic is done through libgcc/libquadmath calls, its
     parameter-passing ABI must match what the C backend's `_Float128`
     produces, and its alignment needs care (see the existing backend's
     May 2026 fix). Float
     conversions and rounding modes (`cvt_int` with
     `round`/`trunc`/`floor`/`ceiling`) map to specific intrinsics.
   - Nested procedures: the static link is an extra leading `ptr`
     parameter, and uplevel-referenced locals are reached through it.
     Port `M3CG_LLVM.m3`'s approach. The 2017 status note says it needed
     a different unnesting order from m3cc.
   - Atomics map directly to `load atomic`/`store atomic`,
     `atomicrmw`, `cmpxchg` and `fence`, with the memory order from
     `MemoryOrder`.
   - Calls: struct and record returns, `pop_struct`, large by-value
     parameters, and indirect calls with and without a static link
     (`pop_static_link`).

## Phases

Each phase ends with an **exit criterion** that can be checked
mechanically. Phases 1 to 4 are the core. Later phases can be
reordered.

### Phase 0: baseline and groundwork

- **Done:** cm3 built from this tree with the C backend, installed in
  `/usr/local/sw/versions/cm3/git` (bootstrapped from the d5.12.0
  release as upstream CI does; d5.11.4 in `~/cm3` is too old because
  EXTENDED became 128-bit on AMD64_LINUX). The commands are in
  `AGENTS.md`.
- **Done:** backend override. The installed `cm3.cfg` sets
  `M3_BACKEND_MODE = "C"` (not readonly), and `cm3 -DM3_BACKEND_MODE=X`
  still selects mode X: tried with `IntegratedObject`. So `LlvmIR`
  can be selected per build without a config variant. (The integrated
  backend itself is broken on AMD64_LINUX: its `.o` files are not ELF.)
- **Done:** m3tests baseline with the C backend; see
  `experiment-doc/m3tests-baseline-c.md`.
- **Skipped:** building the existing `m3llvm`. `llvm-devel` (headers,
  `llvm-config`, libraries) isn't installed. Reading `M3CG_LLVM.m3` is
  enough for now; install `llvm-devel` and build `llvm22bindings` and
  `llvm22` if we need its `.ll` output to compare against.
- **Done:** M3CG IR corpus in `experiment-doc/m3cg-corpus/`, made by
  `experiment-doc/gen_m3cg_corpus.sh`: ASCII IR for 11 `c0`/`p0` tests
  (empty program, CASE, TRY FINALLY, nested procedures, fibonacci,
  floats, sets, open arrays, objects, exceptions, DIV/MOD), using 97 of
  the 146 ops. Findings while getting there:
  - `cm3 -keep` does **not** write IR side files in C mode, even
    though it is meant to: `PushOneM3` sets `m3env.sideIRName`
    (`Builder.m3` ~1647), then `RunM3Front` calls `ResetEnv`, which
    clears it (~1956) before `M3Backend.Open` sees it. This is a
    latent upstream bug; a one-line fix is possible but not needed yet.
  - `USE_C_BACKEND_VIA_M3CGCAT` is dead: `m3cgcat`'s C output is
    commented out.
  - What works: build in `ExternalObject` mode, where cm3 always
    writes `Foo.mc`/`Foo.ic` and calls the quake proc `m3_backend`,
    and redefine `m3_backend` in the package's m3makefile to run
    `m3cgcat -in-binary:SRC -out-ascii:SRC.txt`. The script does this.
    The same trick (an m3makefile-level `m3_backend`) is a cheap way
    to try the standalone `m3llir` driver inside real builds in
    Phase 1, before the in-process mode exists.
- **Done:** an operation checklist listing all 146 methods in
  `M3CG_Ops.i3`, with a status column and links to the implementing
  procedures in `M3C.m3` and `M3CG_LLVM.m3`. It is in
  `experiment-doc/m3cg-ops-checklist.md`, generated by
  `experiment-doc/gen_m3cg_checklist.py`.
*Exit:* a cm3 built from this tree on PATH, a recorded test baseline, an
IR corpus, and the checklist. **Met 2026-11-16.**

### Phase 1: skeleton end to end

- Create the `m3llvmir` package with an `M3CG_Ops.Public` subtype that
  starts from `M3CG_AssertFalse` or `M3CG_DoNothing`, so unimplemented
  operations fail loudly.
- Implement the unit framework: `begin_unit`/`end_unit`, module
  header (`target triple`, `target datalayout` from `Target`), import
  and export declarations, `declare_procedure`/`import_procedure`,
  `begin_procedure`/`end_procedure` with an empty body, and segments
  with initializers.
- The standalone driver `m3llir` reads an M3CG file and writes `.ll`.
- Add the `LlvmIR` backend mode, the branch in `M3Backend.Open`, the
  compile step in `Builder.m3`, and a `compile_llvm_ir` proc in
  `Unix.common`.
- Run the test harness against every `.ll` produced: `llvm-as` (or
  `opt -passes=verify`) must accept it.

*Exit:* an interface-only unit and an empty module compile through
`cm3 -DM3_BACKEND_MODE=LlvmIR` to `.o` files that verify and link
against an `m3core` and `libm3` built with the C backend.
**Met 2026-11-16.**

Phase 1 as built:
- `m3-sys/m3llvmir` (`M3LLVMIR.New (wr)`) subtypes `M3CG_AssertFalse`.
  Besides the unit framework it already does enough of Phase 2 for a
  module body: locals and parameters as allocas, `load`/`store`,
  `load_address`, `load_integer`, `load_nil`, `pop`, labels, `jump`,
  `if_true`/`if_false`, `exit_proc`, and direct calls without a static
  link. Nested procedures, up-level variables and struct parameters
  stop with an `m3llvmir:` error. `experiment-doc/m3cg-ops-checklist.md`
  marks the implemented operations `wip`.
- Target: `LlvmIR` lays out data and calls like the C backend
  (`Target.CLayout` in `Target.m3`), so the output links with C-built
  libraries. Only AMD64_LINUX has a triple and datalayout so far
  (ARM64_LINUX was added in Phase 7).
- `m3-sys/m3llir`: `m3llir [-a] [-b] [-t TARGET] [-o OUT] [IN]` reads
  ASCII (`-a`) or binary M3CG and writes `.ll`. All `_m3main` units and
  the c001 and p066 `Main` units in `experiment-doc/m3cg-corpus/`
  translate and pass `llvm-as`; the rest stop at unimplemented
  operations.
- `cm3 -DM3_BACKEND_MODE=LlvmIR` writes `Foo.m3.ll` and runs the
  `compile_llvm_ir` proc from `Unix.common` (`clang -fPIC
  -Wno-override-module -c -x ir`, with `-O2` under `-O` and `-g` for
  debug builds). The main program `_m3main` is still generated as C.
- `m3llvmir` is in `scripts/pkginfo.txt` (sets `core front`), so
  `concierge.py upgrade` builds it before `cm3`.

### Phase 2: core code generation, with mixed-backend linking

Implement in roughly this order, testing as you go:

1. Constants, loads and stores (`load`, `store`, `load_indirect`,
   `store_indirect`, `load_address`, `load_integer`, `load_nil`), and
   locals and parameters as allocas.
2. Integer and Word arithmetic, comparisons, conversions (`loophole`,
   `widen`, `chop`), and `add_offset`/`index_address`.
3. Control flow: `set_label`, `jump`, `if_true`/`if_false`/`if_compare`,
   `case_jump` (to `switch`), and `exit_proc`.
4. Calls: `start_call_direct`/`indirect`, `pop_param`, `pop_struct`,
   `call_direct`/`indirect`, `pop_static_link`, `load_static_link`.
5. Runtime checks and faults (`check_nil`, `check_lo`, `check_hi`,
   `check_range`, `check_index`, `check_eq`, `abort`).
6. Block operations: `copy`, `copy_n`, `zero`, `zero_n` (to
   `llvm.memcpy`/`llvm.memmove`/`llvm.memset`).

Only the user's own code is compiled with the new backend. `m3core`
and `libm3` stay on the C backend, which tests ABI compatibility
between the two backends from day one.

*Exit:* hello world runs. The `p0` program tests pass when compiled
with `LlvmIR` and linked against C-backend libraries, with the same
pass/fail set as the baseline.
**Met 2026-11-16**, and better than the baseline: with every test
compiled by `LlvmIR` (and `m3core`/`libm3` by C), **291 of 292 tests
pass** (293 runs), against 266 with the C backend. No test that passes
with C fails with `LlvmIR`. The one failure, p047, fails the same way
with C (its expected output assumes a 64-bit EXTENDED). Run it with:

```sh
cd m3-sys/m3tests
systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 \
  cm3 -DHTML -DM3_BACKEND_MODE=LlvmIR
```

Phase 2 as built:
- `m3-sys/m3tests/src/m3makefile` passes `-DM3_BACKEND_MODE=LlvmIR`
  on to each test's `cm3` (a small marked edit; before it, every test
  was built with the default backend).
- `M3LLVMIR.m3` overrides 133 of the 146 M3CG operations. Besides the
  Phase 2 list it already covers much of Phase 3: floating point
  (`fp128` for EXTENDED), sets, bit fields, nested procedures and
  static links, and `ex_frame` exceptions. Still missing: atomics,
  the `ex_stack` operations (`start_try`, `invoke_*`, `landing_pad`)
  and `init_label`/`init_offset`; see the checklist.
- **Operand stack.** The M3CG stack is simulated at compile time as
  (type, LLVM value) pairs. Variables are allocas; code after an
  unconditional jump goes into a fresh unreachable block.
- **Nested procedures.** Each procedure has a `%frame` block: offset 0
  holds the static link, up-level variables follow. Nested procedures
  take the static link as a trailing `ptr %sl` parameter, so a closure
  call can pass it to any procedure (an extra argument is harmless
  for a top-level callee). The static link for an indirect call goes
  through a memory slot, because the front end pops it on only one
  branch of the closure test. FINALLY handlers are declared with an
  "activation" parameter that the front end's direct call omits;
  `call_direct` passes zero for it.
- **Runtime checks** call `RTHooks__ReportFault(module, code + line*32)`
  as M3C does, then `unreachable`.
- **setjmp.** `_setjmp`/`setjmp`/`sigsetjmp` are declared
  `returns_twice`, and in any procedure that calls one, every load and
  store becomes `volatile` (the C backend's approach, coarse but safe).
- **Sets** are small internal helper functions over 64-bit words, emitted
  once per unit when used; `set_member` and `set_singleton` are inline.
  This is why p156, p159 and p162 pass here and fail with C.
- `DIV`/`MOD` round toward negative infinity; shifts and rotates guard
  out-of-range counts with `select`, so no shift produces poison.
- Several C-backend failures pass with `LlvmIR`: the 10 GCC-warning
  tests (nothing goes through GCC), p053/p160/p109/p269 (C++ the C
  backend can't compile), p137, p227 (integer-multiply semantics),
  p268/p270/p277/p280, and p201, whose "DeclareTypes not progressing"
  error comes from `M3C.m3`, not the front end.
- Not yet tested: `-O2` (`cm3 -O`), and the `c*` and `x0` tests.

### Phase 3: full M3CG coverage

Much of this list was done in Phase 2 (see "Phase 2 as built"); what
remains is atomics, `ex_stack`, the rarely emitted operations, the
`-O2` runs, and building `m3core` and `libm3` with `LlvmIR`.

- Floating point: arithmetic, conversions, `cvt_float`, and rounding.
- Sets (`set_union`, `set_difference`, `set_intersection`,
  `set_sym_difference`, `set_member`, `set_compare`, `set_range`,
  `set_singleton`): call the runtime helpers as M3C does, or inline the
  small fixed-size cases.
- Bit fields: `extract`, `extract_n`, `extract_mn`, `insert*`.
- Nested procedures and static links in full.
- Exceptions with `ex_frame`: correct `setjmp` lowering (`returns_twice`),
  `TRY FINALLY`, `LOCK`, and `RAISE` across procedures.
- Atomics and fences.
- Every remaining item in the operation checklist, including the ones
  that are rarely emitted.

*Exit:* all of `p0`, `p1`, `p2` and `r0` match the C-backend baseline at
both `-O0` and `-O2`. **`m3core` and `libm3` build with `LlvmIR`**, and
the test suite still matches when linked against them.
**Met 2026-11-16, except `ex_stack`.** Every configuration passes 291
of 292 tests (293 runs), as in Phase 2; the one failure, p047, fails
the same way with C:
- tests at `-O2`, with the C-built libraries;
- tests at `-O0`, with `m3core` and `libm3` built by `LlvmIR`;
- tests at `-O2`, with `m3core` and `libm3` built by `LlvmIR` at `-O2`.

```sh
cd m3-sys/m3tests
systemd-run --user --scope -q -p MemoryMax=16G -p MemorySwapMax=0 \
  cm3 -DHTML -DM3_BACKEND_MODE=LlvmIR -DM3TESTS_OPTIMIZE
```

Phase 3 as built:
- `-DM3TESTS_OPTIMIZE` (a small marked edit in
  `m3-sys/m3tests/src/m3makefile`) builds each test with `cm3 -O`, for
  any backend. Under `-O`, `compile_llvm_ir` runs `clang -O2`.
- **`m3core` and `libm3`** (272 and 294 units) build with `LlvmIR` at
  both levels, warning-for-warning like C. Fix needed:
  `index_address` with a negative element size (String8, DragonInt) now
  scales the index with `mul` instead of emitting `[-1 x i8]`.
- **Grisu.** `m3core/src/float/Common/m3makefile` now uses `no_grisu`
  for `LlvmIR` as well as C. Grisu's single-precision path fails its
  own `<*ASSERT*>` (IEEE.m3, `NormalizedBoundaries_S`) with *either*
  backend: the bug is in the source, not the backend. With Grisu,
  p003, p040, p113 and p118 fail.
- How the libraries were tested without touching the real install:
  copy the install to a scratch prefix, build `m3core`/`libm3` with
  `LlvmIR` *using the scratch prefix's `cm3`*, and ship there. A
  package's `.M3SHIP` records absolute install paths at build time, so
  a package built by the real `cm3` ships into the real install no
  matter which `cm3 -ship` runs it. Check `.M3SHIP` before shipping.
- **Atomics** (`store_ordered`, `load_ordered`, `exchange`,
  `compare_exchange`, `fence`, `fetch_and_op`) map to LLVM's
  `store atomic`, `load atomic`, `atomicrmw`, `cmpxchg` and `fence`.
  Orders an instruction doesn't allow are weakened to the nearest
  legal one, and a relaxed fence emits nothing. `compare_exchange`
  follows the front end (`builtinAtomic/CompareSwap.mg`): s1 is the
  *address* of `expected`, which is written only on failure. The C
  backend leaves most of these as empty stubs.
  Nothing upstream uses atomics: `m3core/src/atomic` is disabled, so
  the builtin `Atomic*` interfaces have no exporter, and any program
  that imports them (p226, which is commented out) fails cm3's
  version-stamp check with every backend. They were tested by linking
  a value-checking program by hand, with NULL stubs for the
  `Atomic*_I3` functions: 26 checks over INTEGER, BOOLEAN, CHAR,
  WIDECHAR, LONGINT, ADDRESS and REFANY pass at `-O0` and `-O2`. p226's
  IR verifies. Front-end limits found on the way: an atomic call can't
  be used directly as a boolean operand ("CallExpr.NotBoolean"), and
  `AtomicLongint.FetchInc` with a LONGINT increment crashes the front end.
- `init_label` and `init_offset` are no-ops, as in M3C and M3CG_LLVM:
  only the old stack walker reads those words.
- **Deferred: `ex_stack`** (`start_try`, `end_try`, `invoke_direct`,
  `invoke_indirect`, `landing_pad`). It is off by default, and testing
  it needs an `m3core` built with `M3_USE_STACK_WALKER`, which takes the
  two-stage bootstrap in `README-ex_stack.md`. The lowering would be
  `invoke` to a `landingpad` with `__gxx_personality_v0` that catches
  `_M3Exc` (`RTStackC.c`). It is the `ex_stack` item in Phase 7, and
  must be done before AMD64_LINUX switches its default exception
  model to `ex_stack`.
- Not yet run: the `c*` and `x0` tests.

### Phase 4: self-hosting and performance

- Build the whole compiler (`m3front`, `m3middle`, `m3back`,
  `m3llvmir`, `cm3`) with `LlvmIR`. Use the result to build itself
  again, and check the **fixed point**: the stage 2 and stage 3 compilers
  produce byte-identical `.ll` files for the compiler's own sources.
- Build the full headless package set (`concierge.py ... headless`)
  with `LlvmIR`.
- Measure compile time and code size against the C backend. Profile the
  emitter if it's much slower. The likely costs are text concatenation
  (use `M3Buf`, write directly to a `Wr.T`) and the `clang` process per
  unit.
- Run a few runtime benchmarks at `-O2`, using whatever exists in
  `m3-demo`/`m3-tools`, or small dedicated ones.

*Exit:* a self-hosted compiler at the fixed point, the headless
package set built, and the numbers recorded in `experiment-doc/`.

**Phase 4 as built** (details and numbers in
[`experiment-doc/phase4-results.md`](experiment-doc/phase4-results.md)):

- *Exit met.*
  - **Fixed point:** starting from the C-built compiler, each `LlvmIR`
    stage built the 15 compiler packages with the previous stage's
    `cm3`. All 1,368 `.ll` files are byte-identical between stages, and
    the binaries differ only in the build timestamp.
  - **Headless set:** all 59 packages that concierge installs here
    build with the self-hosted compiler.
  - **m3tests:** the self-hosted compiler, with `LlvmIR`-built
    libraries, passes 292 of 293 (p047 as before).
- Two fixes:
  - `cm3cfg.common` now passes `-unfold_nested_procs -check_procs` for
    `LlvmIR`. Before, only `-DM3_BACKEND_MODE=LlvmIR` on a C config got
    them.
  - REAL constants are rounded to single precision before they're
    written; `arithmetic` failed without this.
- Compared with C, builds are 2 to 2.5 times faster, and `-O0` text is
  20% smaller. Front end plus emitter takes 55% of the C backend's time,
  and `M3LLVMIR` is under 2% of the profile, so the emitter was not
  reworked.
- At `-O2`, the benchmarks run within 10% of `gcc -O2`. Upstream never
  optimizes the C backend's output (`cm3 -O` still runs `gcc -O0`), so
  in practice `LlvmIR -O` is up to 4 times faster than C as shipped.
- The scripts are in `experiment-doc/phase4/`: the staged build, the
  measurement, and the benchmarks.

### Phase 5: debug information

- Line tables first: a `DICompileUnit`, a `DIFile` per source, a
  `DISubprogram` per procedure, and a `!dbg` location on each
  instruction from `set_source_line`. This gets stepping and backtraces
  working in gdb and lldb.
- Then variables and types from the `declare_*` debug operations
  (records, objects, enumerations, arrays, open arrays). Port the
  mapping from `M3CG_LLVM.m3` and `M3DebugInfo`.
- Check with `gdb`: breakpoints by line, `bt`, and printing locals and
  record fields.

*Exit:* a debug build of a `p`-test program can be stepped through, and
its variables can be printed in gdb.

**Phase 5 as built:**

- *Exit met.* p034 (records, fixed arrays, open arrays) is built with
  `LlvmIR` and run under gdb 17:
  - line breakpoints, `next`, `step` and `bt` work;
  - gdb prints records, 2-D arrays, `x1^` of open arrays, and the
    loop variables;
  - locals of the separate `VAR ... BEGIN` blocks that share a name
    (`w1`, `x1`) resolve to the right block.

  A larger test program, kept outside the tree, also covers:
  - VAR record and open-array parameters;
  - enumerations, sets (`{Red, Blue}`), BOOLEAN, CHAR and bit-packed
    fields;
  - objects with inheritance (`c^`, `c.radius`);
  - module globals, and `finish` printing the returned value.
- **Structure.** The new module `M3LLVMIRDebug` holds the metadata
  writer.
  - `M3LLVMIR` forwards the `declare_*` type operations to it.
  - DI type nodes are made lazily, when a variable or procedure first
    refers to a type, so recursive types work.
  - Subprograms, variables and globals are defined at `end_unit`, after
    the function bodies.
- **What is emitted:**
  - a `DICompileUnit` and a `DIFile` per source;
  - a `DISubprogram` per defined procedure, with its signature;
  - a `DILocation` on every instruction, and a `DILexicalBlock` per
    `begin_block`;
  - `llvm.dbg.declare` for named locals and parameters, with
    `DW_OP_deref` for VAR and by-reference parameters;
  - a `DIGlobalVariableExpression` for each field of the module's
    global record.
- **Types described:**
  - basic types, subranges (unsigned when the minimum is at least 0),
    and enumerations with an unsigned base type;
  - arrays, open arrays (through `dataLocation` and `upperBound`
    expressions on the dope vector), packed types and bit fields;
  - records, sets, pointers, procedure types;
  - objects and opaque types, as pointers to class structs with
    `DW_TAG_inheritance`.
- **The language is `DW_LANG_Modula2`.** gdb treats Modula-3 as a
  minimal language: it can't print sets ("Unhandled type code"), and it
  prints BOOLEAN and byte-sized subranges as C would. In Modula-2 mode,
  sets, TRUE/FALSE and `POINTER TO` print properly, and `p^`, `a[i]`
  and `r.f` parse. Qualified enumeration literals such as `Color.Blue`
  don't parse.
- **No `.debug_names`.** The compile unit sets `nameTableKind: None`.
  ld.gold concatenates the per-unit tables instead of merging them, and
  gdb then rejects the section with a warning.
- **Switching it on.** Debug information follows cm3's `-g`/`-g0`.
  Builder passes `env.source_unit.debug` to `M3Backend.Open`, and from
  there to `M3LLVMIR.New`. This adds one marked parameter to each, and
  `compile_llvm_ir` already gives clang `-g`. `m3llir -g` turns debug
  information on in the standalone driver.
- **Checked:**
  - all corpus units pass `llvm-as` and `llvm-dwarfdump --verify` with
    `-g`;
  - m3tests with `-DM3_BACKEND_MODE=LlvmIR`, which now has debug
    information on by default, still passes 292 of 293 (p047, as
    before).
- **Follow-ups, done after the Phase 5 commit:**
  - **Methods.** Each object's class struct has an artificial
    `_methods` member at offset 0, a pointer to a `T_methods` struct
    (the method suite). The suite inherits its supertype's suite and
    holds the type's new methods as procedure pointers, at the front
    end's `method_offset`. The suite pointer points at slot 0, and the
    slots follow declaration order, so `p o^._methods^` shows which
    procedure each method is bound to. Objects whose method offset is
    unknown (opaque supertypes) get no `_methods`.
  - **`_result` is hidden.** The front end's temporary for a function
    result is no longer described.
  - **The module body returns ADDRESS.** The front end gives `Main_M3`
    no result typeid; when the procedure returns an address, the
    debug information now says ADDRESS.
  - **TEXT and procedure pretty-printers for gdb.**
    [`m3printers.py`](m3-sys/m3llvmir/src/m3printers.py) is bundled
    into the backend and embedded in every unit with debug information,
    as an inline script in `.debug_gdb_scripts` (a `linkonce_odr`
    COMDAT kept by `@llvm.used`, so a program gets one 9 KB copy).
    - TEXT is now a typedef named `TEXT`. The printer finds the
      representation (`Text8`, `Text16`, `Text8Short`, `Text16Short`,
      `Text8CString`, `TextCat`, `TextSub`, literals) from the symbol in
      the `get_info` slot of the text's method suite, decodes it, and
      prints `"abc"`, `W"..."` for wide texts, or `NIL`. It honors
      `set print elements`; `p/r` shows the pointer.
    - gdb's Modula-2 printer shows a procedure pointer's own address
      instead of its value (`p/a` is right). In Modula-2 frames the
      script prints procedure values as `0x401000 <Main__CircleArea>`.
    - gdb runs embedded scripts only from files under `auto-load
      safe-path`, whose default doesn't cover user programs. Add
      `add-auto-load-safe-path DIR` to `~/.gdbinit`, or `source` the
      script.
    - The layouts are copied from `m3core/src/text`; the script must
      follow changes there.
  - **lldb (22.1.8).** Breakpoints (by symbol and by file:line), `bt`,
    stepping, `finish` and source display work. Variables and types
    don't: lldb has no plugin for `modula2`, so `frame variable` shows
    nothing ("This version of LLDB has no plugin for the language").
    With the compile unit relabeled `DW_LANG_C99` by hand, lldb shows
    everything: locals, objects with their inheritance and `_methods`,
    and the method procedures.
  - **Choosing the DWARF language.** `cm3 -DM3_DEBUG_LANGUAGE=C` (or
    `M3_DEBUG_LANGUAGE = "C"` in the config) makes the compile units
    claim DW_LANG_C99, for lldb; `Modula2`, the default, suits gdb.
    `m3llir -l C` does the same. The setting is
    `M3LLVMIRDebug.SetLanguage`, which `Builder` calls when it reads
    the backend mode (a small, marked edit).
    - C has no sets, and gdb's C mode can't print `DW_TAG_set_type`
      ("Unhandled type code 11"), so in a C unit a set is a struct
      with a one-bit BOOLEAN member per element, named after the
      enumeration element (`_5` or `_m5` for integer domains): gdb
      prints `{Red = true, Green = false, Blue = true}`. Sets of more
      than 1024 elements stay opaque. The bit layout assumes a
      little-endian target.
    - Under C, gdb prints BOOLEANs as `true`/`false` and objects with
      `->`; the TEXT printer works the same.
    - `m3tests` forwards `-DM3_DEBUG_LANGUAGE` to each test with
      `-DM3_BACKEND_MODE=LlvmIR`. Both labels pass 292 of 293 (p047, as
      before), and the IR corpus passes `llvm-dwarfdump --verify` with
      both (`m3llir -g -l Modula2` and `-l C`).
  - **TEXT formatter for lldb.** The decoding in `m3printers.py` is
    now a class, `TextDecoder`, that doesn't use gdb (the file
    imports `gdb` only if it can).
    [`m3lldb.py`](m3-sys/m3llvmir/src/m3lldb.py) imports it and adds a
    summary for the `TEXT` typedef, limited by
    `target.max-string-summary-length`. lldb doesn't run embedded
    scripts; load it with `command script import .../m3lldb.py`
    (keeping `m3printers.py` beside it). With a C unit, `frame
    variable` shows texts, sets, enumerations, BOOLEANs and objects.
- **Not done** (moved to later phases):
  - exceptions and RAISES are not described (Phase 7, with
    `ex_stack`);
  - `m3lldb.py` is not installed anywhere; it is loaded from the
    source tree (done in Phase 6).

### Phase 6: integration and CI

- Add `--backend llvmir` to `concierge.py`. Check that `clang` exists
  and meets the minimum version, then build with `LlvmIR` throughout.
- Make the AMD64_LINUX config allow `LlvmIR` as an alternative default.
- Add a GitHub Actions job (based on `amd64_linux.yml`) that installs
  distribution LLVM packages for the minimum and newest versions, builds
  with `LlvmIR`, and runs `m3tests`, verifying every emitted `.ll`.
- Install the debugger scripts: ship `m3lldb.py` with `m3printers.py`
  beside it (gdb gets `m3printers.py` embedded in each unit, but lldb
  has to load a file), and point the documentation's `~/.lldbinit`
  line at the installed copy. (From Phase 5.)
- Write user and developer documentation, linked from `AGENTS.md`.

*Exit:* CI is green on two LLVM versions.

**Phase 6 as built:**

- *Exit met.* The `integration` run for e564f1996 (run 43962787893)
  is green, both `LlvmIR` jobs (LLVM 18 on Ubuntu 24.04, LLVM 22 on
  Ubuntu 26.04) included. Getting there took the build-order fix and
  the runner change below, and e041 as a known failure. One upstream
  job, AMD64_NT, failed once with a flaky crash of the Windows
  bootstrap compiler (`suspend_cnt = 0` in `ThreadWin32.m3`, then a
  stack overflow) and passed when rerun.
- **concierge.** `--backend llvmir` (or `-llvmir`) is accepted by every
  command and falls back to C on targets other than AMD64_LINUX.
  - `check_clang` fails unless `clang` on `PATH` reports version 18 or
    later.
  - `upgrade` and `full-upgrade` (`_doLlvmIR`) build the front packages
    once with C, because the installed cm3 (a bootstrap, say) may
    predate `LlvmIR`, and then twice with `LlvmIR`, so the second pass
    uses an `LlvmIR`-built cm3.
  - The installed `cm3.cfg` starts with `M3_BACKEND_MODE = "LlvmIR"`.
  - Package builds get `-DM3_BACKEND_MODE=LlvmIR`.
- **Config.** `AMD64_LINUX` keeps C as its default and documents
  `LlvmIR` as the alternative: `cm3.cfg` (as concierge writes it) or
  `-DM3_BACKEND_MODE=LlvmIR`.
- **IR verification.** With `M3_LLVM_IR_VERIFY` set in the environment,
  `compile_llvm_ir` (`Unix.common`) first runs `llvm-as -o /dev/null`
  on the `.ll`. clang 22 verifies IR input itself; this makes sure the
  check also happens with older clangs.
  - It uses `exec`, not `try_exec`. Under the parallel back end
    (`M3_PARALLEL_BACK = 20` in `AMD64.common`), quake records each
    back-end command as a promise, and `try_exec` promises ignore
    their exit status. A failing `try_exec` therefore doesn't stop the
    build; an `exec` failure does, as "quake error in parallel build".
    Tested with a fake `llvm-as` that always fails, both with
    `M3_PARALLEL_BACK = 20` and with 1.
  - The same thing hides clang failures in `compile_llvm_ir`, and in
    upstream's `compile_c`: with the parallel back end, a failed
    compile shows up only when the link can't find the object. This is
    upstream behavior and has been left alone.
- **Debugger scripts.** The `m3llvmir` `m3makefile` installs
  `m3printers.py` and `m3lldb.py` in `INSTALL_ROOT/share/m3llvmir`
  with `RootExport`. `m3lldb.py` imports `m3printers.py` from its own
  directory, so the installed pair works as is. The documentation now
  points `~/.lldbinit` at the installed copy.
- **CI.** `.github/workflows/amd64_linux_llvmir.yml`, called from
  `integration.yml` and also runnable by hand:
  - a matrix over LLVM 18, on Ubuntu 24.04, and 22, on
    `ubuntu-latest`, each from the distribution's archive if it has
    the version and else from apt.llvm.org (which has no LLVM 18 for
    Ubuntu 26.04, the current `ubuntu-latest`), with
    `/usr/lib/llvm-N/bin` first on `PATH`;
  - the d5.12.0 bootstrap, then `concierge.py full-upgrade --backend
    llvmir` with the package set of upstream's AMD64_LINUX job;
  - a check that the installed `cm3.cfg` defaults to `LlvmIR`;
  - m3tests (using that default), reported with `dorny/test-reporter`,
    and a final step that fails on any test failure not listed in
    `KNOWN_FAILURES`, tests that fail with C too: p047, and e041. On
    e041 the front end crashes with a segmentation fault, whatever
    the backend: its mutually recursive REVEALs overflow the stack.
    Under bash (Fedora's `/bin/sh`) the shell reports the crash on its
    own stderr, so the test passes; under dash (Ubuntu's) the message
    lands in the captured stderr and the test fails. Upstream's C job
    on Ubuntu fails e041 too, along with 14 other tests (and p047)
    that `LlvmIR` passes;
  - `M3_LLVM_IR_VERIFY=1` for the whole job.
- **Build order.** The first CI run showed that the Phase 5 bundle of
  `m3printers.py` broke every fresh build, upstream's jobs included:
  `scripts/pkginfo.txt` listed `m3llvmir` before `m3bundle`, which a
  bootstrap install doesn't have yet. `m3llvmir` now comes after
  `m3bundle` (and `mklib`).
- **Documentation.** [`m3-sys/m3llvmir/README.md`](m3-sys/m3llvmir/README.md)
  (using the backend: choosing it, optimization, overriding the clang
  step, `m3llir`, gdb and lldb, troubleshooting) and
  [`HACKING.md`](m3-sys/m3llvmir/HACKING.md) (the file map, how the
  emitter works, rules for the IR, testing, CI), linked from
  `AGENTS.md`.
- **Results (local, Fedora, clang 22, on a copy of the installation):**
  - `full-upgrade --backend llvmir` succeeds, and the installed
    `cm3.cfg` selects `LlvmIR`.
  - With `M3_LLVM_IR_VERIFY=1`, the CI package set (about 170
    packages, including the GUI libraries and applications) builds and
    ships with `LlvmIR`, and every `.ll` passes `llvm-as`. The
    exception is `llvm22bindings`, whose shared library doesn't link
    on this machine with either backend (gold finds 32-bit libraries
    in `/lib`); upstream CI builds it on Ubuntu.
  - m3tests, with `LlvmIR` as the installed default and verification
    on: 292 of 293 pass (p047 fails, as with C), and the CI workflow's
    check of the results passes.
- **Results in CI (Ubuntu, LLVM 18 and 22):** the full build passes,
  with every `.ll` verified, and m3tests passes 291 of 293 (p047 and
  e041, as above).

### Phase 7: beyond AMD64_LINUX and the basics

Ordered by expected value. Each item is a separate mini-plan.

- **ARM64_LINUX.** This should be mostly the triple, datalayout and
  ABI details (by-value structs, varargs if any). It's the cheapest
  check that the backend isn't accidentally x86-specific.

  *Done (on a Raspberry Pi 400: aarch64, Debian 13, 4 GB RAM,
  clang 19, GCC 14).* The backend needed only the triple and datalayout
  (`TargetTriple`, `DataLayout`); concierge's `has_llvmir_backend`
  needed ARM64_LINUX too. Nothing else was x86-specific: EXTENDED is
  `double` off AMD64_LINUX, the jmp_buf's size comes from m3core at run
  time, structures are passed by pointer, and there are no variadic
  calls. d5.12.0 has no ARM64_LINUX bootstrap, so one was made with
  `concierge.py make-bootstrap --target ARM64_LINUX`, which needed a
  `CMakeLists.txt` and `m3overrides` entries for m3llvmir (cm3 imports
  it). The Pi also needed `binutils-gold` (Linux.common links with
  gold; Debian 13 doesn't install it) and, for the GUI packages,
  `xorg-dev` and `libglu1-mesa-dev`.

  Results: `full-upgrade --backend llvmir -g0 all -caltech-other
  -caltech-parser -m3-scheme` (CI's arguments, with
  `M3_LLVM_IR_VERIFY=1`) builds everything, self-hosting included, and
  m3tests passes 291 of 293 (p047 and e041), as on AMD64_LINUX. With
  the C backend m3tests fails 16 (those two and p053 p109 p137 p156
  p159 p160 p162 p201 p227 p268 p269 p270 p277 p280), the same 16 as
  upstream's C job on Ubuntu; with GCC 14 the C backend's output fails
  to compile (p053: "`SET` was not declared") or misbehaves (p137:
  "LONGINT value check failed"). Still to do: a CI job (on
  `ubuntu-24.04-arm`).
- **Darwin targets** (AMD64 and ARM64).
- **Zero-cost exceptions (`ex_stack`)** through `invoke`/`landingpad`
  with the C++ personality, interoperating with `RTStackC.c`. See
  `README-ex_stack.md`. The old LLVM backend's `invoke_direct` and
  `landing_pad` are the starting reference.
- **Debug information for exceptions** (from Phase 5): describe
  exception declarations and procedures' RAISES sets in the DWARF.
  Design it together with `ex_stack`, which decides how exceptions are
  represented at run time.
- Optimization work: function attributes (`nounwind`, `noalias` where
  the front end guarantees it, `nonnull`), cheap loop and alias hints,
  and possibly LTO through `clang -flto`.
- Precise GC (statepoints or stack maps), only if conservative scanning
  becomes a real limitation.
- Decide the future of the library-linked `m3llvm`: keep it,
  deprecate it, or propose the text emitter upstream as a replacement.

## Testing strategy, summarized

- **Differential testing against the C backend** is the main oracle.
  Same test, two backends: the outputs must match.
- **IR validity**: run every `.ll` through `opt -passes=verify` in the
  test harness. A verifier error is always our bug.
- **Golden IR tests** through the standalone driver: small M3CG inputs
  with expected `.ll` output, for operations that are easy to get
  subtly wrong (shifts, `DIV`/`MOD`, `extract`/`insert`, set operations,
  `case_jump`).
- **Mixed linking**: some packages built with C and some with `LlvmIR`,
  to keep the ABI honest.
- **Optimization levels**: run every suite at `-O0` and `-O2`. Bugs that
  only appear at `-O2` usually mean undefined behavior in the emitted
  IR, such as poison or a missing `returns_twice`.
- **Bisecting a miscompile**: dump `.ll` files with `-keep`, then
  compare individual units between backends by mixing them.
- **Prior art for the harness: Hostess**, the Oberon compiler test
  suite from oo2c (hostess.sourceforge.net), with a local copy in
  `/usr/local/sw/src/lang/Oberon/hostess`; oo2c's runner for it is in
  `/usr/local/sw/src/lang/Oberon/oo2c/src/OOC/TestFramework/` and
  `rsrc/OOC/TestFramework/`. Two of its ideas fit problems the m3tests
  baseline already shows:
  - *Typed outcomes.* Each test is declared in XML as `reject`
    (must fail to compile), `accept` (must compile), `error` (must
    compile and then raise at run time) or `run` (must compile and run
    cleanly, optionally matching a `.Ref` output file). m3tests instead
    diffs `stderr.build` byte for byte, so a new compiler warning
    counts as a failure (10 of the 27 baseline failures). Judging
    `LlvmIR` by outcome, and diffing program output only, avoids
    that.
  - *Calibrating the harness.* Its `baseline-testcases.xml` holds
    tests that must pass and tests that must fail, to show that the
    framework gives neither false passes nor false failures. The
    differential harness should have the same: known-bad `.ll` that
    the verifier must reject, and a deliberately wrong program whose
    output must be reported as a mismatch.
  Don't reuse its code (Oberon, Java/Xalan for the reports); borrow
  the test-description format if it fits. The test-type ideas also
  belong in the later build and test simplification work.

## Risks

- **M3CG has undocumented contracts** that only the existing backends
  encode, such as operand-stack typing quirks, the ordering of nested
  procedures, and when `widen`/`chop` appear. Mitigation: run
  `M3CG_Check` in front of the emitter in debug mode, and read both
  reference backends before implementing each operation family.
- **Undefined behavior in the emitted IR** that works at `-O0` and
  breaks at `-O2`. Mitigation: testing at both levels, plus the
  semantics list in design decision 8.
- **IR syntax drift between LLVM versions.** Mitigation: keep printing
  in one place, and test the minimum and the newest LLVM in CI.
- **Compile-time cost** of text output plus a `clang` process per unit.
  Mitigation: measure in Phase 4. Batching several units per `clang`
  call is possible if needed.
- **Upstream churn** in `m3front`/`M3CG` (for example, new operations
  such as the recent `ex_stack` ones). Mitigation: merge upstream
  regularly. Unimplemented operations fail loudly through
  `M3CG_AssertFalse`.

## Out of scope for this plan

The build-system simplification (bootstrap, `cm3.cfg`, quake) is the
fork's second goal. It gets its own plan once the backend reaches
Phase 4. One relevant fact for that plan: the text-IR backend adds no
build-time dependency beyond a `clang`, which is no more than the C
backend already requires.
