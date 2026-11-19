# Network objects with LONGINT arguments don't compile

## What happens

stubgen already writes calls to `StubLib.OutLongint` and `StubLib.InLongint` for
LONGINT parameters and results, but `StubLib` doesn't have them, so the stubs
don't compile.

## Reproducer

`src/L.i3`:

```
INTERFACE L;
IMPORT NetObj, Thread;
TYPE
  Sub = [0L .. 16_1ffffffffL];
  T = NetObj.T OBJECT METHODS
    add (x: LONGINT; y: Sub): LONGINT RAISES {NetObj.Error, Thread.Alerted};
  END;
END L.
```

`src/m3makefile`:

```
import("libm3")
import("netobj")
interface("L")
netobj("L","T")
library("l")
```

```
"../AMD64_LINUX/L_T_v1.m3", line 24: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/L_T_v1.m3", line 25: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/L_T_v1.m3", line 29: unknown qualification '.' (InLongint)
"../AMD64_LINUX/L_T_v1.m3", line 76: unknown qualification '.' (InLongint)
"../AMD64_LINUX/L_T_v1.m3", line 77: unknown qualification '.' (InLongint)
"../AMD64_LINUX/L_T_v1.m3", line 81: unknown qualification '.' (OutLongint)
```

Adding the two procedures isn't enough. stubgen writes the bounds of a LONGINT
subrange as INTEGER literals (`StubLib.InLongint(c, rep, 0, 8589934591)`),
which aren't assignable to LONGINT formals:

```
"../AMD64_LINUX/L_T_v1.m3", line 77: actual not assignable to VALUE formal (2.3.2)  (min)
"../AMD64_LINUX/L_T_v1.m3", line 77: actual not assignable to VALUE formal (2.3.2)  (max)
```

## Fix

Branch `fix/netobj-longint`:

- Adds `OutLongint` and `InLongint` to `StubLib`, written like `OutInt32` and
  `InInt32`.
- stubgen writes LONGINT bounds as LONGINT literals.
- New client/server test `m3-comm/netobj/tests/longint`.

Details are in `docs/notes/netobj-longint.md`.
