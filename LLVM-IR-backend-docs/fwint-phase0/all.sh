#!/bin/bash
W=${W:?set W to the scratch directory (see README.md)}
for o in O0 O2; do for r in 1 2 3; do for v in old new; do
  $(dirname "$0")/buildtime.sh $v-$o-$r $v $o
done; done; done
$(dirname "$0")/runtime.sh
