# Building cm3 on macOS

These notes say how to build and install cm3 on a Mac, with either of
two back ends:

- **C**, upstream's back end on macOS: the compiler translates
  Modula-3 to C++, and Xcode's `clang++` compiles that.
- **LlvmIR**, this fork's back end: the compiler writes LLVM IR
  (`Foo.m3.ll`), and LLVM's `clang` compiles that. Its user guide is
  [`m3-sys/m3llvmir/README.md`](m3-sys/m3llvmir/README.md).

Both work on Apple silicon (target ARM64_DARWIN) and on Intel Macs
(AMD64_DARWIN). The commands below are for Apple silicon; see "Intel
Macs" for the differences.

The usual way to get an `LlvmIR` installation today is to start from
upstream's C bootstrap, let the C back end build a compiler that has
`LlvmIR` in it, and then build everything else with `LlvmIR`.
`concierge.py` does all of that in one command (see "LlvmIR, starting
from the C bootstrap" below). It needs nothing but a Mac and the tools
listed here: no release of this fork, and no CI.

## Prerequisites

For either back end:

- **Xcode Command Line Tools**, for the macOS SDK, the linker, `clang`
  and `python3`: `xcode-select --install`.
- **CMake and Ninja**, to build the bootstrap: `brew install cmake ninja`.
- **This fork's sources:** `git clone https://github.com/tkurtbond/cm3`.

For `LlvmIR`, also:

- **LLVM's clang, 18 or later, from Homebrew.** Not Xcode's clang:
  Apple numbers its versions differently ("Apple clang version 17" is
  roughly LLVM 19) and lags LLVM, and `concierge.py` refuses it.

  ```sh
  brew install llvm                  # or a particular one: llvm@18 … llvm@22
  export PATH="$(brew --prefix llvm)/bin:$PATH"   # keg-only: put it first
  clang --version                    # Homebrew clang, version 18 or later
  ```

  Keep that clang first on `PATH` whenever you use cm3, not just while
  installing it: the installed config compiles each `.ll` file with the
  `clang` it finds there. To avoid depending on `PATH`, define
  `LLVM_IR_CC` in the installed `cm3.cfg` (see "Changing how the IR is
  compiled" in the `LlvmIR` user guide).

## Step 1: install the C bootstrap

Upstream's release d5.12.0 has a bootstrap for each Mac: the compiler's
sources translated to C++, with CMake files. Build it into the prefix
where you want cm3 installed:

```sh
P=$HOME/cm3       # the install prefix; anything you like
curl -LO https://github.com/modula3/cm3/releases/download/d5.12.0/cm3-boot-ARM64_DARWIN-d5.12.0.tar.xz
mkdir bootstrap
tar Jxf cm3-boot-ARM64_DARWIN-d5.12.0.tar.xz -C bootstrap --strip-components=1
cmake -S bootstrap -B build -G Ninja -DCMAKE_INSTALL_PREFIX=$P
cmake --build build && cmake --install build
export PATH=$P/bin:$PATH
```

This gives `$P/bin/cm3`, a d5.12.0 compiler with the C back end only.
The rest is built from this fork's sources with `scripts/concierge.py`,
which installs into the prefix of the `cm3` it finds on `PATH`. Run it
from any directory; it writes its log, `concierge.log`, there.

## Step 2, the C back end

```sh
cd cm3                       # this fork's sources
scripts/concierge.py full-upgrade
```

`full-upgrade` builds this tree's compiler twice with the C back end
(the second time with the first's output), installs it, and then
builds and installs the packages. With no `--backend`, concierge uses
C here (`--backend c` says so explicitly).

## Step 2, LlvmIR, starting from the C bootstrap

With Homebrew's clang first on `PATH` (see "Prerequisites"):

```sh
cd cm3                       # this fork's sources
scripts/concierge.py full-upgrade --backend llvmir
```

This one command goes through these stages:

1. It checks that `clang` on `PATH` is clang 18 or later.
2. It builds this tree's compiler with the C back end, using the
   bootstrap's cm3, and installs it. The bootstrap's cm3 has no
   `LlvmIR`; the new one does.
3. It rebuilds the compiler with `LlvmIR`, using that new cm3, and
   installs it; then once more, so that the installed compiler was
   built by an `LlvmIR`-built compiler.
4. It writes `M3_BACKEND_MODE = "LlvmIR"` at the top of
   `$P/bin/cm3.cfg`.
5. It deletes every package's build directory and builds and installs
   all the packages with `LlvmIR`.

From then on plain `cm3` uses `LlvmIR`, and `cm3
-DM3_BACKEND_MODE=C` builds one package with the C back end instead.
Later runs of `concierge.py` see the `cm3.cfg` line and keep using
`LlvmIR` without being told.

### Switching an existing installation

An installation made with the C back end switches to `LlvmIR` the same
way: with its `cm3` first on `PATH`, run
`scripts/concierge.py full-upgrade --backend llvmir`. Because step 5
rebuilds every package, nothing built with the C back end is left
behind. (Code from the two back ends does link together, so a mixed
installation also works; it is just not what this command makes.)
`full-upgrade --backend c` switches back.

To change only the default, edit the `M3_BACKEND_MODE` line at the top
of `$P/bin/cm3.cfg` yourself. cm3 does not recompile a package because
the back end changed, so rebuild existing packages from scratch (`cm3
-realclean`, or delete their `ARM64_DARWIN` directories).

## Alternative to steps 1 and 2: a bootstrap of LLVM IR

When this fork makes a release, its `make-release.yml` also makes
`cm3-boot-ARM64_DARWIN-llvmir-VERSION.tar.xz` and
`cm3-boot-AMD64_DARWIN-llvmir-VERSION.tar.xz`: the compiler's sources
as LLVM IR (`.ll` files) instead of C++. It makes them on Linux, so a
release doesn't wait for macOS runners. The first is in
[d5.12.1-llvmir.1](https://github.com/tkurtbond/cm3/releases/tag/d5.12.1-llvmir.1).
You can also make one yourself, on any machine (it need not be a Mac) that
has this fork's compiler and clang 18 or later:
`scripts/concierge.py make-bootstrap --backend llvmir --target
ARM64_DARWIN`, or `--target AMD64_DARWIN`.

Build it with clang as CMake's compilers: Homebrew's clang 18 or
later, or Xcode's (Apple clang 17 or later). The bootstrap's
`CMakeLists.txt` refuses other compilers. The `full-upgrade` after it
needs Homebrew's clang first on `PATH`, as in "Prerequisites":

```sh
mkdir bootstrap
tar Jxf cm3-boot-ARM64_DARWIN-llvmir-VERSION.tar.xz -C bootstrap --strip-components=1
cmake -S bootstrap -B build -G Ninja -DCMAKE_C_COMPILER=clang \
      -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_INSTALL_PREFIX=$P
cmake --build build && cmake --install build
export PATH=$P/bin:$PATH
cd cm3 && scripts/concierge.py full-upgrade
```

Its cm3 already has `LlvmIR`, so the round through the C back end is
skipped. The bootstrap also installs `$P/share/cm3/bootstrap-backend`,
which says `llvmir`; given no `--backend`, concierge then uses `LlvmIR`
(see "A bootstrap of LLVM IR" in the `LlvmIR` user guide).

## Package sets

`full-upgrade` builds the `headless` set unless told otherwise, which
is what CI builds on macOS (`full-upgrade ... headless -m3gdb`: m3gdb,
an old gdb, doesn't build there). Other sets, such as `all`, can be
named after the command; `concierge.py --help` lists them.

The GUI libraries (Trestle and everything built on it) need X11. On
Apple silicon the config (`Darwin.common`) doesn't set X11 up at all,
so those packages skip themselves. On Intel Macs it expects X11 in
`/usr/X11R6`, as old versions of macOS had it. Nobody has tried the
GUI packages on macOS with either back end in this fork.

## What you get

- **Exceptions:** the Darwin configs turn on zero-cost exceptions
  (`ex_stack`, see [`README-ex_stack.md`](README-ex_stack.md)). Both
  back ends support them.
- **Debugging:** use lldb. With `LlvmIR`, debug information is labeled
  as C, because lldb has no Modula-2 support. Load the TEXT formatter,
  installed as `$P/share/m3llvmir/m3lldb.py`, with `command script
  import` (in `~/.lldbinit`, say), and use C syntax: `o->n`,
  `o->_methods->get`.
- **Optimization:** with `LlvmIR`, `cm3 -O` has clang compile at
  `-O2`; otherwise at `-O0`.
- **Tests:** the compiler test suite (`cd m3-sys/m3tests && cm3
  -DHTML`) passes except for failures that are macOS-specific or that
  both back ends share: p047; e020 and r001 to r005, because the macOS
  shell reports signals differently ("Abort trap: 6", "Segmentation
  fault: 11"); and p223, whose expected output names Linux `.so`
  libraries.

## Intel Macs (AMD64_DARWIN)

Everything above works the same way, with `AMD64_DARWIN` in place of
`ARM64_DARWIN` in the bootstrap names. For `LlvmIR` the difference is
clang: Homebrew has no LLVM bottles for Intel any more (it builds LLVM
from source, which takes hours), so use a release from LLVM itself.
20.1.7 is the newest with an Intel macOS build, and is what CI uses:

```sh
mkdir -p ~/llvm
curl -L https://github.com/llvm/llvm-project/releases/download/llvmorg-20.1.7/LLVM-20.1.7-macOS-X64.tar.xz \
  | tar Jxf - -C ~/llvm --strip-components=1
export PATH=~/llvm/bin:$PATH
export SDKROOT=$(xcrun --show-sdk-path)   # LLVM's clang doesn't find the SDK itself
```

Keep `SDKROOT` set whenever you use cm3, as well as `PATH`.

## How this is tested

- Upstream's `arm64_darwin.yml` and `amd64_darwin.yml` build `headless`
  from the d5.12.0 C bootstrap with the C back end, and run m3tests.
- This fork's `darwin_llvmir.yml`:
  - `build-and-test` does "LlvmIR, starting from the C bootstrap" above
    and runs m3tests: on Apple silicon with LLVM 18 and 22, and on
    Intel with LLVM 20.1.7.
  - `ir-bootstrap` makes a bootstrap of LLVM IR, builds it with clang,
    builds everything with its compiler, and runs m3tests, on both
    kinds of Mac.

macOS runners on GitHub are often scarce, so these jobs can wait in a
queue for a long time. That affects only CI, not building on your own
Mac.
