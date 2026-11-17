# cm3 with the LLVM IR back end on macOS (ARM64_DARWIN)

This fork's `LlvmIR` back end (package `m3-sys/m3llvmir`; user guide
in [`m3-sys/m3llvmir/README.md`](m3-sys/m3llvmir/README.md)) works on
Apple silicon Macs. CI (`.github/workflows/darwin_llvmir.yml`) builds
and tests it there with LLVM 18 and 22. These notes say how to get an
installation that uses it by default.

## Prerequisites

- **Xcode Command Line Tools**, for the macOS SDK, the linker and
  `python3`: `xcode-select --install`.
- **CMake and Ninja.**
- **LLVM's clang, 18 or later, from Homebrew.** Not Xcode's clang:
  Apple numbers its versions differently and lags LLVM, and
  `concierge.py` refuses it.

```sh
brew install cmake ninja llvm      # or a particular one: llvm@18 … llvm@22
export PATH="$(brew --prefix llvm)/bin:$PATH"    # keg-only: put it first
clang --version                    # Homebrew clang, version 18 or later
```

Keep that clang first on `PATH` afterwards too: the installed config
compiles each `.ll` file with the `clang` it finds there. To avoid
depending on `PATH`, define `LLVM_IR_CC` in the installed `cm3.cfg`
(see "Changing how the IR is compiled" in the user guide).

## From source, with upstream's C bootstrap

This works now, with no release of this fork.

1. Install upstream's ARM64_DARWIN C bootstrap (d5.12.0) into a prefix
   of your choice:

   ```sh
   P=$HOME/cm3       # the install prefix
   curl -LO https://github.com/modula3/cm3/releases/download/d5.12.0/cm3-boot-ARM64_DARWIN-d5.12.0.tar.xz
   mkdir bootstrap
   tar Jxf cm3-boot-ARM64_DARWIN-d5.12.0.tar.xz -C bootstrap --strip-components=1
   cmake -S bootstrap -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$P
   cmake --build build && cmake --install build
   export PATH=$P/bin:$PATH
   ```

2. Clone this fork and build with `LlvmIR`:

   ```sh
   git clone https://github.com/tkurtbond/cm3 && cd cm3
   scripts/concierge.py full-upgrade --backend llvmir headless -m3gdb
   ```

   This builds the compiler with the C back end, rebuilds it twice with
   `LlvmIR`, and then builds the packages with `LlvmIR`. It writes
   `M3_BACKEND_MODE = "LlvmIR"` into `$P/bin/cm3.cfg`, so plain `cm3`
   uses `LlvmIR` from then on (`cm3 -DM3_BACKEND_MODE=C` for the C back
   end).

## From a bootstrap of LLVM IR

`make-release.yml` also makes `cm3-boot-ARM64_DARWIN-llvmir-VERSION.tar.xz`,
the compiler's sources as LLVM IR (`.ll` files) instead of C. (There
is no release of this fork with it yet; `darwin_llvmir.yml`'s
`ir-bootstrap` job uploads one as an artifact, and you can make one
yourself, on any machine with this fork's compiler and clang 18 or
later: `scripts/concierge.py make-bootstrap --backend llvmir --target
ARM64_DARWIN`.) It skips the round through the C back end, and its
`cm3` defaults to `LlvmIR` from the start:

```sh
mkdir bootstrap
tar Jxf cm3-boot-ARM64_DARWIN-llvmir-VERSION.tar.xz -C bootstrap --strip-components=1
cmake -S bootstrap -B build -G Ninja -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_INSTALL_PREFIX=$P
cmake --build build && cmake --install build
export PATH=$P/bin:$PATH
cd cm3 && scripts/concierge.py full-upgrade headless -m3gdb
```

The bootstrap installs `$P/share/cm3/bootstrap-backend`, which says
`llvmir`; given no `--backend`, concierge then uses `LlvmIR` (see "A
bootstrap of LLVM IR" in the user guide).

## What you get

- **Exceptions:** the Darwin configs turn on zero-cost exceptions
  (`ex_stack`, see [`README-ex_stack.md`](README-ex_stack.md)), and
  `LlvmIR` supports them.
- **Debugging:** debug information is labeled as C, for lldb (which
  has no Modula-2 support). The TEXT formatter is installed as
  `$P/share/m3llvmir/m3lldb.py`; load it with `command script import`
  (in `~/.lldbinit`, say), and use C syntax: `o->n`,
  `o->_methods->get`.
- **Tests:** m3tests passes except for failures that are macOS-specific
  or that the C back end shares: p047; e020 and r001 to r005, because
  the macOS shell reports signals differently ("Abort trap: 6",
  "Segmentation fault: 11"); and p223, whose expected output names
  Linux `.so` libraries.

## Caveats

- CI builds and tests only the `headless` package set (without
  `m3gdb`). The GUI packages (`all`) would need XQuartz's X11
  libraries, and no one has tried them with `LlvmIR` on macOS.
- **AMD64_DARWIN (Intel Macs):** the source route works the same way,
  with the AMD64_DARWIN C bootstrap. Homebrew has no LLVM bottles for
  Intel any more, so use a release from LLVM itself (20.1.7 is the
  newest with an Intel macOS build); that clang needs
  `export SDKROOT=$(xcrun --show-sdk-path)` to find the SDK. There is
  no bootstrap of LLVM IR for AMD64_DARWIN.
