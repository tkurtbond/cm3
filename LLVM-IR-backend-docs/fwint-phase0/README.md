# Phase 0 cost measurement

The scripts and raw numbers behind the build-time and benchmark
comparison in the Phase 0 status of
[`fixed-width-integer-types-plan.md`](../fixed-width-integer-types-plan.md):
the C back end before (7670ff1ac) and after (547d4f16b) signed
arithmetic was made to wrap.

- `buildtime.sh LABEL old|new O0|O2` builds the packages in
  `$W/pkgs.txt` in C mode and prints wall time, CPU time, object text
  size and generated C++ size. `buildtime.tsv` has the per-package
  numbers (name, wall, user, sys, text, data, C++ bytes).
- `runtime.sh` builds the benchmarks with both drivers at `gcc -O0` and
  `gcc -O2`, times three interleaved runs of each pinned to CPU 2 (a
  P-core), checks that the outputs agree, and prints the minimum.
  `runtime.raw` has every run.
- `all.sh` runs three alternating build-time rounds per driver and
  level, then `runtime.sh`.
- `bench/Hash` is a new benchmark: multiplicative hashing over an
  INTEGER array, which overflows on purpose. The other benchmarks are
  in [`../phase4/bench`](../phase4/bench).

## Setup

```sh
W=/usr/local/sw/tmp/<your-dir>; export W
P=/usr/local/sw/versions/cm3/git; export PATH=$P/bin:$PATH
git worktree add --detach $W/wt-old 7670ff1ac
git worktree add --detach $W/wt-new 547d4f16b
for v in old new; do
  T=$W/wt-$v/m3-sys
  (cd $T/m3back && cm3)
  echo "override(\"m3back\", \"$T\")" > $T/cm3/src/m3overrides
  (cd $T/cm3 && cm3 -override)
  mkdir -p $W/bin-$v && cp $T/cm3/AMD64_LINUX/cm3 $W/bin-$v/
  # A cm3.cfg that selects C and includes the installed config:
  cat > $W/bin-$v/cm3.cfg <<EOF
M3_BACKEND_MODE = "C"
if not defined("SL") SL = "/" end
if not defined("HOST") HOST = "AMD64_LINUX" end
if not defined("TARGET") TARGET = HOST end
INSTALL_ROOT = "$P"
include("$P/bin/config/" & TARGET)
EOF
done
mkdir -p $W/o2 && cp LLVM-IR-backend-docs/phase4/gcc-O2-wrapper $W/o2/gcc
cp LLVM-IR-backend-docs/phase4/front-pkgs.txt $W/pkgs.txt
mkdir -p $W/benchsrc && cp -a LLVM-IR-backend-docs/phase4/bench/* \
  LLVM-IR-backend-docs/fwint-phase0/bench/* $W/benchsrc/
LLVM-IR-backend-docs/fwint-phase0/all.sh
```

`strings $W/bin-new/cm3 | grep m3_iabs_` finds the new helper; in
`bin-old` it finds nothing, which shows the override took effect.
