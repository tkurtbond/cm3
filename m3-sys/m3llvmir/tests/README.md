# Tests for the LlvmIR back end

```sh
m3-sys/m3llvmir/tests/run-tests.sh [-O] WORKDIR
```

It takes a few seconds and needs `cm3`, `clang`, `llvm-as` and
`FileCheck` on `PATH` (or `FILECHECK=/path/to/FileCheck`). `-O` builds
with `cm3 -O`. WORKDIR holds the builds and outputs; it is not cleaned
up afterwards.

- **Mixed linking** (`mixed/`): `mixlib` is a library and `mixprog` a
  program that calls it and prints the results. They are built with
  each of the four combinations of `LlvmIR` and the C back end, and
  the output is compared with `expected-output`.
  - `Ops` covers operations that are easy to lower wrongly: shifts and
    rotates with counts out of range, `DIV` and `MOD` with every sign,
    `Word.Extract` and `Word.Insert` at their edges, packed record
    fields, sets of one and of several words, sparse and dense `CASE`,
    and real-to-integer conversions.
  - `Abi` covers the calling convention between the two back ends:
    records and arrays by value and `READONLY`, open arrays, `REAL`,
    `LONGREAL` and `EXTENDED`, many arguments, enumerations and sets,
    nested procedures passed as values, exceptions and `FINALLY`
    across the boundary, and objects whose methods are overridden in
    the other unit.
- **Golden IR** (`Ops.check`): FileCheck patterns for the IR that
  `LlvmIR` emits for `Ops.m3`. Every `.ll` also goes through `llvm-as`.

`expected-output` holds the correct results, which `LlvmIR` gives. The
C back end gets five of them wrong (`diff expected-output
expected-output.clib`), so when `mixlib` is built with C the output is
compared with `expected-output.clib`. If the C back end is fixed,
delete that file and the line of `run-tests.sh` that uses it.

To regenerate `expected-output` after adding tests, run the script,
check `WORKDIR/L-L/output` by hand, and copy it here; the same for
`WORKDIR/C-C/output` and `expected-output.clib`.

To add a FileCheck check, look at `WORKDIR/L-L/mixlib/AMD64_LINUX/Ops.m3.ll`.
Match values with captures (`[[X:%t\.[0-9]+]]`), not their numbers.
Debug information is on, so a `CHECK-NOT` must name what it excludes:
plain `call` matches `@llvm.dbg.declare`.
