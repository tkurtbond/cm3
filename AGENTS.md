# AGENTS.md

Guidance for coding agents (and humans) working in this repository.

## What this fork is for

This is a fork of [modula3/cm3](https://github.com/modula3/cm3), the
Critical Mass Modula-3 compiler, runtime, and libraries. The fork has
two goals, in this order:

1. **An LLVM backend that emits textual LLVM IR** (`.ll` files) and
   hands them to the system's `clang`/`llc`, instead of linking against
   LLVM's libraries. See [`PLAN.md`](PLAN.md) for the phased plan.
2. **Later, a simpler build and install story** for cm3 (bootstrap,
   `cm3.cfg`, the quake layering). This is not started; don't make
   build-system changes unless a task asks for them.

Background and motivation:
[`experiment-doc/modula3-build-llvm-64bit-discussion.md`](experiment-doc/modula3-build-llvm-64bit-discussion.md).

Outside this repository: the Hostess Oberon compiler test suite, in
`/usr/local/sw/src/lang/Oberon/hostess` (the oo2c driver for it is in
`/usr/local/sw/src/lang/Oberon/oo2c`), is prior art for the test
harness; see "Testing strategy" in `PLAN.md`.

Keep changes **additive and easy to merge with upstream**: put new code
in new packages or modules, append to enums rather than reordering
them, and keep edits to shared files (`Builder.m3`, `M3Backend.m3`,
`Target.i3`, config files) small and clearly marked.

## Repository map (the parts that matter for the backend)

| Path | What it is |
|------|------------|
| `m3-sys/m3front/` | Front end: parser, type checker. Emits code through the M3CG interface. Don't modify it for backend work unless unavoidable. |
| `m3-sys/m3middle/src/M3CG_Ops.i3` | **The M3CG interface**: the stack-machine operations every backend implements. This is the contract the new backend must honor. |
| `m3-sys/m3middle/src/M3CG_*.m3` | M3CG utilities: `M3CG_BinWr`/`M3CG_BinRd` (binary IR files), `M3CG_Wr`/`M3CG_Rd` (ASCII IR), `M3CG_Check` (stack/type checker), `M3CG_MultiPass` (record and replay), `M3CG_Tee`. |
| `m3-sys/m3middle/src/Target.i3` | Target description and `M3BackendMode_t`, the enum of backend modes. |
| `m3-sys/m3back/src/M3C.m3` | **The C backend** (about 8,300 lines). It is the default on AMD64_LINUX. It is the closest structural template for a text-emitting backend and the reference oracle for testing. |
| `m3-sys/m3llvmir/src/M3LLVMIR.m3` | **This fork's backend** (backend mode `LlvmIR`): an M3CG_Ops subtype of `M3CG_AssertFalse` that writes textual `.ll`. Unimplemented operations fail with an assertion; progress is tracked in `experiment-doc/m3cg-ops-checklist.md`. `M3LLVMIRDebug.m3` writes the DWARF debug metadata (Phase 5). Documentation: [`m3-sys/m3llvmir/README.md`](m3-sys/m3llvmir/README.md) (using it) and [`HACKING.md`](m3-sys/m3llvmir/HACKING.md) (working on it). |
| `m3-sys/m3llir/` | Standalone driver: `m3llir [-a] [-g] [-l LANG] [-t TARGET] [-o out.ll] in.mc` translates an M3CG file (`-a` for ASCII, `-g` for debug info, `-l C` to label it C for lldb) to `.ll`. Handy with the IR corpus: `m3llir -a -t AMD64_LINUX X.mc.txt \| llvm-as -o /dev/null`. |
| `m3-sys/llvm/llvm22/src/M3CG_LLVM.m3` | **The existing LLVM backend** (about 7,100 lines, by Peter McKinna and Rodney Bates). It uses LLVM's C API through bindings in `llvm22bindings`, runs as a standalone `m3llvm` executable, and needs LLVM's libraries at build time. Use it as the main reference for *how to lower* M3CG to LLVM, but don't add dependencies on it. `llvm13/` and `llvm18/` are older copies. |
| `m3-sys/cm3/src/Builder.m3` | The build driver: dispatches on backend mode (`CompileM3llvm`, `CompileLlc`, `RunM3Llvm`, `RunLlcBack`, and so on). |
| `m3-sys/cm3/src/M3Backend.m3` | Constructs the in-process code generator for a backend mode (`M3C.New` for C). |
| `m3-sys/cminstall/src/config/` | Per-platform quake config. `Unix.common` defines the `m3llvm`, `llvm_backend` (llc) and `llvm_opt` procs. `AMD64_LINUX` selects the backend mode. |
| `m3-sys/m3tests/` | Compiler test suite: `p*` program tests (expected output), `r0` runtime-error tests, `e0` static-error tests, `c*` code tests, `x0` manual tests. |
| `m3-sys/m3cgcat/` | Converts between binary and ASCII M3CG IR. Useful for inspecting what the front end emits. |
| `scripts/concierge.py` | The installer and build driver (`install`, `upgrade`, `full-upgrade`, `--backend c|gcc|integrated|llvm|llvmir`). `--backend llvmir` checks for clang 18+, builds the compiler with C and then twice with `LlvmIR`, and makes `LlvmIR` the installed `cm3.cfg`'s default. |
| `README-ex_stack.md` | The newer zero-cost exception model. It currently requires the C backend, and is off by default on AMD64_LINUX. |
| `.github/workflows/` | Upstream CI, one workflow per platform. This fork adds `amd64_linux_llvmir.yml` (called from `integration.yml`): the `LlvmIR` build and m3tests with LLVM 18 and the newest LLVM. |

## Building and testing

**This fork's compiler is installed in `/usr/local/sw/versions/cm3/git`.**
Put `/usr/local/sw/versions/cm3/git/bin` first on `PATH`, and check
`cm3 -version` to see which compiler is active.

`~/cm3` holds an older release (d5.11.4). Leave it alone. It **cannot**
build this tree: on AMD64_LINUX this tree makes EXTENDED a 128-bit
`_Float128`, and d5.11.4's front end rejects the new `m3core` float
code ("LOOPHOLE: expression's size (64) differs from type's (128)").

To (re)create the install, follow upstream CI
(`.github/workflows/amd64_linux.yml`): build the d5.12.0 bootstrap
release with CMake, then upgrade from this tree. Building the
bootstrap needs **`libquadmath-devel`** (`-lquadmath`) and `ninja`.

```sh
P=/usr/local/sw/versions/cm3/git
W=/usr/local/sw/tmp/<your-dir>
mkdir -p $W/bootstrap && cd $W
curl -LO https://github.com/modula3/cm3/releases/download/d5.12.0/cm3-boot-AMD64_LINUX-d5.12.0.tar.xz
tar Jxf cm3-boot-AMD64_LINUX-d5.12.0.tar.xz -C bootstrap --strip-components=1
cmake -S bootstrap -B bootbuild -G Ninja -DCMAKE_INSTALL_PREFIX=$P
cmake --build bootbuild -j 8 && cmake --install bootbuild
export PATH=$P/bin:$PATH
/usr/local/sw/src/tkb/cm3/scripts/concierge.py full-upgrade   # run from $W; it writes concierge.log there
```

`full-upgrade` builds in-tree (gitignored `AMD64_LINUX/` directories)
and installs into the prefix of the `cm3` it finds on `PATH`.

- Build one package: `cd m3-sys/<pkg> && cm3` (output goes in
  `AMD64_LINUX/`). Install it: `cm3 -ship`.
- Select a backend for one build: `cm3 -DM3_BACKEND_MODE=C` (or another
  mode name from `Target.BackendModeStrings`).
  `cm3 -DM3_BACKEND_MODE=LlvmIR -keep` uses this fork's backend and
  keeps `Foo.m3.ll`; the `compile_llvm_ir` proc in `Unix.common` runs
  `clang -x ir` on it. After editing `Unix.common`, reinstall the config
  (`concierge.py upgrade` does) or copy it to
  `/usr/local/sw/versions/cm3/git/bin/config/`.
  Set `M3_LLVM_IR_VERIFY=1` in the environment to run `llvm-as` (the
  IR verifier) on every `.ll` first; a failure stops the build.
  `LlvmIR` emits debug information unless `-g0` is given, so its
  programs can be debugged with gdb (details in
  [`m3-sys/m3llvmir/README.md`](m3-sys/m3llvmir/README.md)). The compile unit says Modula-2,
  because gdb's Modula-3 support can't print sets or BOOLEANs; use
  `p^`, `a[i]` and `r.f`, not `Color.Blue`. Every unit embeds
  `m3-sys/m3llvmir/src/m3printers.py`, which prints TEXT values as
  strings and fixes how procedure values print. gdb runs it only for
  programs under `add-auto-load-safe-path DIR` (in `~/.gdbinit`, or
  `gdb -iex ...`); otherwise `source` it. `DIR` can be any directory
  above the program. On the command line it must be `-iex`: `-ex` and
  `-x` run after the program is loaded, too late for auto-loading.
  `set auto-load safe-path /` turns the check off entirely. An
  object's method suite is `p o^._methods^`. lldb has no Modula-2
  support and shows no variables of such units. For lldb, build with
  `-DM3_DEBUG_LANGUAGE=C` (the compile unit then says C, and sets
  become structs of one-bit members) and load the TEXT formatter with
  `command script import INSTALL_ROOT/share/m3llvmir/m3lldb.py` (in
  `~/.lldbinit`, say; here
  `/usr/local/sw/versions/cm3/git/share/m3llvmir/`, or
  `m3-sys/m3llvmir/src/` in the tree); then use `o->n` and
  `o->_methods->get`. Both debugger scripts are installed there when
  `m3llvmir` is shipped.
- After changing `m3llvmir`, rebuild the units you test (`rm -rf
  AMD64_LINUX` or touch the source): cm3 doesn't recompile when the
  compiler changes.
- A test package outside `m3tests` needs `import ("libm3")` in its
  `m3makefile`, or the front end can't find `RTHooks`.
- Keep intermediate files and show the commands run: `cm3 -keep -commands`.
  In C mode this keeps `Foo.m3.cpp` but, because of a bug, **not** the
  M3CG IR (`.mc`/`.ic`). To get M3CG IR as text, use
  `experiment-doc/gen_m3cg_corpus.sh` (or its `m3_backend` trick); a
  saved corpus is in `experiment-doc/m3cg-corpus/`.
- Run the compiler tests: `cd m3-sys/m3tests && cm3 -DHTML` (writes
  `m3tests-results.xml`). They take a while; prefer running a subset
  while iterating. The C-backend baseline is in
  `experiment-doc/m3tests-baseline-c.md`. Add `-DM3_BACKEND_MODE=LlvmIR`
  to build every test with this fork's backend (292 of 293 pass, as
  with C; see Phases 2 to 6 in `PLAN.md`), and `-DM3TESTS_OPTIMIZE` to build
  each test with `cm3 -O`.
