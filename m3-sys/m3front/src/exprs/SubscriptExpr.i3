(* Copyright (C) 1992, Digital Equipment Corporation           *)
(* All rights reserved.                                        *)
(* See the file COPYRIGHT for a full description.              *)

(* File: SubscriptExpr.i3                                      *)
(* Last Modified On Mon Jul 31 13:22:38 1989 By kalsow         *)

INTERFACE SubscriptExpr;

IMPORT Expr;

PROCEDURE New (a, b: Expr.T): Expr.T;

PROCEDURE Split (e: Expr.T;  VAR a: Expr.T): BOOLEAN;
(* This fork: if 'e' is 'a[b]', set 'a' and return TRUE.  After 'e' is
   checked, an implicit dereference is explicit in 'a'. *)

END SubscriptExpr.
