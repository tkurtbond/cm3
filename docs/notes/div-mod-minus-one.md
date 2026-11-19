# FIRST DIV -1 and FIRST MOD -1 in the C back end (m3tests p297)

## Problem

In Modula-3, `x MOD -1` is 0 for every `x`, and `FIRST(INTEGER) DIV -1`
overflows. With the C back end, both kill the program with SIGFPE on x86:

```
MODULE Main;
IMPORT IO, Fmt;
VAR x := FIRST (INTEGER);  y := -1;
BEGIN
  IO.Put (Fmt.Int (x MOD y) & "\n");   (* Floating point exception *)
END Main.
```

The same holds for LONGINT. The C back end (`m3-sys/m3back/src/M3C.m3`) computes DIV
and MOD with C's `/` and `%`, either inline or inside the `m3_div_T` and `m3_mod_T`
helpers. In C, `FIRST / -1` and `FIRST % -1` are undefined, and x86's `idiv` traps on
them.

C's `/` and `%` are used inline when the type is unsigned, or when both operands have
the same known sign. Two negative operands can still be `FIRST / -1`, so that case
traps too.

## Change

`m3-sys/m3back/src/M3C.m3`:

- `m3_div_T` and `m3_mod_T` check for a divisor of -1 first. MOD returns 0. DIV
  negates in unsigned arithmetic, so `FIRST DIV -1` wraps to `FIRST`, the same as
  unary minus.
- New `DivModIsPlain` holds the condition for using `/` and `%` inline: an unsigned
  type, or two operands known to be non-negative (`Sign.Positive`). The four places
  that tested `(a = b AND a # Sign.Unknown) OR unsigned` use it now, so two negative
  operands go through the helpers.

New test p297 tests DIV and MOD over every combination of signs, for INTEGER and
LONGINT. It covers FIRST and LAST, a constant divisor of -1, and two operands of the
subrange type `[FIRST(INTEGER) .. -1]`.

## Verification

On Fedora 44 (GCC 16.2.1), master was built with
`concierge.py full-upgrade --backend c -g0`. Then m3back and the cm3 driver were rebuilt
with this change and installed into a copy of that installation.

- **master:** p297's program dies with `Floating point exception` after its first two
  lines of output.
- **with the change:** p297 passes.
- **Rest of the suite** (`cd m3-sys/m3tests && cm3 -DHTML`): master has 26 errors
  out of 294 tests. With the change there are 26 errors out of 295. The failing tests
  are the same on both, so p297 is the only difference.
