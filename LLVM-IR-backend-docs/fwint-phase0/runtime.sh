#!/bin/bash
# runtime.sh: build each benchmark with each driver at gcc -O0 and -O2 (C
# mode), then time 3 runs of each, interleaved, pinned to CPU 2; print
# the minimum wall time and check that outputs agree.
W=${W:?set W to the scratch directory (see README.md)}
PROGS="Sieve NBody Trees QSort Hash"; CFGS="old-O0 new-O0 old-O2 new-O2"
for c in $CFGS; do
  v=${c%-*}; o=${c#*-}; PRE=$W/bin-$v; [ $o = O2 ] && PRE=$W/o2:$PRE
  for p in $PROGS; do
    rm -rf $W/rt/$c/$p; mkdir -p $W/rt/$c; cp -a $W/benchsrc/$p $W/rt/$c/$p
    (cd $W/rt/$c/$p && PATH=$PRE:/usr/bin:/bin M3CONFIG=$W/bin-$v/cm3.cfg cm3 -build > build.log 2>&1) || echo "BUILD FAILED $c $p"
  done
done
: > $W/m/runtime.raw
for rep in 1 2 3; do for p in $PROGS; do for c in $CFGS; do
  exe=$(ls $W/rt/$c/$p/AMD64_LINUX/ | grep -v '\.' | grep -v '^_' | head -1)
  /usr/bin/time -o $W/m/t -f %e taskset -c 2 $W/rt/$c/$p/AMD64_LINUX/$exe > $W/rt/$c/$p/out.txt 2>&1
  echo "$p $c $(cat $W/m/t)" >> $W/m/runtime.raw
done; done; done
for p in $PROGS; do
  for c in $CFGS; do cmp -s $W/rt/old-O0/$p/out.txt $W/rt/$c/$p/out.txt || echo "OUTPUT DIFFERS $p $c"; done
done
awk '{k=$1" "$2; if(!(k in m)||$3<m[k]) m[k]=$3} END{for(k in m) print k, m[k]}' $W/m/runtime.raw | sort
