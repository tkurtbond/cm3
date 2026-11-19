(* This fork: SHA256 (FIPS PUB 180-4) on Word32.T, for test p301. *)

INTERFACE Sha256W32;

PROCEDURE FromText (txt: TEXT): TEXT;
(* The digest of the characters of txt, read as bytes, as 64 lower-case
   hexadecimal digits. *)

END Sha256W32.
