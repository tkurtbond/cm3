# m3tk overwrites negative subrange bounds, so stubgen checks the wrong range

## What happens

When m3tk computes the size of a subrange type, it changes the subrange's bounds
in the AST:

- An INTEGER subrange with a negative upper bound gets an upper bound of 0.
- A LONGINT subrange with a negative lower bound gets a lower bound of 0.

Tools that use m3tk then see the wrong range. stubgen, for example, makes the
stubs check arguments and results against it.

## Reproducer

`src/N.i3`:

```
INTERFACE N;
IMPORT NetObj, Thread;
TYPE
  Neg = [-10 .. -1];
  T = NetObj.T OBJECT METHODS
    f (x: Neg): Neg RAISES {NetObj.Error, Thread.Alerted};
  END;
END N.
```

`src/m3makefile`:

```
import("libm3")
import("netobj")
interface("N")
netobj("N","T")
library("n")
```

After `cm3 -keep`, `AMD64_LINUX/N_T_v1.m3` has:

```
    x_arg := StubLib.InInteger(c, rep, -10, 0);
```

The bounds should be -10 and -1. With `Sub = [-10L .. 5L]` instead,
stubgen writes the bounds 0 and 5. That stub doesn't compile on master
anyway (see the LONGINT network objects issue), but the wrong bounds are visible
in the generated source.

## Cause

`MayBeExactBitSizeAndAlign` in `m3-tools/m3tk/src/target/M3CBackEnd_C.m3`
binds `s1` and `s2` to the bounds with `WITH`, which makes them aliases of the AST
values. It then assigns `s2 := 0` (or `0L`) for a negative bound. In the LONGINT
branch, both `s1` and `s2` are bound to the lower bound (`as_exp1`).

## Fix

Branch `fix/m3tk-subrange-bounds`: it copies the bounds into variables, and reads
`s2` from `as_exp2`. Details are in `docs/notes/m3tk-subrange-bounds.md`.
