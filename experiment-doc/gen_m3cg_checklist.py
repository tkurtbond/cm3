#!/usr/bin/env python3
"""Generate experiment-doc/m3cg-ops-checklist.md from the M3CG interface.

Usage: python3 experiment-doc/gen_m3cg_checklist.py . > experiment-doc/m3cg-ops-checklist.md

Regenerating overwrites the hand-maintained Status and Notes columns;
merge by hand (or diff) if they have been filled in.
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
ops_file = "m3-sys/m3middle/src/M3CG_Ops.i3"
backends = [
    ("M3C", "m3-sys/m3back/src/M3C.m3"),
    ("M3CG_LLVM", "m3-sys/llvm/llvm22/src/M3CG_LLVM.m3"),
]

ops_lines = (root / ops_file).read_text(errors="replace").splitlines()

# Collect (section, op, line) from the METHODS block.
section = None
ops = []
in_methods = False
for n, line in enumerate(ops_lines, 1):
    if line.startswith("METHODS"):
        in_methods = True
        continue
    if not in_methods:
        continue
    if line.startswith("END"):
        break
    m = re.match(r"\(\*-+\s*(.*?)\s*-+\*\)", line)
    if m:
        section = m.group(1)
        continue
    m = re.match(r"([a-z_][a-z_0-9]*)\s*\(", line)
    if m:
        ops.append((section, m.group(1), n))


def index_backend(path):
    """Map op name -> line of its implementing PROCEDURE."""
    text = (root / path).read_text(errors="replace").splitlines()
    procs = {}
    for n, line in enumerate(text, 1):
        m = re.match(r"\s*(?:<\*[^*]*\*>\s*)?PROCEDURE\s+([A-Za-z_][A-Za-z_0-9]*)\b", line)
        if m and m.group(1) not in procs:
            procs[m.group(1)] = n
    bindings = {}
    for line in text:
        m = re.match(r"\s*([a-z_][a-z_0-9]*)\s*:=\s*([A-Za-z_][A-Za-z_0-9.]*)\s*;", line)
        if m and m.group(1) not in bindings:
            bindings[m.group(1)] = m.group(2)
    result = {}
    for _, op, _ in ops:
        for target in (op, bindings.get(op)):
            if target in procs:
                result[op] = procs[target]
                break
    return result


indexes = [(name, path, index_backend(path)) for name, path in backends]

out = []
out.append("# M3CG operation checklist for the LlvmIR backend\n")
out.append(
    "Generated from `" + ops_file + "` by `gen_m3cg_checklist.py`; the Status column is\n"
    "maintained by hand. Line links point at the implementing procedure in\n"
    "each reference backend (`—` means no procedure of that name was found,\n"
    "which usually means the method is inherited or bound under another\n"
    "name, so check by hand).\n\n"
    "Status values: `todo`, `wip`, `done` (implemented and covered by a\n"
    "test), `n/a` (deliberately not needed; say why in Notes).\n"
)
cur = object()
for sec, op, line in ops:
    if sec != cur:
        cur = sec
        out.append(f"\n## {sec or 'Unsectioned'}\n")
        hdr = "| Op | Decl | " + " | ".join(n for n, _, _ in indexes) + " | Status | Notes |"
        out.append(hdr)
        out.append("|" + "---|" * (4 + len(indexes) - 1) + "---|")
    cells = [f"`{op}`", f"[{line}](../{ops_file}#L{line})"]
    for _, path, idx in indexes:
        cells.append(f"[{idx[op]}](../{path}#L{idx[op]})" if op in idx else "—")
    cells += ["todo", ""]
    out.append("| " + " | ".join(cells) + " |")

print("\n".join(out))
missing = {n: sum(1 for _, op, _ in ops if op not in idx) for n, _, idx in indexes}
print(f"{len(ops)} ops; unresolved per backend: {missing}", file=sys.stderr)
