(* See the file COPYRIGHT for a full description. *)

(* This fork: see M3CFixedType.i3. *)

MODULE M3CFixedType;

IMPORT Text;
IMPORT M3AST_AS, M3AST_SM;
IMPORT M3AST_LX_F, M3AST_AS_F;
IMPORT SeqM3AST_AS_IMPORTED, SeqM3AST_AS_Import_item,
       SeqM3AST_AS_DECL_REVL, SeqM3AST_AS_TYPE_DECL;
IMPORT M3CId;

PROCEDURE Same(t1, t2: M3AST_SM.TYPE_SPEC_UNSET): BOOLEAN =
  BEGIN
    TYPECASE t1 OF
    | M3AST_AS.Fixed_type(f1) =>
        TYPECASE t2 OF
        | M3AST_AS.Fixed_type(f2) =>
            RETURN f1.fx_bits = f2.fx_bits AND f1.fx_signed = f2.fx_signed;
        ELSE
          RETURN FALSE;
        END;
    ELSE
      RETURN FALSE;
    END;
  END Same;

(* If "name" is "WordNRep" or "SignedNRep" for N in {8, 16, 32, 64}, set
   "bits" and "signed" and return the name of the type's interface
   ("WordN" or "SignedN"); otherwise return NIL. *)
PROCEDURE RepName(name: TEXT; VAR bits: INTEGER; VAR signed: BOOLEAN): TEXT =
  CONST Widths = ARRAY OF INTEGER {8, 16, 32, 64};
  VAR prefix: TEXT;
  BEGIN
    FOR s := FALSE TO TRUE DO
      IF s THEN prefix := "Signed" ELSE prefix := "Word" END;
      FOR i := FIRST(Widths) TO LAST(Widths) DO
        WITH intf = prefix & Fmt(Widths[i]) DO
          IF Text.Equal(name, intf & "Rep") THEN
            bits := Widths[i];
            signed := s;
            RETURN intf;
          END;
        END;
      END;
    END;
    RETURN NIL;
  END RepName;

PROCEDURE Fmt(n: INTEGER): TEXT =
  BEGIN
    CASE n OF
    | 8 => RETURN "8";
    | 16 => RETURN "16";
    | 32 => RETURN "32";
    ELSE RETURN "64";
    END;
  END Fmt;

PROCEDURE Transform(cu: M3AST_AS.Compilation_Unit) =
  VAR
    bits: INTEGER;
    signed: BOOLEAN;
    intf: TEXT;
  BEGIN
    IF cu = NIL THEN RETURN END;
    TYPECASE cu.as_root OF
    | M3AST_AS.Interface(unit) =>
        IF unit.as_id = NIL OR unit.as_id.lx_symrep = NIL THEN RETURN END;
        intf := RepName(M3CId.ToText(unit.as_id.lx_symrep), bits, signed);
        IF intf = NIL THEN RETURN END;
        DropImport(unit, intf);
        IF unit.as_block # NIL THEN
          ReplaceT(unit.as_block, bits, signed);
        END;
    ELSE
    END;
  END Transform;

(* Remove the import of "intf" from "unit". *)
PROCEDURE DropImport(unit: M3AST_AS.Interface; intf: TEXT) =
  VAR
    imports := SeqM3AST_AS_IMPORTED.Null;
    iter := SeqM3AST_AS_IMPORTED.NewIter(unit.as_import_s);
    imported: M3AST_AS.IMPORTED;
  BEGIN
    WHILE SeqM3AST_AS_IMPORTED.Next(iter, imported) DO
      TYPECASE imported OF
      | M3AST_AS.Simple_import(simple) =>
          VAR
            items := SeqM3AST_AS_Import_item.Null;
            iterItem := SeqM3AST_AS_Import_item.NewIter(
                            simple.as_import_item_s);
            item: M3AST_AS.Import_item;
          BEGIN
            WHILE SeqM3AST_AS_Import_item.Next(iterItem, item) DO
              IF NOT Text.Equal(
                       M3CId.ToText(item.as_intf_id.lx_symrep), intf) THEN
                SeqM3AST_AS_Import_item.AddRear(items, item);
              END;
            END;
            IF NOT SeqM3AST_AS_Import_item.Empty(items) THEN
              simple.as_import_item_s := items;
              SeqM3AST_AS_IMPORTED.AddRear(imports, simple);
            END;
          END;
      | M3AST_AS.From_import(from) =>
          IF NOT Text.Equal(M3CId.ToText(from.as_intf_id.lx_symrep), intf) THEN
            SeqM3AST_AS_IMPORTED.AddRear(imports, from);
          END;
      ELSE
        SeqM3AST_AS_IMPORTED.AddRear(imports, imported);
      END;
    END;
    unit.as_import_s := imports;
  END DropImport;

(* Make the type "T" declared in "block" a fixed-width type. *)
PROCEDURE ReplaceT(block: M3AST_AS.Block; bits: INTEGER; signed: BOOLEAN) =
  VAR
    iter := SeqM3AST_AS_DECL_REVL.NewIter(block.as_decl_s);
    decl: M3AST_AS.DECL_REVL;
  BEGIN
    WHILE SeqM3AST_AS_DECL_REVL.Next(iter, decl) DO
      TYPECASE decl OF
      | M3AST_AS.Type_decl_s(typeDecls) =>
          VAR
            iterType := SeqM3AST_AS_TYPE_DECL.NewIter(
                            typeDecls.as_type_decl_s);
            typeDecl: M3AST_AS.TYPE_DECL;
          BEGIN
            WHILE SeqM3AST_AS_TYPE_DECL.Next(iterType, typeDecl) DO
              IF typeDecl.as_id # NIL AND
                 Text.Equal(M3CId.ToText(typeDecl.as_id.lx_symrep), "T") THEN
                VAR fixed: M3AST_AS_F.Fixed_type :=
                      NEW(M3AST_AS.Fixed_type).init();
                BEGIN
                  fixed.fx_bits := bits;
                  fixed.fx_signed := signed;
                  typeDecl.as_type := fixed;
                END;
              END;
            END;
          END;
      ELSE
      END;
    END;
  END ReplaceT;

BEGIN
END M3CFixedType.
