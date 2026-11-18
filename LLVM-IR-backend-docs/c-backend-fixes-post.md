# C backend fixes in the tkurtbond/cm3 fork

This fork of cm3 is developed with the aid of AI.

While adding an LLVM IR backend to my fork, I compared the C backend's
output with it and found some bugs in `m3-sys/m3back/src/M3C.m3`. The
fixes are small and marked "This fork" in the source, and I'm happy to
open PRs if they're wanted.

## Sets and word operations

Commit [8be996c90](https://github.com/tkurtbond/cm3/commit/8be996c90):

- `Word.Extract(x, 0, 64)` and `Word.Insert(x, y, 0, 64)` shifted by 64,
  which is undefined in C. They now compute in `UINT64` and handle the
  full-width case.
- `shift_right` on signed types used C's arithmetic `>>`, so one-word
  set ranges came out wrong. It now shifts as unsigned.
- `m3_set_le` and `m3_set_lt` named their parameters in the opposite
  order to the call, so `<=` and `<` on sets longer than one word were
  reversed.
- `=` and `#` on sets in memory gave inverted results.
- A unit whose only set operations were comparisons didn't get the
  `SET` typedef and failed to compile (p053, p160).

With these fixes, m3tests with the C backend fail 22 tests instead of
27 (with GCC 16 on AMD64_LINUX); p053, p156, p159, p160 and p162 now
pass. Most of the remaining failures are only GCC 16's `-Wvolatile`
warning about the `m3_pop_T` macro showing up in `stderr.build`.

## Signed overflow

Commit [547d4f16b](https://github.com/tkurtbond/cm3/commit/547d4f16b):

- INTEGER and LONGINT `+`, `-`, `*` and unary minus were emitted as C
  signed arithmetic, whose overflow is undefined behavior. GCC folded
  `x + 1 > x` to TRUE at `LAST(INTEGER)`, even at `-O0`.
- Signed operands are now cast to the unsigned type, operated on, and
  cast back, the same way `casted_shift_left` already works.
- `ABS` of a signed integer gets a new `m3_iabs_T` helper that negates
  through the unsigned type, so `ABS(FIRST(INTEGER))` also wraps.
- Overflow now wraps. A new test, p296, checks this at the limits.
