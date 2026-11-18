MODULE NBody EXPORTS Main;
IMPORT IO, Fmt, Math;
CONST Pi = 3.141592653589793D0; SolarMass = 4.0D0 * Pi * Pi; Days = 365.24D0;
TYPE Body = RECORD x, y, z, vx, vy, vz, m: LONGREAL END;
VAR b := ARRAY [0..4] OF Body {
  Body {0.0D0, 0.0D0, 0.0D0, 0.0D0, 0.0D0, 0.0D0, SolarMass},
  Body {4.84143144246472090D+00, -1.16032004402742839D+00, -1.03622044471123109D-01,
        1.66007664274403694D-03*Days, 7.69901118419740425D-03*Days, -6.90460016972063023D-05*Days,
        9.54791938424326609D-04*SolarMass},
  Body {8.34336671824457987D+00, 4.12479856412430479D+00, -4.03523417114321381D-01,
        -2.76742510726862411D-03*Days, 4.99852801234917238D-03*Days, 2.30417297573763929D-05*Days,
        2.85885980666130812D-04*SolarMass},
  Body {1.28943695621391310D+01, -1.51111514016986312D+01, -2.23307578892655734D-01,
        2.96460137564761618D-03*Days, 2.37847173959480950D-03*Days, -2.96589568540237556D-05*Days,
        4.36624404335156298D-05*SolarMass},
  Body {1.53796971148509165D+01, -2.59193146099879641D+01, 1.79258772950371181D-01,
        2.68067772490389322D-03*Days, 1.62824170038242295D-03*Days, -9.51592254519715870D-05*Days,
        5.15138902046611451D-05*SolarMass}};
PROCEDURE Energy (): LONGREAL =
  VAR e := 0.0D0; dx, dy, dz: LONGREAL;
  BEGIN
    FOR i := 0 TO 4 DO
      WITH a = b[i] DO
        e := e + 0.5D0 * a.m * (a.vx*a.vx + a.vy*a.vy + a.vz*a.vz);
        FOR j := i + 1 TO 4 DO
          dx := a.x - b[j].x; dy := a.y - b[j].y; dz := a.z - b[j].z;
          e := e - a.m * b[j].m / Math.sqrt (dx*dx + dy*dy + dz*dz);
        END;
      END;
    END;
    RETURN e;
  END Energy;
PROCEDURE Advance (dt: LONGREAL) =
  VAR dx, dy, dz, d2, mag: LONGREAL;
  BEGIN
    FOR i := 0 TO 4 DO
      FOR j := i + 1 TO 4 DO
        dx := b[i].x - b[j].x; dy := b[i].y - b[j].y; dz := b[i].z - b[j].z;
        d2 := dx*dx + dy*dy + dz*dz;
        mag := dt / (d2 * Math.sqrt (d2));
        b[i].vx := b[i].vx - dx * b[j].m * mag; b[i].vy := b[i].vy - dy * b[j].m * mag;
        b[i].vz := b[i].vz - dz * b[j].m * mag;
        b[j].vx := b[j].vx + dx * b[i].m * mag; b[j].vy := b[j].vy + dy * b[i].m * mag;
        b[j].vz := b[j].vz + dz * b[i].m * mag;
      END;
    END;
    FOR i := 0 TO 4 DO
      b[i].x := b[i].x + dt * b[i].vx; b[i].y := b[i].y + dt * b[i].vy; b[i].z := b[i].z + dt * b[i].vz;
    END;
  END Advance;
VAR px, py, pz := 0.0D0;
BEGIN
  FOR i := 0 TO 4 DO
    px := px + b[i].vx * b[i].m; py := py + b[i].vy * b[i].m; pz := pz + b[i].vz * b[i].m;
  END;
  b[0].vx := -px / SolarMass; b[0].vy := -py / SolarMass; b[0].vz := -pz / SolarMass;
  IO.Put (Fmt.LongReal (Energy (), Fmt.Style.Fix, 9) & "\n");
  FOR i := 1 TO 20000000 DO Advance (0.01D0) END;
  IO.Put (Fmt.LongReal (Energy (), Fmt.Style.Fix, 9) & "\n");
END NBody.
