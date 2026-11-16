# Phase 4 results: self-hosting and performance

Recorded 2026-11-16. Compiler: this tree at commit 5b32ce1e1 plus the
two Phase 4 fixes below. Machine: Intel i9-13900HX (8 P-cores, 16
E-cores, 32 threads), Fedora 44 x86_64, clang/LLVM 22.1.8, GCC 16.2.1,
ld.gold. Scripts, package lists, benchmark sources and raw numbers are
in [`phase4/`](phase4/).

## Summary

- **Fixed point reached.** A C-built `cm3` (stage 1) built the 15
  compiler packages with `LlvmIR`. The result (stage 2) built them
  again (stage 3), and so on. All **1,368 `.ll` files are
  byte-identical** between consecutive stages. The binaries differ only
  in the embedded build timestamp (23 bytes).
- **Headless set built.** All 59 packages that `concierge.py` installs
  on this machine with the C backend build with `LlvmIR`, using the
  self-hosted compiler.
- **The self-hosted compiler passes m3tests** as well as the C-built
  one did in Phase 3: 292 of 293 runs (p047, Real - Integer
  `LOOPHOLE`, is the known failure), with `m3core`/`libm3` and the whole
  compiler built by `LlvmIR`.
- **Builds are about 2 to 2.5 times faster than with the C backend, and
  `-O0` code is 20% smaller.** At `-O2` the code is the same size.
- **The emitter needs no tuning.** Front end plus emitter (`-boot`, no
  clang) takes 55% of the C backend's time, and the backend module is
  under 2% of the profile.
- **Runtime at `-O2` is on par with C at `-O2`** (within ±10%). The
  upstream C configuration never optimizes its generated C (see below),
  so in practice `LlvmIR -O` is 1.7 to 4 times faster than what cm3
  users get today with the C backend, except on GC-bound code, which
  runs in the same `m3core` either way.

## Fixes found by Phase 4

1. **`cm3cfg.common`: `-unfold_nested_procs` for `LlvmIR`.** The front
   end only unnests procedures (TRY-FINALLY handlers, nested
   procedures) when `M3_FRONT_FLAGS` contains `-unfold_nested_procs`.
   The config sets that for C and the LLVM modes, but not for `LlvmIR`.
   Earlier phases never noticed: they selected `LlvmIR` with
   `-DM3_BACKEND_MODE=LlvmIR` on a config whose `cm3.cfg` says `C`, and
   the flags are computed from the config's value. With
   `M3_BACKEND_MODE = "LlvmIR"` in `cm3.cfg`, `m3core` failed with
   "begin_procedure inside @RTAllocator__AllocTraced". Fixed by adding
   `LlvmIR` to the list (one marked line).
2. **REAL constants must be exactly representable.** `FloatLit` wrote a
   REAL constant's value as an LLVM double-format hex literal without
   rounding it to single precision. The front end can hand a REAL
   operation a value of LONGREAL precision (e.g. `FLOAT(2.0D0*Pi, REAL)`
   folded at compile time). TFloat's `FloatF` doesn't round, so LLVM
   rejected the literal ("floating point constant invalid for type") in
   eight `arithmetic` units. `FloatLit` now always rounds float
   constants with `FLOAT(x, REAL)`, as C's implicit conversion does. A
   test of folded constants, record initializers and `TRUNC` prints the
   same values with both backends.

## Self-hosting

The method
([`phase4/stage.sh`](phase4/stage.sh)):
- **Setup.** Copy the install (`/usr/local/sw/versions/cm3/git`, built
  by C) to a scratch prefix, and set line 1 of its `bin/cm3.cfg` to
  `M3_BACKEND_MODE = "LlvmIR"`. Make a git worktree of the commit.
- **Each stage.**
  - For every package in [`front-pkgs.txt`](phase4/front-pkgs.txt), run
    `cm3 -realclean`, `cm3 -build -keep` and `cm3 -ship` with the
    scratch prefix's `cm3`.
  - Keep the `.ll` files.
  - Copy the new `pkg/cm3/AMD64_LINUX/cm3` to `bin/cm3`, because
    `cm3 -ship` doesn't install into `bin/`.
