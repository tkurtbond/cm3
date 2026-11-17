# The LlvmIR back end: developer guide

How the back end is put together, how to change it, and how to test
it. For using it, see [`README.md`](README.md). The design decisions
and the record of each phase are in [`PLAN.md`](../../PLAN.md);
[`AGENTS.md`](../../AGENTS.md) has the repository map and build
commands.

## Where things are

| Path | What it is |
|------|------------|
| `m3-sys/m3llvmir/src/M3LLVMIR.m3` | The emitter: an `M3CG_AssertFalse` subtype that implements the M3CG operations and writes textual LLVM IR. |
| `m3-sys/m3llvmir/src/M3LLVMIRDebug.m3` | DWARF debug information, written as LLVM metadata. |
| `m3-sys/m3llvmir/src/m3printers.py` | gdb pretty-printers (TEXT, procedure values), bundled into the back end (`M3LLVMIRBundle`) and embedded in every unit with debug information. Its `TextDecoder` class doesn't need gdb. |
| `m3-sys/m3llvmir/src/m3lldb.py` | lldb TEXT formatter; imports `TextDecoder` from `m3printers.py`. Both scripts are installed in `INSTALL_ROOT/share/m3llvmir/` (`RootExport` in the `m3makefile`). |
| `m3-sys/m3llir/` | `m3llir`, the standalone driver: M3CG file in, `.ll` out. |
| `m3-sys/cm3/src/M3Backend.m3` | Makes the code generator for mode `LlvmIR` (`M3LLVMIR.New`). |
| `m3-sys/cm3/src/Builder.m3` | Runs it, names the output `Foo.m3.ll`, calls `compile_llvm_ir`, and reads `M3_DEBUG_LANGUAGE`. |
| `m3-sys/m3middle/src/Target.i3` | `M3BackendMode_t.LlvmIR`, appended to the enum. |
| `m3-sys/cminstall/src/config/Unix.common` | `LLVM_IR_CC`, `compile_llvm_ir`, and the `M3_LLVM_IR_VERIFY` check. |
| `m3-sys/cminstall/src/config/cm3cfg.common` | Front-end flags for `LlvmIR` (`-unfold_nested_procs -check_procs`). |
| `scripts/concierge.py` | `--backend llvmir`: the clang check, the C-then-LlvmIR bootstrap (`_doLlvmIR`), and the `cm3.cfg` default. |
| `.github/workflows/amd64_linux_llvmir.yml` | CI: LLVM 18 and the newest LLVM; full build, m3tests, IR verification; also with ex_stack and at `-O2`. |
| `experiment-doc/m3cg-ops-checklist.md` | Which M3CG operations are implemented. |
| `experiment-doc/m3cg-corpus/` | Saved ASCII M3CG units for quick tests with `m3llir`. |
| `experiment-doc/phase4-results.md`, `phase4/` | Self-hosting, timing and benchmark scripts and numbers. |

Changes to shared files (`Builder.m3`, `M3Backend.m3`, `Target.i3`,
the configs) are small and marked `(* LLVM IR backend *)` or with a
comment naming the phase, so merges with upstream stay easy. Keep it
that way: new code goes in `m3llvmir`.

## How the emitter works

M3CG is a stack machine; `M3LLVMIR.m3` follows the C back end's shape
(an object that writes text) and ports lowering decisions from the
library-based `m3-sys/llvm/llvm22/src/M3CG_LLVM.m3`. The file is in
sections, marked by `(*--- name ---*)` comment rules:
targets, utilities, instructions and stack, unit, globals,
initializers, procedures, control flow, loads and stores, calls,
faults, floating point, arithmetic, sets, bit operations, copying,
conversions, runtime checks, address arithmetic, indirect calls,
static data, atomics.

