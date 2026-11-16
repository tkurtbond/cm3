# Plan: an LLVM backend for cm3 that emits textual LLVM IR

Status: draft, 2026-11-16. Phases 0, 1 and 2 are done; Phase 3 is next.

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
  libraries. Only AMD64_LINUX has a triple and datalayout so far.
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

### Phase 6: integration and CI

- Add `--backend llvmir` to `concierge.py`. Check that `clang` exists
  and meets the minimum version, then build with `LlvmIR` throughout.
- Make the AMD64_LINUX config allow `LlvmIR` as an alternative default.
- Add a GitHub Actions job (based on `amd64_linux.yml`) that installs
  distribution LLVM packages for the minimum and newest versions, builds
  with `LlvmIR`, and runs `m3tests`, verifying every emitted `.ll`.
- Write user and developer documentation, linked from `AGENTS.md`.

*Exit:* CI is green on two LLVM versions.

### Phase 7: beyond AMD64_LINUX and the basics

Ordered by expected value. Each item is a separate mini-plan.

- **ARM64_LINUX.** This should be mostly the triple, datalayout and
  ABI details (by-value structs, varargs if any). It's the cheapest
  check that the backend isn't accidentally x86-specific.
- **Darwin targets** (AMD64 and ARM64).
- **Zero-cost exceptions (`ex_stack`)** through `invoke`/`landingpad`
  with the C++ personality, interoperating with `RTStackC.c`. See
  `README-ex_stack.md`. The old LLVM backend's `invoke_direct` and
  `landing_pad` are the starting reference.
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
