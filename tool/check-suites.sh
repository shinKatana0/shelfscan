#!/bin/sh
# Run both suites under a wall-clock bound and then read their logs, because
# neither runner can be trusted to say what happened to itself.
#
# Two measured facts this exists for (T-0264, T-0276):
#
# 1. When a suite file's `flutter_tester` host process dies, every test in that
#    file is reported `did not complete` -- including tests that never started
#    -- with no cause attached, followed by `No tests were found.` and exit 79.
#    Killing a tester child by parent PID reproduces that byte for byte, so the
#    wording says nothing about whether a test is at fault. The only way to get
#    a cause out of the runner is `--verbose`, which dumps the child
#    environment of the machine it ran on and therefore must never be kept, so
#    this script never passes it. The discriminator used instead is free:
#    re-run the named file ALONE. A file whose host died comes back green; a
#    real defect does not.
#
# 2. A test awaiting a future nothing completes hangs with no further reporter
#    output and no end. No per-test `@Timeout` fires and no CLI `--timeout`
#    covers it. So the bound has to be on the run, and tripping it has to kill
#    the process tree -- an orphaned tester keeps a core busy afterwards.
#
# `dart test` fails differently, and is read the same way: its suites share one
# host, so killing it truncates the log with no verdict line at all rather than
# naming anything. That is why green here requires the verdict line AND exit 0,
# never either on its own.
#
# What is retained: the reporter logs, written outside the repository. They
# hold reporter output only -- no `--verbose`, no environment -- but they do
# carry absolute paths of the machine that ran them, so they are a scratch file
# to read and not an artefact to commit or paste.
#
# No `set -e`: every exit code here is data.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BOUND=${SHELFSCAN_SUITE_BOUND:-900}
RERUN_BOUND=${SHELFSCAN_RERUN_BOUND:-300}
LOGDIR=
SUITES=

usage() {
  cat <<'USAGE'
usage: sh tool/check-suites.sh [--bound S] [--rerun-bound S] [--log-dir DIR] [core] [app]

  --bound S         wall-clock bound per suite run, seconds (default 900)
  --rerun-bound S   wall-clock bound per single-file re-run (default 300)
  --log-dir DIR     where the logs go (default: a fresh dir under TMPDIR)
  core | app        run only that suite; default is both

exit: 0 green | 1 a real failure | 3 a host died, every named file green alone
      4 the bound tripped | 2 bad usage
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --bound) BOUND=$2; shift 2 ;;
    --rerun-bound) RERUN_BOUND=$2; shift 2 ;;
    --log-dir) LOGDIR=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    core|app) SUITES="$SUITES $1"; shift ;;
    *) echo "check-suites: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$SUITES" ] || SUITES="core app"
[ -n "$LOGDIR" ] || LOGDIR="${TMPDIR:-/tmp}/shelfscan-suites-$$"
mkdir -p "$LOGDIR" || exit 2

TRIPPED=124   # what `timeout` returns for the same event

# Kills the tree, not the process. `flutter test` is a launcher over dart.exe
# over one flutter_tester per suite file; signalling only the launcher leaves
# the testers running.
hard_kill() {
  _p=$1
  if command -v taskkill >/dev/null 2>&1; then
    # MSYS `ps` is the only place the Windows pid of a background job is
    # visible, and it is not $!.
    _w=$(ps 2>/dev/null | awk -v p="$_p" 'NR>1 && $1==p {print $4; exit}')
    [ -n "$_w" ] && taskkill //F //T //PID "$_w" >/dev/null 2>&1
  fi
  kill -TERM "$_p" 2>/dev/null
  sleep 2
  kill -KILL "$_p" 2>/dev/null
  return 0
}

# bounded SECONDS DIR LOGFILE CMD...
bounded() {
  _b=$1; _d=$2; _lg=$3; shift 3
  ( cd "$_d" && exec "$@" ) >"$_lg" 2>&1 &
  _child=$!
  _waited=0
  while kill -0 "$_child" 2>/dev/null; do
    if [ "$_waited" -ge "$_b" ]; then
      hard_kill "$_child"
      wait "$_child" 2>/dev/null
      return $TRIPPED
    fi
    sleep 1
    _waited=$((_waited + 1))
  done
  wait "$_child"
}