- **Operand stack.** A compile-time stack of `Operand`s (an LLVM type
  and a value: a `%tN` temporary or a constant). Each operation pops
  its operands with `Pop`/`PopAs`, emits instructions with `Emit` or
  `Instr` (which returns a fresh `%tN`), and pushes its result with
  `Push`. Temporaries are never reused.
- **Variables live in memory.** Locals and parameters get `alloca`
  slots in the entry block; globals are LLVM globals. There is no SSA
  construction: `mem2reg` at `-O1` and above cleans up, and
  conservative GC stack scanning keeps working.
- **Nested procedures** (`LProc` with a parent): uplevel-referenced
  locals live in a frame struct in the owner, reached through a static
  link passed as an extra leading `ptr` (`FrameOf`, `InFrame`). The
  front end is run with `-unfold_nested_procs`, so the bodies arrive
  one at a time.
- **Buffers.** Each procedure's body is buffered and written at
  `end_procedure`; declarations, helper functions (`AddHelper`, for
  example set operations and `fp128` support) and globals are
  collected and written at `end_unit`, together with the debug
  metadata. Textual IR allows forward references at module scope, so
  one pass suffices.
- **Data segments** (`declare_segment`, `init_*`) become one global
  per segment with a packed-struct initializer `<{ ... }>`, padded
  with `[N x i8] zeroinitializer`.
- **Semantics that differ from LLVM's** are handled explicitly:
  shifts and rotates by large or negative counts, `DIV`/`MOD`
  rounding, variable bit-field extract/insert, `noreturn cold` fault
  procedures, `returns_twice` on `setjmp`, `fp128` for EXTENDED, and
  atomics with explicit memory orders. PLAN.md's design decision 8
  lists them; the C back end (`m3-sys/m3back/src/M3C.m3`) is the
  reference for what the result must be.
- **Zero-cost exceptions** (`ex_stack`, PLAN.md Phase 7): between
  `start_try` and `end_try`, `EmitCall` turns every call that can
  raise (including `ReportFault`) into an `invoke` that unwinds to the
  region's landing pad. `landing_pad` starts that block: a
  `landingpad` that catches the C++ `_M3Exc` (typeinfo `_ZTI6_M3Exc`,
  thrown by `RTStack__ThrowM3Exc` in `RTStackC.c`), then
  `__cxa_begin_catch`/`__cxa_end_catch`, and pushes the activation.
  Such procedures get `personality ptr @__gxx_personality_v0`.
- **Targets.** `TargetTriple` and `DataLayout` know AMD64_LINUX and
  ARM64_LINUX; a new target starts there (PLAN.md, Phase 7). Little
  else depends on the target: EXTENDED is `fp128` (with libquadmath's
  `llroundq`, `floorq`, `ceilq`) only on AMD64_LINUX and `double`
  elsewhere (`Target.Init`); the jmp_buf's size comes from m3core at
  run time (`m3_jmpbuf_size`); structures are passed by pointer; and
  the backend emits no variadic calls, inline asm or target
  intrinsics.

Rules for the IR:

- **Opaque pointers only** (`ptr`); never typed pointers.
- **LLVM 18 is the minimum.** Use only instructions, intrinsics and
  attributes that LLVM 18 already accepts; CI checks 18 and the newest
  version. Gate anything newer on a version.
- Every instruction carries `!dbg` when debug information is on; a
  call without a location inside a function with a `DISubprogram`
  fails verification.

### Debug information

`M3LLVMIR` forwards the `declare_*` type operations to
`M3LLVMIRDebug`, which records them and makes DI type nodes lazily,
when a variable or procedure first refers to a type (so recursive
types work). Subprogram, variable and global nodes are numbered when
needed and defined in `Finish`, at `end_unit`. The compile unit's
language is `M3LLVMIRDebug.language` (Modula-2 by default; C for
lldb). The layout knowledge in `m3printers.py` is copied from
`m3-libs/m3core/src/text/` and must follow changes there.

## Building and testing

