#!/bin/bash
# buildtime.sh LABEL VER O0|O2: build every package in pkgs.txt in C mode
# with driver bin-VER; record wall, cpu, text size and C++ size.
W=${W:?set W to the scratch directory (see README.md)}; LABEL=$1; V=$2; OPT=$3
PRE=$W/bin-$V; [ $OPT = O2 ] && PRE=$W/o2:$PRE
export PATH=$PRE:/usr/bin:/bin M3CONFIG=$W/bin-$V/cm3.cfg
OUT=$W/m/$LABEL.tsv; mkdir -p $W/m; : > $OUT
while read n d; do
  cd $W/wt-new/$d || exit 1
  cm3 -realclean >/dev/null 2>&1
  /usr/bin/time -o $W/m/t -f "%e %U %S" cm3 -build -keep > $W/m/$LABEL.$n.log 2>&1 || echo "FAILED $LABEL $n" >&2
  read e us sy < $W/m/t
  read txt dat < <(size AMD64_LINUX/*.o | awk 'NR>1{t+=$1; d+=$2+$3} END{print t+0, d+0}')
  srcsz=$(cat AMD64_LINUX/*.cpp AMD64_LINUX/*.c 2>/dev/null | wc -c)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" $n $e $us $sy $txt $dat $srcsz >> $OUT
done < $W/pkgs.txt
awk -F'\t' '{e+=$2; c+=$3+$4; t+=$5; d+=$6; s+=$7} END{printf "%s: wall %.1fs cpu %.1fs text %d data %d gen-src %d\n", L, e, c, t, d, s}' L=$LABEL $OUT
