# Bug reports for modula3/cm3

One file per bug, each written to be pasted into a GitHub issue: what goes wrong,
a minimal reproducer, and what was checked. Each was reproduced on master
(5f8dd68485) on Fedora 44 x86_64 with GCC 16.2.1, using the C back end
(`concierge.py full-upgrade --backend c -g0`).

| File | Bug | Fix branch |
|------|-----|------------|
| [div-mod-minus-one.md](div-mod-minus-one.md) | `FIRST(INTEGER) DIV -1` and `MOD -1` die with SIGFPE (C back end) | `fix/div-mod-minus-one` |
| [netobj-longint.md](netobj-longint.md) | Network objects with LONGINT arguments don't compile | `fix/netobj-longint` |
| [sharedobj-longint.md](sharedobj-longint.md) | Shared objects with LONGINT arguments don't compile | `fix/sharedobj-longint` |
| [m3tk-subrange-bounds.md](m3tk-subrange-bounds.md) | m3tk overwrites negative subrange bounds, so stubgen checks the wrong range | `fix/m3tk-subrange-bounds` |
| [rtpacking-max-align-128.md](rtpacking-max-align-128.md) | `RTPacking.Encode` overflows on a max_align of 128 | none yet: it changes the pickle header, so it needs discussion first |
