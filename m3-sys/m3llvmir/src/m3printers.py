# m3printers.py: gdb pretty-printers for Modula-3 programs compiled by
# cm3's LlvmIR back end (PLAN.md, Phase 5).
#
# The back end embeds this script in the .debug_gdb_scripts section of
# every unit compiled with debug information.  gdb runs it if the
# program is under a directory of "auto-load safe-path", for example
# after this line in ~/.gdbinit:
#
#     add-auto-load-safe-path /path/to/your/programs
#
# or it can be loaded by hand: "source m3printers.py".
#
# Printers:
#   TEXT       the characters of the text, as "abc" (W"abc" for wide
#              texts) or NIL.  "print/r t" shows the raw pointer.
#   PROCEDURE  in Modula-2 frames (gdb shows Modula-3 as Modula-2),
#              the procedure a procedure value points to; gdb's own
#              Modula-2 printer shows the address of the pointer.
#
# The TEXT printer knows the representations in m3core/src/text and
# finds a text's representation from the symbol in the first slot of
# its method suite (get_info).  Keep it in step with those modules.

import gdb
import gdb.printing

_cache = {}         # get_info address -> representation name
_state = {}         # target facts: pointer size, byte order, ...


def _clear(_event=None):
    _cache.clear()
    _state.clear()


def _facts():
    if not _state:
        arch = gdb.selected_inferior().architecture()
        void_p = arch.void_type().pointer()
        _state["ptr"] = void_p.sizeof
        _state["void_p"] = void_p
        endian = gdb.execute("show endian", to_string=True)
        _state["order"] = "big" if "big endian" in endian else "little"
        try:
            _state["wide"] = gdb.lookup_type("WIDECHAR").sizeof
        except gdb.error:
            _state["wide"] = 2
    return _state


def _read(addr, n):
    if n <= 0:
        return b""
    return bytes(gdb.selected_inferior().read_memory(addr, n))


def _word(addr, signed=False):
    f = _facts()
    return int.from_bytes(_read(addr, f["ptr"]), f["order"], signed=signed)


def _kind(text):
    """The representation of the TEXT at "text": the name of the
    procedure in the get_info slot of its method suite."""
    get_info = _word(_word(text))
    kind = _cache.get(get_info)
    if kind is None:
        # "0x401234 <RTHooks__TextLitInfo@plt>", or "0x401234" if no
        # symbol is known.  ("info symbol" would need an expression,
        # and gdb's Modula-2 parser rejects most addresses.)
        out = gdb.format_address(get_info)
        kind = "?"
        if "<" in out:
            kind = out[out.index("<") + 1:].rstrip(">")
            # C-backend code has C++ names: "Text8__T8GetInfo(...)".
            for sep in "+@(":
                kind = kind.split(sep)[0]
        _cache[get_info] = kind
    return kind


def _chars(addr, n, wide):
    """n characters at addr, as a str."""
    if not wide:
        return _read(addr, n).decode("latin-1")
    f = _facts()
    w = f["wide"]
    raw = _read(addr, n * w)
    return "".join(chr(int.from_bytes(raw[i:i + w], f["order"]))
                   for i in range(0, len(raw), w))


def _cstring(addr, limit):
    out = bytearray()
    while len(out) < limit:
        chunk = _read(addr + len(out), min(256, limit - len(out)))
        nul = chunk.find(b"\0")
        if nul >= 0:
            out += chunk[:nul]
            break
        out += chunk
    return out.decode("latin-1")


def _text(t, limit, depth=0):
    """(characters, wide): at most "limit" characters of the TEXT at t."""
    if t == 0:
        return "", False
    if depth > 100:
        raise ValueError("TEXT nested too deeply")
    p = _facts()["ptr"]
    kind = _kind(t)
    if kind == "RTHooks__TextLitInfo":                 # TextLiteral.T
        cnt = _word(t + p, signed=True)
        wide = cnt < 0
        return _chars(t + 2 * p, min(abs(cnt), limit), wide), wide
    if kind in ("Text8__T8GetInfo", "Text16__T16GetInfo"):
        wide = kind.startswith("Text16")
        arr = _word(t + p)                             # REF ARRAY OF CHAR
        n = _word(arr + p) - 1                         # NUL-terminated
        return _chars(_word(arr), min(n, limit), wide), wide
    if kind in ("Text8Short__T8SGetInfo", "Text16Short__T16SGetInfo"):
        wide = kind.startswith("Text16")
        n = min(_word(t + p), 16)
        return _chars(t + 2 * p, min(n, limit), wide), wide
    if kind == "Text8CString__T8CGetInfo":
        return _cstring(_word(t + p), limit), False
    if kind == "TextCat__CatGetInfo":
        a, wa = _text(_word(t + p), limit, depth + 1)
        b, wb = "", False
        if len(a) < limit:
            b, wb = _text(_word(t + 2 * p), limit - len(a), depth + 1)
        return a + b, wa or wb
    if kind == "TextSub__SubGetInfo":
        start, n = _word(t + 2 * p), _word(t + 3 * p)
        s, wide = _text(_word(t + p), start + min(n, limit), depth + 1)
        return s[start:start + n], wide
    raise ValueError("unknown TEXT representation " + kind)


def _quote(s):
    out = ['"']
    for c in s:
        if c == '"' or c == "\\":
            out.append("\\" + c)
        elif c == "\n":
            out.append("\\n")
        elif c == "\t":
            out.append("\\t")
        elif c.isprintable():
            out.append(c)
        elif ord(c) < 256:
            out.append("\\%03o" % ord(c))
        else:
            out.append("\\x%04x" % ord(c))
    out.append('"')
    return "".join(out)


class TextPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        t = int(self.val.cast(_facts()["void_p"]))
        if t == 0:
            return "NIL"
        limit = gdb.parameter("print elements") or (1 << 30)
        try:
            s, wide = _text(t, limit + 1)
        except (gdb.error, gdb.MemoryError, ValueError) as e:
            return "<TEXT 0x%x: %s>" % (t, e)
        more = "..." if len(s) > limit else ""
        return ("W" if wide else "") + _quote(s[:limit]) + more


class ProcPrinter:
    def __init__(self, val):
        self.val = val

    def to_string(self):
        p = int(self.val.cast(_facts()["void_p"]))
        if p == 0:
            return "NIL"
        try:
            return gdb.format_address(p)
        except AttributeError:                         # gdb < 13
            return "0x%x" % p


class M3Printer(gdb.printing.PrettyPrinter):
    def __init__(self):
        super().__init__("m3", [gdb.printing.SubPrettyPrinter("TEXT"),
                                gdb.printing.SubPrettyPrinter("PROCEDURE")])

    def __call__(self, val):
        if not self.enabled:
            return None
        t = val.type
        while t.code == gdb.TYPE_CODE_TYPEDEF:
            if t.name == "TEXT":
                return TextPrinter(val) if self.subprinters[0].enabled else None
            t = t.target()
        if (t.code == gdb.TYPE_CODE_PTR
                and t.target().code == gdb.TYPE_CODE_FUNC
                and self.subprinters[1].enabled
                and gdb.current_language() == "modula-2"):
            return ProcPrinter(val)
        return None


if not getattr(gdb, "_m3printers_loaded", False):
    gdb._m3printers_loaded = True
    gdb.printing.register_pretty_printer(None, M3Printer())
    gdb.events.new_objfile.connect(_clear)
    gdb.events.exited.connect(_clear)
