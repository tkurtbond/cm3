(* The program half of the mixed-linking test: exercise mixlib (Ops and
   Abi) and print the results, which must be the same whichever back
   end built each half (../../expected-output). *)

MODULE Main;

IMPORT IO, Fmt, Word, Long, Ops, Abi;

<*FATAL Abi.Fail, Abi.Plain*>  (* the calls that do raise are in TRYs *)

PROCEDURE P (label, value: TEXT) =
  BEGIN IO.Put (label & " = " & value & "\n") END P;

PROCEDURE I (i: INTEGER): TEXT =
  BEGIN RETURN Fmt.Int (i) END I;

PROCEDURE L (i: LONGINT): TEXT =
  BEGIN RETURN Fmt.LongInt (i) END L;

PROCEDURE H (w: Word.T): TEXT =
  BEGIN RETURN "16_" & Fmt.Unsigned (w, 16) END H;

PROCEDURE B (b: BOOLEAN): TEXT =
  BEGIN RETURN Fmt.Bool (b) END B;

PROCEDURE R (x: LONGREAL): TEXT =
  BEGIN RETURN Fmt.LongReal (x, Fmt.Style.Fix, 3) END R;

PROCEDURE S (READONLY s: Ops.BigSet): TEXT =
  VAR t := "{";  first := TRUE;
  BEGIN
    FOR i := 0 TO 199 DO
      IF i IN s THEN
        IF NOT first THEN t := t & "," END;
        t := t & I (i);  first := FALSE;
      END;
    END;
    RETURN t & "}";
  END S;

PROCEDURE SS (s: Ops.SmallSet): TEXT =
  VAR t := "{";  first := TRUE;
  BEGIN
    FOR i := 0 TO 31 DO
      IF i IN s THEN
        IF NOT first THEN t := t & "," END;
        t := t & I (i);  first := FALSE;
      END;
    END;
    RETURN t & "}";
  END SS;

CONST
  X = 16_0123456789ABCDEF;
  Ns = ARRAY OF INTEGER {0, 1, 4, 63, 64, 65, 100, -1, -4, -63, -64, -65,
                         FIRST (INTEGER), LAST (INTEGER)};
  Ds = ARRAY OF INTEGER {7, -7, 8, -8, 1, -1, 0, LAST (INTEGER),
                         FIRST (INTEGER) + 1};
  Rs = ARRAY OF LONGREAL {0.0d0, 0.5d0, -0.5d0, 1.5d0, -1.5d0, 2.5d0,
                          -2.5d0, 2.7d0, -2.7d0, 1.0d15};

