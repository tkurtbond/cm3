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
#
# TextDecoder does not use gdb: m3lldb.py, the lldb formatter, imports
# it from this file.  Without gdb, importing this file only defines it.

try:
    import gdb
    import gdb.printing
except ImportError:                                    # lldb, or plain Python
    gdb = None


def symbol_name(name):
    """The bare procedure name of a symbol name: no "+16" offset, no
    "@plt", and no C++ signature ("Text8__T8GetInfo(...)", as in code
    from the C back end)."""
    for sep in "+@(":
        name = name.split(sep)[0]
    return name.strip()


class TextDecoder:
    """Decodes Modula-3 TEXTs in a debugged program's memory.

    read(addr, n) returns n bytes at addr; symbol(addr) returns the
    name of the symbol at addr, or None.  ptr is the size of a pointer
    in bytes, order is "little" or "big", and wide is the size of
    WIDECHAR in bytes."""

    def __init__(self, read, symbol, ptr, order, wide=2):
        self.read, self.symbol = read, symbol
        self.ptr, self.order, self.wide = ptr, order, wide
        self.kinds = {}     # get_info address -> representation name

    def word(self, addr, signed=False):
        return int.from_bytes(self.read(addr, self.ptr), self.order,
                              signed=signed)

    def kind(self, text):
        """The representation of the TEXT at "text": the name of the
        procedure in the get_info slot of its method suite."""
        get_info = self.word(self.word(text))
        kind = self.kinds.get(get_info)
        if kind is None:
            name = self.symbol(get_info)
            kind = symbol_name(name) if name else "?"
            self.kinds[get_info] = kind
        return kind

    def chars(self, addr, n, wide):
        """n characters at addr, as a str."""
        if n <= 0:
            return ""
        if not wide:
            return self.read(addr, n).decode("latin-1")
        w = self.wide
        raw = self.read(addr, n * w)
        return "".join(chr(int.from_bytes(raw[i:i + w], self.order))
                       for i in range(0, len(raw), w))

    def cstring(self, addr, limit):
        out = bytearray()
        while len(out) < limit:
            chunk = self.read(addr + len(out), min(256, limit - len(out)))
            nul = chunk.find(b"\0")
            if nul >= 0:
                out += chunk[:nul]
                break
            out += chunk
        return out.decode("latin-1")

    def text(self, t, limit, depth=0):
        """(characters, wide): at most "limit" characters of the TEXT
        at t."""
        if t == 0:
            return "", False
        if depth > 100:
            raise ValueError("TEXT nested too deeply")
        p, word = self.ptr, self.word
        kind = self.kind(t)
        if kind == "RTHooks__TextLitInfo":             # TextLiteral.T
            cnt = word(t + p, signed=True)
            wide = cnt < 0
            return self.chars(t + 2 * p, min(abs(cnt), limit), wide), wide
        if kind in ("Text8__T8GetInfo", "Text16__T16GetInfo"):
            wide = kind.startswith("Text16")
            arr = word(t + p)                          # REF ARRAY OF CHAR
            n = word(arr + p) - 1                      # NUL-terminated
            return self.chars(word(arr), min(n, limit), wide), wide
        if kind in ("Text8Short__T8SGetInfo", "Text16Short__T16SGetInfo"):
            wide = kind.startswith("Text16")
            n = min(word(t + p), 16)
            return self.chars(t + 2 * p, min(n, limit), wide), wide
        if kind == "Text8CString__T8CGetInfo":
            return self.cstring(word(t + p), limit), False
        if kind == "TextCat__CatGetInfo":
            a, wa = self.text(word(t + p), limit, depth + 1)
            b, wb = "", False
            if len(a) < limit:
                b, wb = self.text(word(t + 2 * p), limit - len(a), depth + 1)
            return a + b, wa or wb
        if kind == "TextSub__SubGetInfo":
            start, n = word(t + 2 * p), word(t + 3 * p)
            s, wide = self.text(word(t + p), start + min(n, limit),
                                depth + 1)
            return s[start:start + n], wide
        raise ValueError("unknown TEXT representation " + kind)

    def show(self, t, limit):
        """The TEXT at t as Modula-3 shows it: "abc", W"abc" or NIL,
        with "..." after it if it is longer than limit."""
        if t == 0:
            return "NIL"
        s, wide = self.text(t, limit + 1)
        more = "..." if len(s) > limit else ""
        return ("W" if wide else "") + quote(s[:limit]) + more


def quote(s):
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


# ------------------------------------------------------------------ gdb

_state = {}         # the decoder and gdb's void *, for the inferior


def _clear(_event=None):
    _state.clear()


def _gdb_symbol(addr):
    # "0x401234 <RTHooks__TextLitInfo@plt>", or "0x401234" if no symbol
    # is known.  ("info symbol" would need an expression, and gdb's
    # Modula-2 parser rejects most addresses.)
    out = gdb.format_address(addr)
    if "<" not in out:
        return None
    return out[out.index("<") + 1:].rstrip(">")


def _gdb_read(addr, n):
    return bytes(gdb.selected_inferior().read_memory(addr, n))


def _decoder():
    if not _state:
        arch = gdb.selected_inferior().architecture()
        void_p = arch.void_type().pointer()
        endian = gdb.execute("show endian", to_string=True)
        try:
            wide = gdb.lookup_type("WIDECHAR").sizeof
        except gdb.error:
            wide = 2
        _state["void_p"] = void_p
        _state["dec"] = TextDecoder(
            _gdb_read, _gdb_symbol, void_p.sizeof,
            "big" if "big endian" in endian else "little", wide)
    return _state["dec"]


if gdb is not None:
    class TextPrinter:
        def __init__(self, val):
            self.val = val

        def to_string(self):
            dec = _decoder()
            t = int(self.val.cast(_state["void_p"]))
            limit = gdb.parameter("print elements") or (1 << 30)
            try:
                return dec.show(t, limit)
            except (gdb.error, gdb.MemoryError, ValueError) as e:
                return "<TEXT 0x%x: %s>" % (t, e)


    class ProcPrinter:
        def __init__(self, val):
            self.val = val

        def to_string(self):
            _decoder()
            p = int(self.val.cast(_state["void_p"]))
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


if gdb is not None and not getattr(gdb, "_m3printers_loaded", False):
    gdb._m3printers_loaded = True
    gdb.printing.register_pretty_printer(None, M3Printer())
    gdb.events.new_objfile.connect(_clear)
    gdb.events.exited.connect(_clear)
