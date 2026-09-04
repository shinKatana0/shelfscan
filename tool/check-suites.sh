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
# What is retained: the reporter logs, written outside the repository, in a
# directory this run created and owns (see `--log-dir` below). They hold
# reporter output only -- no `--verbose`, no environment -- but they do carry
# absolute paths of the machine that ran them, so they are a scratch file to
# read and not an artefact to commit or paste.
#
# No `set -e`: every exit code here is data.

set -u

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BOUND=${SHELFSCAN_SUITE_BOUND:-900}
RERUN_BOUND=${SHELFSCAN_RERUN_BOUND:-300}
LOGPARENT=
SUITES=
VERDICT=

usage() {
  cat <<'USAGE'
usage: sh tool/check-suites.sh [--bound S] [--rerun-bound S] [--log-dir DIR] [core] [app]

  --bound S         wall-clock bound per suite run, seconds (default 900)
  --rerun-bound S   wall-clock bound per single-file re-run (default 300)
  --log-dir DIR     PARENT of this run's log directory (default: TMPDIR).
                    The run creates a fresh subdirectory of DIR and writes
                    only there; DIR itself is never written to or cleared.
  core | app        run only that suite; default is both

exit: 0 green | 1 a real failure | 3 a host died, every named file green alone
      4 the bound tripped | 2 bad usage
USAGE
}

while [ $# -gt 0 ]; do
  case $1 in
    --bound) BOUND=$2; shift 2 ;;
    --rerun-bound) RERUN_BOUND=$2; shift 2 ;;
    --log-dir) LOGPARENT=$2; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    core|app) SUITES="$SUITES $1"; shift ;;
    *) echo "check-suites: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[ -n "$SUITES" ] || SUITES="core app"
[ -n "$LOGPARENT" ] || LOGPARENT="${TMPDIR:-/tmp}"

# The run owns its directory, and `--log-dir` names its PARENT (T-0463).
#
# Measured 2026-09-04: one scratchpad is handed to every worker in a session,
# so a run was pointed at a directory that already held an earlier run's
# `app.log` and `app.did-not-complete` -- green, complete, and about another
# worktree. core.log is written first and app.log second, so a run stopped
# between the two leaves the previous run's app evidence standing, and a
# reader doing exactly what the convention asks reports somebody else's green.
# A fresh directory per run removes the inheritance rather than labelling it.
#
# Why this name cannot collide, which a branch name could not promise -- two
# clones can sit on a branch of the same name, and a re-run collides with
# itself. Three reasons, and only the third has to hold:
#   1. `$$` is unique among the processes alive at this instant.
#   2. The UTC stamp separates two runs whose pid value was recycled between
#      them.
#   3. `mkdir` WITHOUT `-p` is atomic and fails if the name already exists, so
#      a collision is detected rather than assumed away and the counter walks
#      to a free name. Whatever this run writes into, this run created.
# Nothing here removes anything: the parent may be shared with a live worker.
_stamp=$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null) || _stamp=unstamped
mkdir -p "$LOGPARENT" || exit 2
_n=1
while :; do
  LOGDIR="$LOGPARENT/shelfscan-suites-$_stamp-$$-$_n"
  mkdir "$LOGDIR" 2>/dev/null && break
  _n=$((_n + 1))
  if [ "$_n" -gt 64 ]; then
    echo "check-suites: no free run directory under $LOGPARENT" >&2
    exit 2
  fi
done
# Named so a reader who passed --log-dir DIR and finds nothing in DIR is not
# left guessing. The per-suite `log PATH` lines below carry it too, but the
# first of those is up to $BOUND seconds away and an interrupted run may print
# none of them -- which is the case where the directory most needs finding.
echo "LOGS: $LOGDIR"

# One field per line, and never two: `git rev-parse` writes a partial answer to
# stdout BEFORE failing -- an unborn HEAD answers the word `HEAD` and exits
# 128 -- so an inline `|| echo unknown` yields both, and the record stops being
# readable line by line. The value is taken only when git exited 0.
_gitfield() {
  _v=$(git -C "$ROOT" "$@" 2>/dev/null) || _v=
  [ -n "$_v" ] || _v=unknown
  echo "$_v"
}

# A log cannot name its own run: the core log holds no path at all, and only
# `flutter test` names a worktree. This is what turns "is this evidence mine?"
# from an mtime guess into a read. It stays beside the logs, outside the
# repository, like everything else this script writes.
{
  echo "logdir   $LOGDIR"
  echo "root     $ROOT"
  echo "started  $_stamp"
  echo "pid      $$"
  echo "head     $(_gitfield rev-parse HEAD)"
  echo "branch   $(_gitfield rev-parse --abbrev-ref HEAD)"
  echo "worktree $(_gitfield rev-parse --show-toplevel)"
} >"$LOGDIR/run.info"

# An interrupted run must not read as a finished one. Two signals, because a
# reader may look for either: `run-incomplete` is present until the script
# reaches its own end, and `verdict` is written there as the last act.
: >"$LOGDIR/run-incomplete"

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
# Double-underscored on purpose: sh has no locals, and this is called from
# inside run_suite's loop. An `_lg` here rewrote the caller's suite log path
# under it, so the run after the loop read the wrong file and reported one
# thing wrongly before the collision was noticed.
bounded() {
  __b=$1; __d=$2; __log=$3; shift 3
  ( cd "$__d" && exec "$@" ) >"$__log" 2>&1 &
  __child=$!
  __waited=0
  while kill -0 "$__child" 2>/dev/null; do
    if [ "$__waited" -ge "$__b" ]; then
      hard_kill "$__child"
      wait "$__child" 2>/dev/null
      return $TRIPPED
    fi
    sleep 1
    __waited=$((__waited + 1))
  done
  wait "$__child"
}

# passed | failed | none -- "none" is a run that was cut off before it judged.
verdict_of() {
  if grep -q "All tests passed" "$1"; then echo passed
  elif grep -q "Some tests failed" "$1"; then echo failed
  else echo none
  fi
}

# The files named `did not complete`. Two sources, because neither is
# sufficient on its own: the `Failing tests:` summary block stops after four
# entries and says "... and N more" (measured -- 39 marked tests, 4 listed), and
# the per-test `[E]` lines carry no path when the run held a single file.
# A real failure appears in both without the suffix, so this selects host
# deaths only.
dnc_files() {
  { sed -n '/^Failing tests:/,$ s/^[[:space:]]*\(.*\.dart\): .*(did not complete)$/\1/p' "$1"
    sed -n 's/^[0-9][0-9]:[0-9][0-9] [^:]*: \(.*\.dart\): .* - did not complete \[E\]$/\1/p' "$1"
  } | sort -u
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
    _other=$(grep -c ' \[E\]$' "$_lg")
    _other=$((_other - $(grep -c ' - did not complete \[E\]$' "$_lg")))
    [ "$_other" -gt 0 ] && echo "   ...and $_other test(s) failed outright in the same run; see the log."
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
  0) VERDICT="PREFLIGHT: GREEN" ;;
  1) VERDICT="PREFLIGHT: NOT GREEN -- a real failure" ;;
  3) VERDICT="PREFLIGHT: HOLD -- a test host died; every named file is green alone" ;;
  4) VERDICT="PREFLIGHT: HOLD -- the wall-clock bound tripped; nothing was judged" ;;
esac
echo "$VERDICT"
{ echo "$VERDICT"; echo "exit $WORST"; } >"$LOGDIR/verdict"
rm -f "$LOGDIR/run-incomplete"
exit $WORST
