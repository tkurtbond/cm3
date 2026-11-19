#!/bin/sh
# This fork: runs the network-object tests that check results
# (longint and fixedwidth; the older tests here are run by hand):
#
#   run-netobj-tests.sh WORKDIR [TEST...]
#
# Each test is copied to WORKDIR and built there with the cm3 on PATH
# (cm3 builds in the package directory).  Then its server is started,
# its client is run against it on 127.0.0.1, and the server is stopped.
# A test passes when its client exits with status 0.  fixedwidth needs
# a compiler with the fixed-width integer types (Word8 .. Signed64).
# Set NETOBJ_TEST_PORT to move the ports (default 18877; each test uses
# the next one).

set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 WORKDIR [TEST...]" >&2
  exit 2
fi
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$1"
work=$(cd "$1" && pwd)
shift
[ $# -gt 0 ] || set -- longint fixedwidth

port=${NETOBJ_TEST_PORT-18877}
failed=
for t in "$@"; do
  echo "=== $t"
  rm -rf "$work/$t"
  cp -R "$here/$t" "$work/$t"
  if ! (cd "$work/$t" && cm3 >build.log 2>&1); then
    cat "$work/$t/build.log"
    echo "$t: build FAILED"
    failed="$failed $t"
    continue
  fi
  prog=$(ls "$work/$t"/*/"${t}test" 2>/dev/null | head -1)
  "$prog" server "$port" >"$work/$t/server.log" 2>&1 &
  server=$!
  i=0
  until grep -q 'server ready' "$work/$t/server.log"; do
    i=$((i + 1))
    if [ $i -gt 100 ] || ! kill -0 $server 2>/dev/null; then
      cat "$work/$t/server.log"
      echo "$t: server didn't start"
      kill $server 2>/dev/null || :
      failed="$failed $t"
      continue 2
    fi
    sleep 0.1
  done
  if "$prog" client "$port"; then
    echo "$t: passed"
  else
    echo "$t: FAILED"
    failed="$failed $t"
  fi
  if ! kill -0 $server 2>/dev/null; then
    cat "$work/$t/server.log"
    echo "$t: server died"
    failed="$failed $t"
  fi
  kill $server 2>/dev/null || :
  wait $server 2>/dev/null || :
  port=$((port + 1))
done

if [ -n "$failed" ]; then
  echo "FAILED:$failed"
  exit 1
fi
echo "all passed"