PROCEDURE TestOps () =
  VAR p: Ops.Packed;  a, b: Ops.BigSet;
  BEGIN
    FOR k := FIRST (Ns) TO LAST (Ns) DO
      WITH n = Ns[k] DO
        P ("Shift(X," & I (n) & ")", H (Ops.Shift (X, n)));
        P ("Rotate(X," & I (n) & ")", H (Ops.Rotate (X, n)));
        P ("LongShift(-1L," & I (n) & ")", L (Ops.LongShift (-1L, n)));
      END;
    END;
    FOR n := 0 TO 63 BY 7 DO
      P ("LeftShift(X," & I (n) & ")", H (Ops.LeftShift (X, n)));
      P ("RightShift(-1," & I (n) & ")", H (Ops.RightShift (-1, n)));
    END;
    P ("RightShift(-1,63)", H (Ops.RightShift (-1, 63)));

    FOR k := FIRST (Ds) TO LAST (Ds) DO
      FOR m := FIRST (Ds) TO LAST (Ds) DO
        WITH x = Ds[k], y = Ds[m] DO
          IF y # 0 THEN
            P (I (x) & " DIV " & I (y), I (Ops.Div (x, y)));
            P (I (x) & " MOD " & I (y), I (Ops.Mod (x, y)));
            P (I (x) & " LDIV " & I (y),
               L (Ops.LongDiv (VAL (x, LONGINT), VAL (y, LONGINT))));
            P (I (x) & " LMOD " & I (y),
               L (Ops.LongMod (VAL (x, LONGINT), VAL (y, LONGINT))));
            P (H (x) & " UDIV " & H (y), H (Ops.UDiv (x, y)));
            P (H (x) & " UMOD " & H (y), H (Ops.UMod (x, y)));
            P (H (x) & " ULESS " & H (y), B (Ops.ULess (x, y)));
          END;
        END;
      END;
      P (I (Ds[k]) & " DIV 8", I (Ops.Div8 (Ds[k])));
      P (I (Ds[k]) & " MOD 8", I (Ops.Mod8 (Ds[k])));
      P ("ABS(" & I (Ds[k]) & ")", I (Ops.Abs (Ds[k])));
      P ("MIN(" & I (Ds[k]) & ",3)", I (Ops.Min (Ds[k], 3)));
      P ("MAX(" & I (Ds[k]) & ",-3)", I (Ops.Max (Ds[k], -3)));
      P ("FLOAT(" & I (Ds[k]) & ")",
         Fmt.Real (Ops.ToReal (Ds[k]), Fmt.Style.Sci, 6));
    END;
    P ("FIRST(INTEGER) DIV 1", I (Ops.Div (FIRST (INTEGER), 1)));
    P ("AddGt(LAST(INTEGER))", B (Ops.AddGt (LAST (INTEGER))));
    P ("LongAddGt(LAST(LONGINT))", B (Ops.LongAddGt (LAST (LONGINT))));
    P ("SubLt(FIRST(INTEGER))", B (Ops.SubLt (FIRST (INTEGER))));
    P ("MulGt(LAST(INTEGER))", B (Ops.MulGt (LAST (INTEGER))));
    P ("NegLt(FIRST(INTEGER))", B (Ops.NegLt (FIRST (INTEGER))));
    P ("AbsLt(FIRST(INTEGER))", B (Ops.AbsLt (FIRST (INTEGER))));

    P ("Extract(X,0,64)", H (Ops.Extract (X, 0, 64)));
    P ("Extract(X,60,4)", H (Ops.Extract (X, 60, 4)));
    P ("Extract(X,8,0)", H (Ops.Extract (X, 8, 0)));
    P ("Extract(X,13,17)", H (Ops.Extract (X, 13, 17)));
    P ("Extract3_5(X)", H (Ops.Extract3_5 (X)));
    P ("Insert(X,-1,0,64)", H (Ops.Insert (X, -1, 0, 64)));
    P ("Insert(X,0,4,8)", H (Ops.Insert (X, 0, 4, 8)));
    P ("Insert(X,-1,63,1)", H (Ops.Insert (X, -1, 63, 1)));
    P ("Insert(X,16_FFF,10,0)", H (Ops.Insert (X, 16_FFF, 10, 0)));
    P ("Insert60_4(X,-1)", H (Ops.Insert60_4 (X, -1)));
    p := Ops.Packed {a := -4, b := 31, c := -64, d := 8191};
    P ("p.a", I (Ops.GetA (p)));
    P ("p.c", I (Ops.GetC (p)));
    Ops.SetC (p, 63);
    P ("p.c := 63", I (Ops.GetC (p)) & " " & I (p.a) & " " & I (p.b)
                    & " " & I (p.d));
    Ops.SetC (p, -1);
    Ops.SetD (p, 1234);
    P ("p.c := -1, p.d := 1234", I (p.a) & " " & I (p.b) & " " & I (p.c)
                                 & " " & I (p.d));
    p.a := 3;
    P ("p.a := 3", I (Ops.GetA (p)) & " " & I (Ops.GetC (p)));

    a := Ops.Range (60, 140);
    b := Ops.BigSet {0, 63, 64, 127, 128, 129, 198, 199};
    P ("a", S (a));
    P ("b", S (b));
    P ("a+b", S (Ops.Union (a, b)));
    P ("a-b", S (Ops.Difference (a, b)));
    P ("a*b", S (Ops.Intersection (a, b)));
    P ("a/b", S (Ops.SymDifference (a, b)));
    P ("Range(0,199)=full", B (Ops.Equal (Ops.Range (0, 199),
                                           Ops.BigSet {0 .. 199})));
    P ("Range(5,4)", S (Ops.Range (5, 4)));
    P ("Range(199,199)", S (Ops.Range (199, 199)));
    P ("Singleton(128)", S (Ops.Singleton (128)));
    P ("63 IN a", B (Ops.Member (a, 63)));
    P ("59 IN a", B (Ops.Member (a, 59)));
    P ("199 IN b", B (Ops.Member (b, 199)));
    P ("a*b <= a", B (Ops.Subset (Ops.Intersection (a, b), a)));
    P ("a <= b", B (Ops.Subset (a, b)));
    P ("a < a", B (Ops.ProperSubset (a, a)));
    P ("a*b < a", B (Ops.ProperSubset (Ops.Intersection (a, b), a)));
    P ("a = a", B (Ops.Equal (a, a)));
    P ("a = b", B (Ops.Equal (a, b)));
    P ("SmallUnion", SS (Ops.SmallUnion (Ops.SmallSet {0, 31},
                                         Ops.SmallRange (3, 9))));
    P ("SmallRange(0,31)", SS (Ops.SmallRange (0, 31)));
    P ("SmallRange(31,31)", SS (Ops.SmallRange (31, 31)));
    P ("31 IN {31}", B (Ops.SmallMember (Ops.SmallSet {31}, 31)));
    P ("0 IN {31}", B (Ops.SmallMember (Ops.SmallSet {31}, 0)));
    P ("{1} <= {1,2}", B (Ops.SmallSubset (Ops.SmallSet {1},
                                           Ops.SmallSet {1, 2})));
    P ("{3} <= {1,2}", B (Ops.SmallSubset (Ops.SmallSet {3},
                                           Ops.SmallSet {1, 2})));

    FOR i := -5 TO 15 DO P ("Classify(" & I (i) & ")", I (Ops.Classify (i))) END;
    FOR i := 99 TO 101 DO P ("Classify(" & I (i) & ")", I (Ops.Classify (i))) END;
    FOR i := 999999 TO 1000003 DO
      P ("Classify(" & I (i) & ")", I (Ops.Classify (i)));
    END;
    P ("Classify(FIRST)", I (Ops.Classify (FIRST (INTEGER))));
    P ("Classify(LAST)", I (Ops.Classify (LAST (INTEGER))));
    FOR c := FIRST (CHAR) TO LAST (CHAR) BY 17 DO
      P ("ClassifyChar(" & I (ORD (c)) & ")", Ops.ClassifyChar (c));
    END;
    P ("ClassifyChar(255)", Ops.ClassifyChar ('\377'));

    FOR k := FIRST (Rs) TO LAST (Rs) DO
      WITH x = Rs[k] DO
        P ("FLOOR(" & R (x) & ")", I (Ops.Floor (x)));
        P ("CEILING(" & R (x) & ")", I (Ops.Ceiling (x)));
        P ("ROUND(" & R (x) & ")", I (Ops.Round (x)));
        P ("TRUNC(" & R (x) & ")", I (Ops.Trunc (x)));
      END;
    END;
    P ("7.5 MOD 2.0", Fmt.Real (Ops.RealMod (7.5, 2.0)));
    P ("-7.5 MOD 2.0", Fmt.Real (Ops.RealMod (-7.5, 2.0)));
    P ("7.5 MOD -2.0", Fmt.Real (Ops.RealMod (7.5, -2.0)));
  END TestOps;

