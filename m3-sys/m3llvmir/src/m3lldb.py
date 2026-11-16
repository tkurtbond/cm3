# m3lldb.py: lldb formatters for Modula-3 programs compiled by cm3's
# LlvmIR back end (PLAN.md, Phase 5).
#
# lldb shows no variables of a unit that claims to be Modula-2, the
# default, so compile the program for lldb with
#
#     cm3 -DM3_BACKEND_MODE=LlvmIR -DM3_DEBUG_LANGUAGE=C
#
# and load this file, with m3printers.py beside it, for example from
# ~/.lldbinit.  Shipping m3llvmir installs both in
# INSTALL_ROOT/share/m3llvmir:
#
#     command script import /usr/local/cm3/share/m3llvmir/m3lldb.py
#
# (lldb does not read the scripts that the back end embeds for gdb.)
#
# Formatters:
#   TEXT  a summary with the characters of the text, as "abc" (W"abc"
#         for wide texts) or NIL.  At most target.max-string-summary-
#         length characters are shown.  "frame variable --raw-output t"
#         or "p/x t" shows the pointer.
#
# The decoding is m3printers.py's TextDecoder, shared with gdb.

import os
import sys

import lldb

_dont_write = sys.dont_write_bytecode
sys.dont_write_bytecode = True      # no __pycache__ in the source tree
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
try:
    from m3printers import TextDecoder
finally:
    del sys.path[0]
    sys.dont_write_bytecode = _dont_write

_decoders = {}      # process unique id -> TextDecoder


def _limit(debugger):
    try:
        v = lldb.SBDebugger.GetInternalVariableValue(
            "target.max-string-summary-length", debugger.GetInstanceName())
        return int(v.GetStringAtIndex(0))
    except (TypeError, ValueError, AttributeError):
        return 1024


def _decoder(process):
    key = (process.GetUniqueID(), process.GetProcessID())
    dec = _decoders.get(key)
    if dec is None:
        target = process.GetTarget()

        def read(addr, n):
            if n <= 0:
                return b""
            err = lldb.SBError()
            data = process.ReadMemory(addr, n, err)
            if err.Fail():
                raise ValueError("cannot read 0x%x: %s" % (addr,
                                                         err.GetCString()))
            return bytes(data)

        def symbol(addr):
            sym = target.ResolveLoadAddress(addr).GetSymbol()
            return sym.GetName() if sym.IsValid() else None

        wide = 2
        widechar = target.FindFirstType("WIDECHAR")
        if widechar.IsValid() and widechar.GetByteSize() > 0:
            wide = widechar.GetByteSize()
        order = ("big" if target.GetByteOrder() == lldb.eByteOrderBig
                 else "little")
        _decoders.clear()           # one process at a time is plenty
        dec = TextDecoder(read, symbol, target.GetAddressByteSize(),
                          order, wide)
        _decoders[key] = dec
    return dec


def text_summary(valobj, _internal_dict):
    t = valobj.GetValueAsUnsigned(0)
    if t == 0:
        return "NIL"
    process = valobj.GetProcess()
    if not process.IsValid():
        return None
    try:
        return _decoder(process).show(
            t, _limit(process.GetTarget().GetDebugger()))
    except (ValueError, OverflowError) as e:
        return "<TEXT 0x%x: %s>" % (t, e)


def __lldb_init_module(debugger, _internal_dict):
    debugger.HandleCommand(
        "type summary add --category m3 -F %s.text_summary TEXT" % __name__)
    debugger.HandleCommand("type category enable m3")
