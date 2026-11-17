# The LlvmIR back end: user guide

`LlvmIR` is a cm3 back end that writes textual LLVM IR (`Foo.m3.ll`)
and compiles it with the system's `clang`. It runs inside `cm3`, like
the C back end, and needs no LLVM libraries to build: only a `clang`
(and, for checking, `llvm-as`) at compile time.

Developers working on the back end itself: see
[`HACKING.md`](HACKING.md). The design and its history are in
[`PLAN.md`](../../PLAN.md).

## Requirements and status

- **Target:** AMD64_LINUX and ARM64_LINUX, both tested in CI.
  Darwin is planned (see PLAN.md, Phase 7).
- **LLVM:** `clang` 18 or later on `PATH`. CI tests LLVM 18 and the
  newest release. The IR uses opaque pointers throughout.
- **Exceptions:** the default `ex_frame` model (setjmp/longjmp) works,
  and so does the zero-cost `ex_stack` model (`README-ex_stack.md`) on
  AMD64_LINUX: with `M3_USE_STACK_WALKER` set, the config keeps
  `LlvmIR` (it forces C for every other mode). With `ex_stack`, m3tests
  passes 292 of 293, as with `ex_frame`, and an unhandled exception is
  reported the same way.
- **Tests:** m3tests passes 292 of 293, the same as the C back end
  (p047 fails with both). The compiler builds itself with `LlvmIR`, and
  its output reaches a fixed point.
- **Mixing:** code built with `LlvmIR` and with the C back end links
  together. You can switch one package at a time.

## Choosing the back end

For one build, pass the mode to cm3:

```sh
cm3 -DM3_BACKEND_MODE=LlvmIR          # build this package with LlvmIR
cm3 -DM3_BACKEND_MODE=LlvmIR -keep    # ... and keep Foo.m3.ll
```

To make it the default for an installation, build and install with
concierge:

```sh
scripts/concierge.py full-upgrade --backend llvmir    # or: -llvmir
```

This checks for `clang` 18 or later, builds the compiler with the C
back end, rebuilds it twice with `LlvmIR`, and then builds the
packages with `LlvmIR`. It writes `M3_BACKEND_MODE = "LlvmIR"` at the
top of the installed `bin/cm3.cfg`, so later `cm3` runs use `LlvmIR`
unless told otherwise (`cm3 -DM3_BACKEND_MODE=C`). You can also edit
that line of `cm3.cfg` yourself.

### Optimization

`cm3 -O` passes `-O2` to clang (the config's `m3back_optimize`);
otherwise clang gets `-O0`. The C back end compiles with `-O0` even
under `-O`, so optimized `LlvmIR` code is often several times faster
(numbers in `experiment-doc/phase4-results.md`).

### Changing how the IR is compiled

The installed config compiles each `.ll` with the quake procedure
`compile_llvm_ir` from `Unix.common`, which runs

```
clang -fPIC -Wno-override-module -O0|-O2 [-g] -c -x ir Foo.m3.ll -o Foo.m3.o
```

- To use another clang, define `LLVM_IR_CC` before the config's
  includes in `cm3.cfg`, or on the command line:
  `cm3 -DLLVM_IR_CC="clang-18 -fPIC -Wno-override-module"`.
- To replace the step entirely (for example with `llc` and `as`),
  define your own `proc compile_llvm_ir(source, object, optimize,
  debug)` in `cm3.cfg`.
- If the environment variable `M3_LLVM_IR_VERIFY` is set, every `.ll`
  is first checked with `llvm-as -o /dev/null` (LLVM's IR verifier).
  CI sets it. Recent clangs verify IR input themselves; older ones may
  not.

### The standalone translator

`m3llir` (package `m3-sys/m3llir`) translates a saved M3CG file to
LLVM IR without running the front end:

```sh
m3llir [-a] [-g] [-l LANG] [-t TARGET] [-o out.ll] in.mc
```

`-a` reads ASCII M3CG (as `m3cgcat` writes it), `-g` adds debug
information, and `-l C` labels it as C (see below).

## Debugging

`LlvmIR` emits DWARF debug information unless `-g0` is given: line
tables, procedures, locals and parameters (including those of inner
blocks), globals, and the types of all of them (records, arrays and
open arrays, enumerations, subranges, sets, packed fields, pointers,
procedure types, and objects with their supertypes and method suites).
Exceptions and `RAISES` are not described yet.

The debugger scripts are installed in `INSTALL_ROOT/share/m3llvmir/`
(for example `/usr/local/cm3/share/m3llvmir/`):

- `m3printers.py`: gdb pretty-printers for TEXT and procedure values.
  It is also embedded in every unit with debug information.
- `m3lldb.py`: an lldb formatter for TEXT. It imports `m3printers.py`
  from its own directory.

### gdb

By default, the compile units say they are Modula-2, because gdb's
Modula-3 support can't print sets or BOOLEANs. Use Modula-2 syntax:
`p^`, `a[i]`, `r.f`. Qualified enumeration literals such as
`Color.Blue` don't parse. An object's method suite is
`p o^._methods^`.

gdb runs the embedded `m3printers.py` only for programs under an
auto-load safe path. Add a directory above your programs to
`~/.gdbinit`:

```
add-auto-load-safe-path /home/me/src
```

(`set auto-load safe-path /` turns the check off entirely.) On the
command line it must be `-iex`, which runs before the program is
loaded; `-ex` and `-x` come too late:

```sh
gdb -iex 'add-auto-load-safe-path /home/me/src' ./AMD64_LINUX/prog
```

Alternatively, `source INSTALL_ROOT/share/m3llvmir/m3printers.py`.

With the printers, TEXT values print as `"abc"` (`W"..."` for wide
texts) or `NIL`, honoring `set print elements`, and procedure values
print as `0x401000 <Main__CircleArea>`. `p/r t` shows the raw pointer.

### lldb

lldb has no Modula-2 support and shows no variables of such units, so
build for lldb with the C label:

```sh
cm3 -DM3_BACKEND_MODE=LlvmIR -DM3_DEBUG_LANGUAGE=C
```

(or set `M3_DEBUG_LANGUAGE = "C"` in `cm3.cfg`). Sets then become
structs with a one-bit member per element. Load the TEXT formatter,
for example from `~/.lldbinit`:

```
command script import /usr/local/cm3/share/m3llvmir/m3lldb.py
```

Then use C syntax: `o->n`, `o->_methods->get`. gdb also works with
C-labeled units, with C syntax.

## Troubleshooting

- **"the llvmir backend needs clang 18 or later"** from concierge:
  put a newer `clang` first on `PATH` (concierge checks the `clang` it
  finds there).
- **A package didn't pick up a compiler change:** cm3 doesn't
  recompile when the compiler changes. Remove the package's
  `AMD64_LINUX` directory, or touch its sources.
- **Reporting a back-end bug:** build with `-keep -commands` and keep
  `Foo.m3.ll`. If clang rejects it, `llvm-as Foo.m3.ll` points at the
  bad line. Compare with the C back end (`-DM3_BACKEND_MODE=C`): a
  program should behave identically with both.
