# C back end: FIRST(INTEGER) DIV -1 and MOD -1 die with SIGFPE

## What happens

With the C back end on x86, `x MOD -1` and `x DIV -1` kill the program with
SIGFPE when `x` is `FIRST(INTEGER)`, and likewise for LONGINT. `x MOD -1` is 0
for every `x`, so it should never fail. `FIRST(INTEGER) DIV -1` overflows, and
should wrap to `FIRST(INTEGER)`, the same as `-FIRST(INTEGER)` does.

## Reproducer

```
MODULE Main;
IMPORT IO, Fmt;
VAR x := FIRST (INTEGER);  y := -1;
BEGIN
  IO.Put (Fmt.Int (x MOD y) & "\n");
END Main.
```

```
$ ./AMD64_LINUX/snip
Floating point exception (core dumped)
```

Expected output: `0`.

## Cause

`m3-sys/m3back/src/M3C.m3` computes DIV and MOD with C's `/` and `%`, either
inline or in the `m3_div_T` and `m3_mod_T` helpers. In C, `FIRST / -1` and
`FIRST % -1` are undefined behavior, and x86's `idiv` traps on them. The inline
`/` and `%` are also used when both operands are known to be negative, and that
can still be `FIRST / -1`.

## Fix

Branch `fix/div-mod-minus-one`:

- The helpers check for a divisor of -1 first. MOD returns 0, and DIV negates in
  unsigned arithmetic.
- Two negative operands go through the helpers.
- New m3tests case p297.

The m3tests results show no other changes (`docs/notes/div-mod-minus-one.md`).
