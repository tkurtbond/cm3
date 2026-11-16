#!/bin/bash
# stage.sh LABEL [MODE [PKGLIST]]: realclean, build (-keep) and ship each
# package in PKGLIST ("name path" lines; default $W/pkgs.txt) from the
# worktree $W/src into the scratch prefix $W/prefix, using the scratch
# prefix's cm3. Refuses to ship if .M3SHIP names any other prefix.
# Keeps the .ll files in $W/ll/LABEL, then installs the new cm3 as
# $W/prefix/bin/cm3 (and cm3.stageLABEL).
W=${W:?set W to the scratch directory (see experiment-doc/phase4-results.md)}
LABEL=$1; MODE=${2:-LlvmIR}; PKGS=${3:-$W/pkgs.txt}; FAILS=0
export PATH=$W/prefix/bin:/usr/bin:/bin
mkdir -p $W/ll/$LABEL; LOG=$W/$LABEL.log; : > $LOG
echo "cm3: $(readlink -f $(which cm3)) $(md5sum < $W/prefix/bin/cm3 | cut -c1-12)" | tee -a $LOG
T0=$(date +%s.%N)
while read n d; do
  cd $W/src/$d || exit 1
  t0=$(date +%s.%N)
  cm3 -realclean >/dev/null 2>&1
  if ! cm3 -build -keep -DM3_BACKEND_MODE=$MODE >> $LOG 2>&1; then echo "BUILD FAILED: $n" | tee -a $LOG; FAILS=$((FAILS+1)); continue; fi
  if grep -q /usr/local/sw/versions/cm3/git AMD64_LINUX/.M3SHIP || ! grep -q $W/prefix AMD64_LINUX/.M3SHIP; then
    echo "REFUSING to ship $n: .M3SHIP does not target the scratch prefix" | tee -a $LOG; exit 1; fi
  cm3 -ship >> $LOG 2>&1 || { echo "SHIP FAILED: $n" | tee -a $LOG; exit 1; }
  t1=$(date +%s.%N)
  mkdir -p $W/ll/$LABEL/$n; cp AMD64_LINUX/*.ll $W/ll/$LABEL/$n/ 2>/dev/null
  printf "%-10s %6.1fs %4d .ll\n" $n $(echo "$t1 - $t0" | bc) $(ls $W/ll/$LABEL/$n | wc -l) | tee -a $LOG
done < $PKGS
cp $W/prefix/pkg/cm3/AMD64_LINUX/cm3 $W/prefix/bin/cm3.stage$LABEL && cp $W/prefix/bin/cm3.stage$LABEL $W/prefix/bin/cm3
printf "TOTAL %.1fs\n" $(echo "$(date +%s.%N) - $T0" | bc) | tee -a $LOG
echo "FAILED: $FAILS" | tee -a $LOG