- **Safety.** The script refuses to ship any package whose `.M3SHIP`
  names a prefix other than the scratch one.

| Stage | Built by | Front set wall time | `.ll` files vs previous stage |
|-------|----------|--------------------:|-------------------------------|
| A | C-built cm3 (stage 1) | 17.8 s | — |
| B | stage A cm3 | 14.9 s | 1,368 of 1,368 identical |
| C | stage B cm3 | 15.1 s | 1,368 of 1,368 identical |
| D | stage C cm3, fixed source | 14.6 s | only `M3LLVMIR.m3.ll` differs (fix 2) |
| E | stage D cm3 | 14.4 s | 1,368 of 1,368 identical |
| F | stage E cm3 | 14.4 s | 1,368 of 1,368 identical |

Stage A was already at the fixed point: the C-built and `LlvmIR`-built
compilers produce the same IR, as they should.

## Headless package set

The set is [`headless-pkgs.txt`](phase4/headless-pkgs.txt): concierge's
`headless` set, restricted to the packages that `concierge.py
full-upgrade` installed with C on this machine, plus `m3llir`.
- Left out by concierge here: m3cc, m3gdb, tcl, tapi and serial.
- Not installed: libunicode, odbc, mysql, postgres95, PEX, m3sleep,
  llvm22bindings and llvm22.

All 59 build and ship with `LlvmIR` (31 s wall) after fix 2. Before it,
`arithmetic` failed.

## Compile time and code size

[`phase4/measure.sh`](phase4/measure.sh) builds every headless package
(after `cm3 -realclean`, without shipping) and records:
- wall and CPU time;
- `size` of the `.o` files;
- the size of the generated `.ll` or `.cpp`.

The compiler is the self-hosted stage F; `M3_PARALLEL_BACK` is 20.

| Configuration | Wall | CPU | Code (text) | Data | Generated source |
|---------------|-----:|----:|-----:|-----:|-----:|
| C, default (`gcc -O0`) | 61.5 s | 158.8 s | 13.13 MB | 11.76 MB | 596 MB of C++ |
| LlvmIR, default (`clang -O0`) | **29.6 s** | **69.1 s** | **10.51 MB** | 11.78 MB | 127 MB of IR |
| C, `gcc -O2` (wrapper) | 133.9 s | 425.7 s | 6.99 MB | 11.74 MB | 596 MB |
| LlvmIR, `-O` (`clang -O2`) | **54.7 s** | **144.1 s** | **6.89 MB** | 11.78 MB | 127 MB |
| C, `-boot` (front end + M3C only) | 32.5 s | 32.1 s | — | — | 574 MB |
| LlvmIR, `-boot` (front end + M3LLVMIR only) | **17.9 s** | **17.6 s** | — | — | 122 MB |

**`cm3 -O` doesn't optimize C-backend code.** Upstream `Builder.m3`
compiles the C backend's output with `optimize := FALSE`, so `cm3 -O`
in C mode still runs `gcc -O0`. For the "C, `gcc -O2`" row, a `gcc`
wrapper first on `PATH` ([`phase4/gcc-O2-wrapper`](phase4/gcc-O2-wrapper))
rewrites `-O0` to `-O2`.

The C++ is about 4.7 times the size of the IR, because every unit
carries the M3C prelude.

The largest packages (wall seconds / text bytes):

| Package | C | LlvmIR | C gcc -O2 | LlvmIR -O |
|---------|---|--------|-----------|-----------|
| m3core | 5.5 / 670 K | 3.5 / 538 K | 12.9 / 375 K | 7.6 / 373 K |
| libm3 | 4.8 / 1.33 M | 2.3 / 1.05 M | 11.5 / 680 K | 4.3 / 629 K |
| m3front | 9.5 / 2.36 M | 4.1 / 1.91 M | 20.2 / 1.30 M | 7.0 / 1.20 M |
| m3tk | 12.9 / 2.05 M | 5.7 / 1.64 M | 27.1 / 1.08 M | 10.3 / 1.08 M |

