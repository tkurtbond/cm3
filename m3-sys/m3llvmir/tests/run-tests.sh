#!/bin/sh
# LlvmIR's own tests (see README.md here):
#
#   run-tests.sh [-O] WORKDIR
#
# 1. Mixed linking: builds mixed/mixlib and mixed/mixprog with every
#    combination of the LlvmIR and C back ends, runs mixprog, and
#    compares its output with expected-output.  The C back end gets a
#    few operations wrong (see expected-output.clib), so when mixlib is
#    built with C the output is compared with expected-output.clib.
# 2. Golden IR: checks the Ops.m3.ll that the LlvmIR build of mixlib
#    leaves with FileCheck against Ops.check, and every .ll with llvm-as.
#
# -O builds everything with "cm3 -O" (clang -O2 for LlvmIR); the checked
# IR is the same, since clang optimizes it.  WORKDIR is created if
# needed; each combination is built in a copy there, because cm3 builds
# in the package directory.  Needs cm3, clang, llvm-as and FileCheck on
# PATH (or FILECHECK=/path/to/FileCheck).

set -eu

optimize=
if [ "${1-}" = -O ]; then optimize=-O; shift; fi
if [ $# -ne 1 ]; then
  echo "usage: $0 [-O] WORKDIR" >&2
  exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
work=$(cd "$1" && pwd)

filecheck=${FILECHECK-}
if [ -z "$filecheck" ]; then
  for f in FileCheck $(ls /usr/bin/FileCheck-* 2>/dev/null | sort -t- -k2 -n -r); do
    if command -v "$f" > /dev/null 2>&1; then filecheck=$f; break; fi
  done
fi
if [ -z "$filecheck" ]; then
  echo "$0: FileCheck not found (set FILECHECK)" >&2
  exit 2
fi

failures=0
fail () {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# The target directory cm3 builds into (AMD64_LINUX, ARM64_DARWIN, ...).
target_dir () {
  for d in "$1"/*/; do
    d=${d%/}
    case ${d##*/} in src) ;; *) echo "$d"; return ;; esac
  done
}

# build LIBMODE PROGMODE: L for LlvmIR, C for C.
build () {
  name=$1-$2
  dir=$work/$name
  rm -rf "$dir"
  mkdir -p "$dir"
  cp -R "$here/mixed/mixlib" "$here/mixed/mixprog" "$dir"
  for half in mixlib:$1 mixprog:$2; do
    pkg=${half%:*}
    case ${half#*:} in L) mode=LlvmIR ;; C) mode=C ;; esac
    if ! (cd "$dir/$pkg" && cm3 -DM3_BACKEND_MODE=$mode -keep $optimize) \
         > "$dir/$pkg.log" 2>&1; then
      fail "$name: building $pkg with $mode (log: $dir/$pkg.log)"
      tail -20 "$dir/$pkg.log"
      return 1
    fi
  done
}

for combo in L-L L-C C-L C-C; do
  lib=${combo%-*}
  prog=${combo#*-}
  echo "== mixlib built with $lib, mixprog with $prog"
  build "$lib" "$prog" || continue
  dir=$work/$combo
  expected=$here/expected-output
  if [ "$lib" = C ]; then expected=$here/expected-output.clib; fi
  bin=$(target_dir "$dir/mixprog")/mixprog
  status=0
  "$bin" > "$dir/output" 2>&1 || status=$?
  if [ $status -ne 0 ]; then
    fail "$combo: mixprog exited with status $status"
  elif ! diff -u "$expected" "$dir/output"; then
    fail "$combo: output differs from ${expected##*/}"
  fi

  # The IR: verify every .ll, and FileCheck Ops.m3.ll once.
  for pkg in mixlib mixprog; do
    for ll in "$(target_dir "$dir/$pkg")"/*.ll; do
      [ -e "$ll" ] || continue
      llvm-as -o /dev/null "$ll" || fail "$combo: llvm-as ${ll#$work/}"
    done
  done
  if [ "$combo" = L-L ]; then
    ll=$(target_dir "$dir/mixlib")/Ops.m3.ll
    echo "== FileCheck Ops.check"
    "$filecheck" --input-file="$ll" "$here/Ops.check" \
      || fail "FileCheck Ops.check on ${ll#$work/}"
  fi
done

if [ $failures -ne 0 ]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "all passed"
