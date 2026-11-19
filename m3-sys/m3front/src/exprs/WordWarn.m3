(* This fork: see WordWarn.i3. *)

MODULE WordWarn;

IMPORT Expr, Type, TypeRep, NamedType, Value, ValueRep, Error, Text;
IMPORT NamedExpr, M3ID, QualifyExpr, SubscriptExpr, DerefExpr, CallExpr, ProcType;

PROCEDURE Check (a, b: Expr.T;  op, unsigned: TEXT) =
  VAR intf := Interface (Declared (a));
  BEGIN
    IF intf = NIL THEN intf := Interface (Declared (b)) END;
    IF intf # NIL THEN
      Error.Warn (0, op & " on " & intf & ".T is signed; " & intf & "."
                       & unsigned & " is unsigned");
    END;
  END Check;

PROCEDURE Declared (e: Expr.T): Type.T =
  (* The declared type of e, with its names.  Expr.TypeOf has them for
     variables and formals, but checking strips them from fields, array
     elements and REF targets, so these come from the wwDeclared fields;
     a call's comes from its procedure type, which keeps them, and a
     WITH variable's from NoteWith. *)
  VAR v: Value.T;  a: Expr.T;  t: Type.T;  id: M3ID.T;
  BEGIN
    IF e = NIL THEN RETURN NIL END;
    IF NamedExpr.Split (e, id, v) THEN
      v := Value.Base (v);
      IF (v # NIL) AND (Value.ClassOf (v) = Value.Class.Var)
        AND (v.wwDeclared # NIL) THEN
        RETURN v.wwDeclared; (* a WITH variable *)
      END;
      RETURN Expr.TypeOf (e);
    END;
    IF QualifyExpr.Split (e, v) THEN
      IF (v # NIL) AND (Value.ClassOf (v) = Value.Class.Field)
        AND (v.wwDeclared # NIL) THEN
        RETURN v.wwDeclared;
      END;
    ELSIF SubscriptExpr.Split (e, a) THEN
      t := Type.Base (Expr.TypeOf (a));
      IF (t # NIL) AND (t.wwDeclared # NIL)
        AND ((t.info.class = Type.Class.Array)
             OR (t.info.class = Type.Class.OpenArray)) THEN
        RETURN t.wwDeclared;
      END;
    ELSIF DerefExpr.Split (e, a) THEN
      t := Type.Base (Expr.TypeOf (a));
      IF (t # NIL) AND (t.wwDeclared # NIL)
        AND (t.info.class = Type.Class.Ref) THEN
        RETURN t.wwDeclared;
      END;
    ELSE
      TYPECASE e OF
      | CallExpr.T (c) =>
          t := Type.Base (Expr.TypeOf (c.proc));
          IF ProcType.Is (t) THEN
            t := ProcType.Result (t);
            IF t # NIL THEN RETURN t END;
          END;
      ELSE
      END;
    END;
    RETURN Expr.TypeOf (e);
  END Declared;

PROCEDURE NoteWith (var: Value.T;  e: Expr.T) =
  BEGIN
    IF var # NIL THEN var.wwDeclared := Declared (e) END;
  END NoteWith;

PROCEDURE Interface (t: Type.T): TEXT =
  (* "Word" or "Long" if t is a name for Word.T or Long.T, else NIL. *)
  VAR v: Value.T;  name: TEXT;
  BEGIN
    FOR i := 1 TO 20 DO (* a bound, in case of illegal recursion *)
      IF t = NIL THEN RETURN NIL END;
      IF t.info.class = Type.Class.Packed THEN
        (* BITS n FOR Word.T *)
        IF t.wwDeclared = NIL THEN RETURN NIL END;
        t := t.wwDeclared;
      ELSE
        IF NOT NamedType.SplitV (t, v) OR (v = NIL) THEN RETURN NIL END;
        name := Value.GlobalName (v);
        IF Text.Equal (name, "Word.T") THEN RETURN "Word" END;
        IF Text.Equal (name, "Long.T") THEN RETURN "Long" END;
        v := Value.Base (v); (* a name seen through EXPORTS is a proxy *)
        IF (v # NIL) AND (Value.ClassOf (v) = Value.Class.Type)
          AND (v.wwDeclared # NIL) THEN
          t := v.wwDeclared; (* an alias: TYPE U = Word.T *)
        ELSE
          t := NamedType.Strip (t);
        END;
      END;
    END;
    RETURN NIL;
  END Interface;

BEGIN
END WordWarn.