# passed | failed | none -- "none" is a run that was cut off before it judged.
verdict_of() {
  if grep -q "All tests passed" "$1"; then echo passed
  elif grep -q "Some tests failed" "$1"; then echo failed
  else echo none
  fi
}

# The files named `did not complete`, from the summary block both reporters
# print under `--reporter expanded`. A real failure is listed there without the
# suffix, so this selects host deaths only.
dnc_files() {
  sed -n '/^Failing tests:/,$ s/^[[:space:]]*\(.*\.dart\): .*(did not complete)$/\1/p' "$1" | sort -u
}

WORST=0
note_worst() { # 1 beats 4 beats 3 beats 0
  case $1:$WORST in
    1:*) WORST=1 ;;
    4:1) ;; 4:*) WORST=4 ;;
    3:1|3:4) ;; 3:*) WORST=3 ;;
  esac
}

run_suite() {
  _name=$1; _dir=$2; shift 2
  _lg="$LOGDIR/$_name.log"
  echo "== $_name: $* (bound ${BOUND}s)"
  bounded "$BOUND" "$_dir" "$_lg" "$@"
  _rc=$?
  echo "   exit $_rc, log $_lg"

  if [ "$_rc" -eq "$TRIPPED" ]; then
    echo "   WEDGED: no verdict after ${BOUND}s; the process tree was killed."
    echo "   The run stopped after the line below. That is where output ended,"
    echo "   NOT the test that failed -- a hung run names nothing."
    tail -n 2 "$_lg" | sed 's/^/     | /'
    note_worst 4
    return
  fi

  [ "$_rc" -eq 79 ] && echo "   exit 79 is the host-death code; see below."

  _list="$LOGDIR/$_name.did-not-complete"
  dnc_files "$_lg" >"$_list"
  if [ -s "$_list" ]; then
    echo "   'did not complete' in $(wc -l <"$_list" | tr -d ' ') file(s); re-running each alone."
    _died=0; _real=0; _i=0
    while IFS= read -r _f; do
      _i=$((_i + 1))
      _rl="$LOGDIR/$_name-alone-$_i.log"
      bounded "$RERUN_BOUND" "$_dir" "$_rl" "$@" "$_f"
      _rrc=$?
      if [ "$_rrc" -eq 0 ] && [ "$(verdict_of "$_rl")" = passed ]; then
        echo "     $_f"
        echo "       green alone -> its host died. Not a defect in this file."
        _died=$((_died + 1))
      else
        echo "     $_f"
        echo "       NOT green alone (exit $_rrc, $_rl) -> reproducible."
        _real=$((_real + 1))
      fi
    done <"$_list"
    if [ "$_real" -gt 0 ]; then
      echo "   FAILED: $_real file(s) reproduce alone."
      note_worst 1
    else
      echo "   HOST DIED: $_died file(s), each green alone. The suite is green in"
      echo "   two pieces, so this is not a code defect -- but something killed a"
      echo "   test host on this machine and a preflight should not wave it past."
      note_worst 3
    fi
    return
  fi

  case "$(verdict_of "$_lg")" in
    passed)
      if [ "$_rc" -eq 0 ]; then
        echo "   GREEN: $(grep -c '' "$_lg") log lines, exit 0, verdict line present."
      else
        echo "   INCONSISTENT: the log says all tests passed and the runner exited"
        echo "   $_rc. Believe the exit code."
        note_worst 1
      fi
      ;;
    failed) echo "   FAILED: tests failed and are named in the log."; note_worst 1 ;;
    none)
      echo "   TRUNCATED: the run produced no verdict line at all (exit $_rc)."
      echo "   Output stops mid-run -- the host was lost, not a test."
      note_worst 1
      ;;
  esac
}

for s in $SUITES; do
  case $s in
    core) run_suite core "$ROOT/packages/shelfscan_core" dart test --reporter expanded ;;
    app)  run_suite app  "$ROOT/app" flutter test --reporter expanded ;;
  esac
done

case $WORST in
  0) echo "PREFLIGHT: GREEN" ;;
  1) echo "PREFLIGHT: NOT GREEN -- a real failure" ;;
  3) echo "PREFLIGHT: HOLD -- a test host died; every named file is green alone" ;;
  4) echo "PREFLIGHT: HOLD -- the wall-clock bound tripped; nothing was judged" ;;
esac
exit $WORST
