# m3tests baseline: C backend, AMD64_LINUX

Recorded 2026-11-16 (Phase 0) so that the `LlvmIR` backend can be
compared with it: a test that passes here should pass with `LlvmIR`,
and a test that fails here is not a regression.

- Compiler: this tree at commit d2108205f, installed in
  `/usr/local/sw/versions/cm3/git` (`cm3 -version` says d5.11.9), built
  by `concierge.py full-upgrade` with the C backend.
- Toolchain: GCC 16.2.1 (the C backend's output is compiled as C++ by
  `gcc`), ld.gold, Fedora x86_64.
- Command (as in upstream CI), about 2 minutes on this machine:
  ```sh
  cd m3-sys/m3tests
  systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 cm3 -DHTML
  ```
- Full junit report: [`m3tests-baseline-c.xml.xz`](m3tests-baseline-c.xml.xz)
  (`m3tests-results.xml`, which contains every diff).

## Summary

293 test runs (the default run covers `p*`, `e0` and `r0`; `c*` and
`x0` tests are not run by default). **266 pass, 27 fail.** p227 counts
twice: its build check and its run check both fail.

## Failures, by cause

**Only a new GCC warning (10).** The generated C++ triggers GCC 16's
`-Wvolatile` warning ("'volatile'-qualified parameter is deprecated",
from the `m3_pop_T` macro), so `stderr.build` doesn't match the
expected file. The programs are fine. These are expected to pass with
`LlvmIR`:
p039, p085, p100, p117, p140, p184, p189, p205, p265, e020.

**Expected file missing (1).** p283: there is no `stderr.build` in the
test directory. Effectively a pass.

**The C backend generates invalid C++ (4).** These tests fail to
compile.
- p053, p160: `'SET' was not declared in this scope` (set
  comparisons).
- p109: `invalid cast from type 'const Main_m_4_L_5_t'` (FIRST/LAST of
  enumerations in record constants).
- p269: `expected initializer before 'temp'` (nested array
  constructors).

**Wrong results at run time (6).**
- p156, p159, p162: set operations on medium and very large sets give
  wrong answers (`Test.check` reports ERROR).
- p137: bit insert and extract, "LONGINT value check failed".
- p047: Real/Integer LOOPHOLE (`1067316150 instead of 1`, and so on),
  probably an expected-output problem with EXTENDED now 128-bit.
- p227: `<*ASSERT*> failed: (FIRST(INTEGER) * NotConstI(0)) = 0` at
  Main.m3 line 250, after which output stops. This is
  integer-multiply semantics; the LlvmIR backend must get it right.

**Output differs in constructor tests (4).** p268, p270, p277, p280.
Debugging output (`TIntLiteral:type=UINT64 i=-8 ok1=FALSE ok2=TRUE`)
appears, the "N warnings encountered" line is missing, and the
expected run-time errors appear in a different form. These need a
closer look before we count them as either backend's fault.

**C backend type declarations (1).** p201: `DeclareTypes not
progressing` (recursive values). The message comes from `M3C.m3`; the
test passes with `LlvmIR`.

## Passing tests (266)

```
e001 e002 e003 e004 e005 e006 e007 e008 e009 e010 e011 e012 e013 e014
e015 e016 e017 e018 e019 e021 e022 e023 e024 e025 e026 e027 e028 e029
e030 e031 e032 e033 e034 e035 e040 e041 p001 p002 p003 p004 p005 p006
p007 p008 p009 p010 p011 p012 p013 p014 p015 p016 p017 p018 p019 p020
p021 p022 p023 p024 p025 p026 p027 p028 p029 p030 p031 p032 p034 p035
p036 p037 p038 p040 p041 p042 p043 p044 p045 p046 p048 p049 p050 p051
p052 p054 p055 p056 p057 p058 p059 p060 p061 p062 p063 p064 p065 p066
p067 p069 p071 p072 p073 p074 p075 p076 p077 p078 p079 p080 p081 p082
p083 p084 p086 p087 p088 p089 p090 p091 p092 p093 p094 p095 p096 p097
p098 p099 p101 p102 p103 p104 p105 p106 p107 p108 p110 p111 p112 p113
p114 p115 p116b p118 p119 p120 p121 p122 p123 p124 p125 p126 p127 p128
p129 p131 p132 p133 p134 p136 p138 p139 p141 p142 p143 p144 p145 p146
p148 p149 p150 p151 p155 p157 p158 p163 p164 p165 p166 p167 p168 p169
p170 p171 p172 p173 p174 p175 p176 p177 p178 p179 p180 p181 p182 p183
p185 p186 p187 p188 p190 p191 p192 p193 p194 p195 p196 p197 p198 p199
p200 p202 p203 p204 p206 p207 p208 p209 p210 p211 p212 p213 p214 p215
p216 p217 p218 p219 p220 p221 p222 p223 p225 p228 p229 p238 p241 p242
p243 p244 p245 p246 p247 p264 p271 p272 p273 p274 p275 p278 p279 p281
p282 p286 p287 p288 p289 p291 p292 p293 p295 r001 r002 r003 r004 r005
```

## Notes for the LlvmIR comparison

- The test harness compares `stderr.build`, so compiler warnings count
  as failures. `clang -x ir` output must stay quiet, or the harness
  must be told to ignore it.
- The corpus test p0/p053 (`experiment-doc/m3cg-corpus/p0-p053`) is one
  the C backend can't compile. Its M3CG IR is still valid, which makes
  it a good early test of whether `LlvmIR` can do better.

## Update, 2026-11-17: M3C fixes

This fork has since fixed several of the C back end's bugs in
`m3-sys/m3back/src/M3C.m3` (marked "This fork"; see the mixed-linking
item in `PLAN.md`): the `SET` typedef, inverted set `=`/`#`, set
`<=`/`<` operand order, `Word.Extract`/`Insert` with a count of 64, and
`shift_right` on signed types. With them, the same run fails 22 tests
instead of 27: p053, p156, p159, p160 and p162 pass, and p137 fails
only on the `-Wvolatile` warning. The list above is the baseline as
recorded before the fixes.
