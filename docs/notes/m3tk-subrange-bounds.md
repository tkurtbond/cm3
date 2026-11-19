# m3tk overwrites negative subrange bounds (stubgen)

## Problem

`MayBeExactBitSizeAndAlign` in `m3-tools/m3tk/src/target/M3CBackEnd_C.m3` computes
the size of a subrange type. It binds `s1` and `s2` to the subrange's bounds with
`WITH`, so they are aliases of the values in the AST. For a negative bound it then
assigns `s2 := 0` (`0L` for LONGINT), which changes the subrange itself. In the
LONGINT branch both `s1` and `s2` are bound to the lower bound (`as_exp1`).

Anything that runs m3tk and then reads the bounds sees the wrong values. For example,
stubgen on this interface:

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

(with `netobj("N", "T")` in the m3makefile) writes stubs that check the argument and
the result against the bounds -10 and 0:

```
    x_arg := StubLib.InInteger(c, rep, -10, 0);
```

A LONGINT subrange loses its negative lower bound instead: for `[-10L .. 5L]` stubgen
writes the bounds 0 and 5.

## Change

`m3-tools/m3tk/src/target/M3CBackEnd_C.m3`: in both branches the bounds are copied
into variables (`VAR ... BEGIN` instead of `WITH ... DO`), and the LONGINT branch
reads `s2` from the upper bound (`as_exp2`).

## Verification

On Fedora 44 (GCC 16.2.1), master was built with
`concierge.py full-upgrade --backend c -g0`. Then m3tk was rebuilt with this change and
installed into a copy of that installation, and stubgen was relinked against it.
The interface above, and a copy of it with `Sub = [-10L .. 5L]` in place of `Neg`,
were built with `cm3 -keep`, and the generated stubs (`N_T_v1.m3`) were inspected:

- **master:** `[-10 .. -1]` gets the bounds -10, 0, and `[-10L .. 5L]` gets 0, 5.
- **with the change:** -10, -1 and -10, 5.

The LONGINT case is shown only in the generated source: on master, stubs with
LONGINT arguments don't compile, because StubLib has no `InLongint` or `OutLongint`
(fixed separately).
