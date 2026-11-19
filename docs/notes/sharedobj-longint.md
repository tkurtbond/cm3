# LONGINT in shared objects (sharedobjgen, SharedObjStubLib, EventStubLib)

## Problem

A shared object with a LONGINT argument to an update method can't be built. For this
interface (with `sharedobj("L", ["T"], ["LF"])` in the m3makefile, where `LF` reveals
`L.S`):

```
INTERFACE L;
IMPORT SharedObj, Thread;
<*PRAGMA SHARED *>
TYPE
  Sub = [1L .. 16_1ffffffffL];
  Vals = RECORD d: LONGINT; h: Sub END;
  T <: S;
  S <: Public;
  Public = SharedObj.T OBJECT
  METHODS
    init (): T RAISES {SharedObj.Error};
    set (d: LONGINT; h: Sub) RAISES {SharedObj.Error};
    get (): Vals RAISES {SharedObj.Error, Thread.Alerted};
    <* SHARED UPDATE METHODS T.set, T.init *>
  END;
END L.
```

the stubs that sharedobjgen writes don't compile:

```
"../AMD64_LINUX/LSO.m3", line 126: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/LSO.m3", line 173: unknown qualification '.' (InLongint)
"../AMD64_LINUX/LSO.m3", line 315: actual not assignable to VALUE formal (2.3.2)  (min)
```

There are two causes, the same two as in stubgen:

- sharedobjgen calls `SharedObjStubLib.OutLongint` and `InLongint` for LONGINT
  arguments, but `SharedObjStubLib` has neither, and neither does `EventStubLib`, which
  it is built on.
- For a LONGINT subrange, sharedobjgen writes the bounds as INTEGER literals, for
  example `SharedObjStubLib.InLongint(in, 1, 8589934591)`, and the same in the
  `PickleStubs.InLongint` call that reads the field. Those aren't assignable to
  LONGINT formals (line 315 above).

## Change

- `m3-comm/events/src/EventStubLib.i3`, `EventStubLib.m3`: new `OutLongint` and
  `InLongint`, written like `OutInteger` and `InInteger`, and like the new
  `StubLib.InLongint`: 8-byte aligned, bytes reversed when the sender has the other
  byte order, and `Event.Error` for a value outside `[min .. max]`.
- `m3-comm/sharedobj/src/SharedObjStubLib.i3`, `SharedObjStubLib.m3`: `OutLongint` and
  `InLongint` call the `EventStubLib` ones, as `OutInteger` and `InInteger` do.
- `m3-comm/sharedobjgen/src/SOxModuleSOCode.m3`: `SubRange` writes LONGINT bounds with
  the new `LongLit`, which appends `L`, and writes `FIRST(LONGINT)` by name. That is
  the same change as in stubgen. (`m3-comm/sharedobjgen/src/ModuleStubCode.m3` has the
  same code, but it isn't in the m3makefile, so it was left alone.)
- New test `m3-comm/sharedobj/tests/longint`, with the interface above.
  `longinttest` alone calls the update method locally and pickles the object.
  `longinttest server` and then `longinttest client` in another process exchange
  updates both ways through a replica, using values that don't fit in 32 bits. The
  client prints `ok` or `WRONG` for each check and exits with status 1 if any is wrong.

## Verification

On Fedora 44 (GCC 16.2.1), master was built with
`concierge.py full-upgrade --backend c -g0`. Then events, sharedobj and sharedobjgen
were rebuilt with this change and installed into a copy of that installation.

- **master:** the test doesn't build: 4 `unknown qualification` errors and 2
  `actual not assignable` errors in `LSO.m3`.
- **with the change:** the test builds. The local run passes all 4 of its checks, and
  the client passes all 8 of its checks against the server.