VAR counter := 0;

PROCEDURE Count (x: INTEGER): INTEGER =
  BEGIN INC (counter); RETURN x + 100 END Count;

PROCEDURE RaiseFail (x: INTEGER): INTEGER RAISES {Abi.Fail} =
  BEGIN RAISE Abi.Fail (x) END RaiseFail;

PROCEDURE RaiseThrough (x: INTEGER): INTEGER RAISES {Abi.Fail, Abi.Plain} =
  BEGIN Abi.Raise (x); RETURN -1 END RaiseThrough;

PROCEDURE TestAbi () =
  VAR
    pair := Abi.SwapPair (Abi.Pair {1, 2});
    tiny := Abi.NextTiny (Abi.Tiny {'a', 'y', '0'});
    mixed := Abi.MakeMixed (1.5, 200, 0.25d0);
    big := Abi.Big {1, 2, 3, 4, 5, 6, 7, 8, 9, 10};
    open := NEW (REF ARRAY OF INTEGER, 5);
    log: TEXT;
    shape: Abi.Shape;
    base := 1000;
  PROCEDURE AddBase (x: INTEGER): INTEGER =
    BEGIN RETURN x + base END AddBase;
  BEGIN
    P ("SwapPair", I (pair.a) & " " & I (pair.b));
    P ("NextTiny", Fmt.Char (tiny.c1) & Fmt.Char (tiny.c2) & Fmt.Char (tiny.c3));
    P ("MakeMixed", Fmt.Real (mixed.r) & " " & I (mixed.i) & " " & R (mixed.d));
    P ("MixedSum", R (Abi.MixedSum (mixed, 0.125, 1.0d3, 2.0x0)));
    P ("SumBig", I (Abi.SumBig (big)));
    big := Abi.Reverse (big);
    P ("Reverse", I (big[0]) & " " & I (big[9]));
    Abi.Fill (open^, 10);
    P ("Fill/SumOpen", I (Abi.SumOpen (open^)));
    P ("SumOpen(SUBARRAY)", I (Abi.SumOpen (SUBARRAY (big, 2, 3))));
    P ("Scalars", L (Abi.Scalars (TRUE, 'A', W'\x263A', 5000000000L, -128,
                                  65535, 2.5)));
    P ("Many", R (Abi.Many (1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
                            0.5d0, 1.5d0, 2.5d0, 3.5d0, 4.5d0, 5.5d0,
                            6.5d0, 7.5d0, 8.5d0, 9.5d0)));
    P ("NextColor(Blue)", I (ORD (Abi.NextColor (Abi.Color.Blue))));
    P ("Complement({Green})",
       B (Abi.Complement (Abi.Colors {Abi.Color.Green})
            = Abi.Colors {Abi.Color.Red, Abi.Color.Blue}));

    P ("Apply(Count)", I (Abi.Apply (Count, 5)) & " " & I (counter));
    P ("Apply(AddBase)", I (Abi.Apply (AddBase, 5)));
    P ("Apply(Square())", I (Abi.Apply (Abi.Square (), 12)));
    P ("Square()(7)", I (Abi.Square () (7)));
    P ("ApplyLocal(AddBase)", I (Abi.ApplyLocal (4, AddBase)));

    P ("Catch(RaiseFail)", Abi.Catch (RaiseFail, 42));
    P ("Catch(RaiseThrough,7)", Abi.Catch (RaiseThrough, 7));
    P ("Catch(RaiseThrough,0)", Abi.Catch (RaiseThrough, 0));
    P ("Catch(AddBase)", Abi.Catch (AddBase, 1));
    TRY
      EVAL Abi.Apply (RaiseThrough, 9);
      P ("Apply(RaiseThrough)", "no exception");
    EXCEPT
    | Abi.Fail (c) => P ("Apply(RaiseThrough)", "Fail(" & I (c) & ")");
    | Abi.Plain => P ("Apply(RaiseThrough)", "Plain");
    END;
    log := "";
    TRY
      Abi.Finally (log, 3);
    EXCEPT
    | Abi.Fail (c) => log := log & " Fail(" & I (c) & ")";
    | Abi.Plain => log := log & " Plain";
    END;
    P ("Finally(3)", log);
    log := "";
    TRY Abi.Finally (log, -1) EXCEPT Abi.Fail, Abi.Plain => END;
    P ("Finally(-1)", log);

    shape := Abi.NewSquare (1.5d0);
    P ("Area", R (Abi.Area (shape)));
    P ("shape.area", R (shape.area ()));
    P ("shape.describe", shape.describe ());
    P ("Concat", Abi.Concat ("abc", "de"));
  END TestAbi;

BEGIN
  TestOps ();
  TestAbi ();
  P ("Long.Shift", L (Long.Shift (1L, 40)));
END Main.