**Profile.** This is `perf record -e cpu_core/cycles/u` of
`cm3 -build -boot` on m3front.
- `LlvmIR` takes 11K samples and C 28K.
- With `LlvmIR`, the profile is dominated by the front end and the
  runtime: allocation, the GC, `RTType` and `TextCat`. `M3LLVMIR`'s own
  code is 1.8% (self time), and with C, `M3C` is 3.4%.
- Text concatenation shows up (`TextCat` about 6%), but no more than
  with C. Moving to `M3Buf`/direct `Wr.T` writes is not worth doing now.
- The per-unit `clang` process is the main cost of a non-`-boot`
  build. It runs in parallel and is still cheaper than `gcc` on the C++.

## Runtime benchmarks

The sources are in [`phase4/bench/`](phase4/bench/), and the outputs are
identical across configurations.
- **Sieve:** sieve of Eratosthenes to 2×10⁷, 10 times.
- **NBody:** 5 bodies, 2×10⁷ steps (LONGREAL, `Math.sqrt`).
- **Trees:** binary trees to depth 18 (allocation and GC).
- **QSort:** quicksort of 5×10⁶ INTEGERs, 5 times.

Timing: the minimum wall time of 3 runs, pinned to one P-core. All
configurations link the same scratch-prefix `m3core`/`libm3` (built by
`LlvmIR` at `-O0`).

| Program | C (as shipped, `gcc -O0`) | C, `gcc -O2` | LlvmIR `-O0` | LlvmIR `-O2` |
|---------|------:|------:|------:|------:|
| Sieve | 1.57 s | 0.85 s | 1.54 s | 0.93 s |
| NBody | 3.58 s | 0.80 s | 3.25 s | 0.88 s |
| Trees | 4.31 s | 4.16 s | 4.51 s | 4.24 s |
| QSort | 3.75 s | 1.94 s | 3.27 s | 1.89 s |

- Trees spends its time in the allocator and collector in `m3core`,
  which is the same in every column, so it barely moves.
- `LlvmIR -O2` is 9 to 10% behind `gcc -O2` on Sieve and NBody. Two
  likely reasons:
  - Both programs go through bounds-checked or field-by-field accesses
    that the IR spells out with `alloca`/`load`/`store`, and LLVM only
    partly cleans these up.
  - GCC's `-O2` vectorizes and unrolls differently.

  This is a candidate for later tuning (for example, emitting
  `nsw`/`nuw` where Modula-3 semantics allow it, and better aliasing
  information); it is not a blocker.

**The compiler as a benchmark.** The job is `cm3 -build -boot` in C
mode over m3front: front end plus M3C, 2 cores, minimum of 3 runs.
- C-built `cm3` (stage 1, `gcc -O0`): 7.03 s; text 5.58 MB.
- `LlvmIR`-built `cm3` (stage F, `clang -O0`): **4.54 s** (1.55 times
  faster); text 4.64 MB.

## Reproducing

```sh
W=/usr/local/sw/tmp/<your-dir>; export W
cp -a /usr/local/sw/versions/cm3/git $W/prefix
sed -i '1s/.*/M3_BACKEND_MODE = "LlvmIR"/' $W/prefix/bin/cm3.cfg
cp m3-sys/cminstall/src/config/cm3cfg.common $W/prefix/bin/config/  # fix 1
git worktree add --detach $W/src HEAD
cp experiment-doc/phase4/front-pkgs.txt $W/pkgs.txt
cp experiment-doc/phase4/headless-pkgs.txt $W/headless-inst.txt
for s in A B C; do experiment-doc/phase4/stage.sh $s; done
diff -r $W/ll/B $W/ll/C                      # the fixed point
experiment-doc/phase4/stage.sh H LlvmIR $W/headless-inst.txt
experiment-doc/phase4/measure.sh L0 LlvmIR -keep
```
