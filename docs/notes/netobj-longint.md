# LONGINT in network objects (stubgen, StubLib)

## Problem

A network object with a LONGINT parameter or result can't be built. For this
interface (with `netobj("L", "T")` in the m3makefile):

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

the stubs that stubgen writes don't compile:

```
"../AMD64_LINUX/L_T_v1.m3", line 24: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/L_T_v1.m3", line 29: unknown qualification '.' (InLongint)
```

There are two causes:

- stubgen (`MarshalTypedVal` in `m3-comm/stubgen/src/ModuleStubCode.m3`) already
  calls `StubLib.OutLongint` and `StubLib.InLongint` for LONGINT values, but
  `StubLib` has neither.
- For a LONGINT subrange, stubgen writes the bounds as INTEGER literals
  (`StubLib.InLongint(c, rep, 0, 8589934591)`). Those aren't assignable to LONGINT
  formals, so even with the procedures added, the stubs fail with
  `actual not assignable to VALUE formal (2.3.2)  (min)`.

## Change

- `m3-comm/netobj/src/netobjrt/StubLib.i3`, `StubLib.m3`: new `OutLongint` and
  `InLongint`, written like `OutInt32` and `InInt32`. The value is 8-byte aligned and
  sent in the sender's byte order. `InLongint` reverses the bytes when the sender's
  `DataRep` has the other byte order, and raises `NetObj.Error` (through
  `RaiseUnmarshalFailure`) for a value outside `[min .. max]`.
- `m3-comm/stubgen/src/ModuleStubCode.m3`: `SubRange` writes LONGINT bounds with the
  new `LongLit`, which appends `L`. It writes `FIRST(LONGINT)` by name, because the
  magnitude of that value has no literal.
- New test `m3-comm/netobj/tests/longint`. Run `longinttest server`, then
  `longinttest client` in another process. The client calls methods with LONGINT and
  LONGINT subrange arguments, results and VAR parameters, using values that don't fit
  in 32 bits. It also checks that the server rejects an out-of-range subrange value,
  and that the connection still works afterwards. It prints `ok` or `WRONG` for each
  check and exits with status 1 if any is wrong.

## Verification

On Fedora 44 (GCC 16.2.1), master was built with
`concierge.py full-upgrade --backend c -g0`. Then netobj and stubgen were rebuilt with
this change and installed into a copy of that installation.

- **master:** the test doesn't build: 22 `unknown qualification` errors in
  `L_T_v1.m3`.
- **with only the StubLib part** (new StubLib, old stubgen): 10
  `actual not assignable` errors, from the subrange bounds.
- **with the change:** the test builds without warnings. The client passes all 10
  checks against the server and prints them as `ok`.
