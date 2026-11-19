(* See the file COPYRIGHT for a full description. *)

(* This fork: like GenWord.mg, instantiated with its own interface as
   Impl.  The compiler compiles the calls below inline, so these are
   wrappers for when the procedures are used as values. *)

GENERIC MODULE GenWordN(Impl);

IMPORT Word, Long;

PROCEDURE Plus (x, y: T): T     = BEGIN RETURN Impl.Plus (x, y)   END Plus;
PROCEDURE Times (x, y: T): T    = BEGIN RETURN Impl.Times (x, y)  END Times;
PROCEDURE Minus (x, y: T): T    = BEGIN RETURN Impl.Minus (x, y)  END Minus;
PROCEDURE Divide (x, y: T): T   = BEGIN RETURN Impl.Divide (x, y) END Divide;
PROCEDURE Mod (x, y: T): T      = BEGIN RETURN Impl.Mod (x, y)    END Mod;
PROCEDURE LT (x, y: T): BOOLEAN = BEGIN RETURN Impl.LT (x, y)     END LT;
PROCEDURE LE (x, y: T): BOOLEAN = BEGIN RETURN Impl.LE (x, y)     END LE;
PROCEDURE GT (x, y: T): BOOLEAN = BEGIN RETURN Impl.GT (x, y)     END GT;
PROCEDURE GE (x, y: T): BOOLEAN = BEGIN RETURN Impl.GE (x, y)     END GE;
PROCEDURE And (x, y: T): T      = BEGIN RETURN Impl.And (x, y)    END And;
PROCEDURE Or (x, y: T): T       = BEGIN RETURN Impl.Or (x, y)     END Or;
PROCEDURE Xor (x, y: T): T      = BEGIN RETURN Impl.Xor (x, y)    END Xor;
PROCEDURE Not (x: T): T         = BEGIN RETURN Impl.Not (x)       END Not;

PROCEDURE Shift (x: T; n: INTEGER): T
 = BEGIN RETURN Impl.Shift (x, n) END Shift;

PROCEDURE LeftShift (x: T; n: [0..Size-1]): T
 = BEGIN RETURN Impl.LeftShift (x, n) END LeftShift;

PROCEDURE RightShift (x: T; n: [0..Size-1]): T
 = BEGIN RETURN Impl.RightShift (x, n) END RightShift;

PROCEDURE Rotate (x: T; n: INTEGER): T
 = BEGIN RETURN Impl.Rotate (x, n) END Rotate;

PROCEDURE LeftRotate (x: T; n: [0..Size-1]): T
 = BEGIN RETURN Impl.LeftRotate (x, n) END LeftRotate;

PROCEDURE RightRotate (x: T; n: [0..Size-1]): T
 = BEGIN RETURN Impl.RightRotate (x, n) END RightRotate;

PROCEDURE Extract (x: T; i, n: CARDINAL): T
 = BEGIN RETURN Impl.Extract (x, i, n) END Extract;

PROCEDURE Insert (x, y: T; i, n: CARDINAL): T
 = BEGIN RETURN Impl.Insert (x, y, i, n) END Insert;

PROCEDURE Wrap (x: LONGINT): T  = BEGIN RETURN Impl.Wrap (x)      END Wrap;
PROCEDURE FromWord (w: Word.T): T = BEGIN RETURN Impl.FromWord (w) END FromWord;
PROCEDURE ToWord (x: T): Word.T = BEGIN RETURN Impl.ToWord (x)    END ToWord;
PROCEDURE FromLong (l: Long.T): T = BEGIN RETURN Impl.FromLong (l) END FromLong;
PROCEDURE ToLong (x: T): Long.T = BEGIN RETURN Impl.ToLong (x)    END ToLong;

PROCEDURE Equal (a, b: T): BOOLEAN = BEGIN RETURN Impl.Equal (a, b) END Equal;
PROCEDURE Hash (a: T): Word.T   = BEGIN RETURN Impl.Hash (a)      END Hash;
PROCEDURE Compare (a, b: T): [-1..1]
 = BEGIN RETURN Impl.Compare (a, b) END Compare;

BEGIN
END GenWordN.