After changing `m3llvmir` (or `m3middle`, `m3front`, `cm3`), rebuild
and reinstall the compiler: `scripts/concierge.py upgrade`, or build
and ship the packages in dependency order and rebuild `cm3`. cm3
doesn't recompile units when the compiler changes, so remove the
`AMD64_LINUX` directory of whatever you test with.

The fast loop doesn't need a new compiler at all: rebuild only
`m3llir` and run it on saved IR.

```sh
cd m3-sys/m3llvmir && cm3 && cd ../m3llir && cm3
for f in ../../experiment-doc/m3cg-corpus/*.mc.txt; do
  AMD64_LINUX/m3llir -a -g -t AMD64_LINUX "$f" -o /dev/stdout |
    llvm-as -o /dev/null || echo "FAIL $f"
done
```

(`experiment-doc/gen_m3cg_corpus.sh` regenerates the corpus.) Add
`llvm-dwarfdump --verify` on the object file when touching debug
information.

The full checks, roughly in order of cost:

1. **One package or test program:** `cm3 -DM3_BACKEND_MODE=LlvmIR
   -keep -commands`, then look at `AMD64_LINUX/Foo.m3.ll`. Set
   `M3_LLVM_IR_VERIFY=1` in the environment to run `llvm-as` on every
   `.ll` before clang sees it.
2. **m3tests:** `cd m3-sys/m3tests && cm3 -DHTML
   -DM3_BACKEND_MODE=LlvmIR` (add `-DM3TESTS_OPTIMIZE` for `-O`,
   `-DM3_DEBUG_LANGUAGE=C` for C-labeled debug information). Expect
   292 of 293; p047 fails with the C back end too
   (`experiment-doc/m3tests-baseline-c.md`). Run a subset while
   iterating.
3. **Self-hosting:** `experiment-doc/phase4/` builds the compiler in
   stages and checks that the stages' `.ll` files are identical.
4. **The whole tree with `LlvmIR` as default:** what CI does. Don't do
   this to your real installation; copy it:

   ```sh
   W=/usr/local/sw/tmp/<your-dir>
   cp -a /usr/local/sw/versions/cm3/git $W/inst
   rsync -a --exclude=.git --exclude='/**/AMD64_LINUX/' . $W/src/
   cd $W && PATH=$W/inst/bin:$PATH \
     python3 $W/src/scripts/concierge.py full-upgrade --backend llvmir
   ```

   (The `/**/AMD64_LINUX/` pattern skips build directories but keeps
   the config file `m3-sys/cminstall/src/config/AMD64_LINUX`.)

Debugging with gdb and lldb is described in [`README.md`](README.md);
check debug-information changes in both.

## CI

`.github/workflows/amd64_linux_llvmir.yml` is called from
`integration.yml` and can be started by hand (`workflow_dispatch`).
For LLVM 18 (on Ubuntu 24.04, from its archive) and the newest LLVM
(on `ubuntu-latest`, from its archive or else apt.llvm.org), it
builds the bootstrap release, runs `concierge.py full-upgrade
--backend llvmir` on the same package set as upstream's AMD64_LINUX
job, checks that `cm3.cfg` defaults to `LlvmIR`, and runs m3tests. The
environment sets `M3_LLVM_IR_VERIFY`, so every `.ll` of the build and
of the tests goes through `llvm-as`. The last step fails on any test
failure not listed in `KNOWN_FAILURES`. When a new LLVM is released,
bump the newest version in the matrix. Two more jobs, with the newest
LLVM, turn on ex_stack (by uncommenting `M3_USE_STACK_WALKER` in the
source config) and build everything and the tests at `-O2`
(`concierge.py ... -O2`, `cm3 -DHTML -DM3TESTS_OPTIMIZE`).

`m3llvmir` bundles `m3printers.py` with `m3bundle`, so in
`scripts/pkginfo.txt`, which sets concierge's build order, it must
come after `m3bundle`. A fresh bootstrap install has no `m3bundle`.