- Rebuild the compiler after changing `m3front`, `m3middle`, `m3back`,
  `m3llvmir`, or `cm3`: `scripts/concierge.py upgrade` (or build and ship the
  packages in dependency order, then rebuild `cm3`).

Toolchain on the development machine: Fedora, x86_64, clang/LLVM 22
(`clang`, `llc`, `opt`, `llvm-as` in `/usr/bin`), GCC 16, CMake,
Ninja. No `lld`.

Settled backend decisions (see `PLAN.md`): the new package is
`m3-sys/m3llvmir`, the backend mode is `LlvmIR`, and the minimum LLVM
version is 18.

## Conventions

- Language: Modula-3 for compiler and backend code, matching the style
  of the surrounding file (indentation, `(* comments *)`, CamelCase
  interfaces, `snake_case` M3CG methods). Interfaces are `.i3`,
  modules `.m3`, and generics `.ig`/`.mg`. Each package has
  `src/m3makefile`.
- Generated LLVM IR must use **opaque pointers** (`ptr`). Never emit
  typed pointers.
- Don't commit generated build output (`AMD64_LINUX/` and similar
  target directories).
- Prefer small, reviewable commits. Commit only when asked.
- When behavior is unclear, the C backend (`M3C.m3`) is the reference:
  a program should behave identically when compiled with either
  backend.

## Scratch files

On the maintainer's workstation `/tmp` is a RAM-backed tmpfs. Put build
trees, test output and other scratch work under `/usr/local/sw/tmp/`
in a directory of your own, and delete it when you're done. Before
memory-heavy runs (building LLVM-linked code, full test suites) check
`free -g` and cap the run, for example with
`systemd-run --user --scope -q -p MemoryMax=... -p MemorySwapMax=0`.
