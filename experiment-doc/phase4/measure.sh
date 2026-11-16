#!/bin/bash
# measure.sh LABEL MODE [cm3 flags...]: build (no ship) every headless
# package; record wall/cpu time and object sizes per package.
W=${W:?set W to the scratch directory (see experiment-doc/phase4-results.md)}
LABEL=$1; MODE=$2; shift 2
export PATH=${PREPATH}$W/prefix/bin:/usr/bin:/bin
OUT=$W/m/$LABEL.tsv; mkdir -p $W/m; : > $OUT
while read n d; do
  cd $W/src/$d || exit 1
  cm3 -realclean >/dev/null 2>&1
  /usr/bin/time -o $W/m/t -f "%e %U %S" cm3 -build -DM3_BACKEND_MODE=$MODE "$@" > $W/m/$LABEL.$n.log 2>&1 || echo "FAILED $n" >&2
  read e us sy < $W/m/t
  txt=0; dat=0
  if ls AMD64_LINUX/*.o >/dev/null 2>&1; then
    read txt dat < <(size AMD64_LINUX/*.o | awk 'NR>1{t+=$1; d+=$2+$3} END{print t, d}')
  fi
  srcsz=$(ls AMD64_LINUX/*.ll AMD64_LINUX/*.cpp AMD64_LINUX/*.c 2>/dev/null | xargs -r cat | wc -c)
  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" $n $e $us $sy $txt $dat $srcsz >> $OUT
done < $W/headless-inst.txt
awk -F'\t' '{e+=$2; c+=$3+$4; t+=$5; d+=$6; s+=$7} END{printf "%s: wall %.1fs cpu %.1fs text %d data %d gen-src %d\n", L, e, c, t, d, s}' L=$LABEL $OUT
