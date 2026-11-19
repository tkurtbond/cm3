# Shared objects with LONGINT arguments don't compile

## What happens

This is the same problem as in network objects, in sharedobjgen. For a LONGINT
argument of an update method, sharedobjgen writes calls to
`SharedObjStubLib.OutLongint` and `InLongint`. Neither those nor the
`EventStubLib` procedures they would be built on exist. sharedobjgen also writes
LONGINT subrange bounds as INTEGER literals, including in the `PickleStubs` call
that reads the field.

## Reproducer

`src/L.i3`:

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

The rest is in `m3-comm/sharedobj/tests/longint` on the fix branch. It needs
`LF.i3` and `LF.m3`, which reveal `L.S`, and an m3makefile with
`sharedobj("L", ["T"], ["LF"])`. Building it on master gives:

```
"../AMD64_LINUX/LSO.m3", line 126: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/LSO.m3", line 127: unknown qualification '.' (OutLongint)
"../AMD64_LINUX/LSO.m3", line 173: unknown qualification '.' (InLongint)
"../AMD64_LINUX/LSO.m3", line 174: unknown qualification '.' (InLongint)
"../AMD64_LINUX/LSO.m3", line 315: actual not assignable to VALUE formal (2.3.2)  (min)
"../AMD64_LINUX/LSO.m3", line 315: actual not assignable to VALUE formal (2.3.2)  (max)
```

Line 174 is `h_arg := SharedObjStubLib.InLongint(in, 1, 8589934591);`.

## Fix

Branch `fix/sharedobj-longint`:

- Adds `OutLongint` and `InLongint` to `EventStubLib` and `SharedObjStubLib`.
- sharedobjgen writes LONGINT bounds as LONGINT literals.
- New local and client/server test `m3-comm/sharedobj/tests/longint`.

Details are in `docs/notes/sharedobj-longint.md`.
