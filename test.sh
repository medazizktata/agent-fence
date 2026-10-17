#!/bin/bash
# Offline tests for agent-fence, free (no model calls).
#   ./test.sh              run the checks
#   ./test.sh --calibrate  prove the checks can fail: a fence that sandboxes nothing and one
#                          with a broken profile must each be caught
# Stub "agents" named after each tool try writes, reads, moves and a git commit. The fake
# HOME is .test-home next to this script, outside /tmp (which the fence always allows).
# Nothing is deleted. Files from allowed actions are overwritten on the next run.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
FENCE="${FENCE_BIN:-$HERE/agent-fence}"

if [ "${1:-}" = --calibrate ]; then
  C="$HERE/.calibrate"; mkdir -p "$C"
  printf '#!/bin/bash\n# sabotaged: no sandbox at all\nwhile [ "${1:-}" != "" ] && [ "${1#-}" != "$1" ]; do shift; done\nexec "$@"\n' > "$C/no-sandbox"
  sed 's/^  echo .(deny file-write\*).$/  : # sabotaged/' "$FENCE" > "$C/no-default-deny"
  sed 's/^    printf .(deny file-write-unlink.*$/    : # sabotaged/' "$FENCE" > "$C/no-nodelete"
  chmod +x "$C"/*
  bad=0
  for b in no-sandbox no-default-deny no-nodelete; do
    grep -q sabotaged "$C/$b" || { echo "  FAIL  $b: sabotage did not apply"; bad=1; continue; }
    res=$(FENCE_BIN="$C/$b" "$HERE/test.sh" 2>&1); rc=$?
    n=$(grep -c '^  FAIL' <<<"$res")
    if [ $rc -ne 0 ] && [ "$n" -gt 0 ]; then
      echo "  ok    $b is caught ($n failing checks), e.g. $(grep -m1 '^  FAIL' <<<"$res" | sed 's/^  FAIL  //' | cut -c1-90)"
    else echo "  FAIL  $b was NOT caught"; bad=1; fi
  done
  "$HERE/test.sh" >/dev/null 2>&1 && echo "  ok    unmodified fence passes" || { echo "  FAIL  unmodified fence fails"; bad=1; }
  exit $bad
fi

pass=0 fail=0 OUT="" RC=0
run() { OUT=$("$@" 2>&1); RC=$?; }
check() {  # check <name> <want-exit> [+present] [-absent] ...
  local name=$1 want=$2 why="" c; shift 2
  [ "$RC" = "$want" ] || why="exit $RC, want $want"
  for c in "$@"; do
    case "$c" in
      +*) grep -qF -- "${c:1}" <<<"$OUT" || why="${why:+$why; }missing: ${c:1}" ;;
      -*) ! grep -qF -- "${c:1}" <<<"$OUT" || why="${why:+$why; }unexpected: ${c:1}" ;;
    esac
  done
  if [ -z "$why" ]; then pass=$((pass + 1)); echo "  ok    $name"
  else fail=$((fail + 1)); echo "  FAIL  $name ($why)"; sed 's/^/          /' <<<"$OUT" | head -5; fi
}

H="$HERE/.test-home"; W="$H/ws"
mkdir -p "$H/bin" "$W" "$H/outside" "$H/.ssh" "$H/.claude" "$H/.codex" "$H/.cursor" \
         "$H/.local/share/opencode" "$H/extra" "$W/protected"
echo "secret" > "$H/.ssh/config"
cat > "$H/bin/stub" <<'STUB'
#!/bin/bash
# stub agent: write:<f> read:<f> mv:<src>:<dst> commit:<repo>
for a in "$@"; do
  case "$a" in
    write:*) f=${a#write:}; if (echo x > "$f") 2>/dev/null; then echo "wrote $f"; else echo "blocked-write $f"; fi ;;
    read:*)  f=${a#read:};  if cat "$f" >/dev/null 2>&1; then echo "read $f"; else echo "blocked-read $f"; fi ;;
    mv:*)    x=${a#mv:}; s=${x%%:*}; d=${x#*:}
             if mv "$s" "$d" 2>/dev/null; then echo "moved $s"; else echo "blocked-mv $s"; fi ;;
    commit:*) r=${a#commit:}
             if (cd "$r" && date +%s%N >> log.txt && git add log.txt && git -c user.email=t@t -c user.name=t commit -qm t) >/dev/null 2>&1
             then echo "committed $r"; else echo "blocked-commit $r"; fi ;;
  esac
done
STUB
chmod +x "$H/bin/stub"
for t in claude codex opencode cursor-agent sometool; do ln -sf stub "$H/bin/$t"; done
(cd "$W" && { [ -d .git ] || git init -q; } && touch log.txt && git add log.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init --allow-empty) >/dev/null 2>&1

f() { (cd "$W" && HOME="$H" PATH="$H/bin:$PATH" CLAUDE_CONFIG_DIR= CODEX_HOME= "$FENCE" "$@"); }
echo "agent-fence tests (fake HOME: $H)"

run f codex write:"$W/in.txt" write:"$H/outside/x" write:"$H/.codex/state" write:"$H/.claude/x" \
        write:"$H/.cursor/x" read:"$H/.ssh/config" read:"$W/in.txt"
check "codex: writes its workspace and own state" 0 "+wrote $W/in.txt" "+wrote $H/.codex/state"
check "codex: blocked outside the workspace"      0 "+blocked-write $H/outside/x"
check "codex: blocked in other agents' state"     0 "+blocked-write $H/.claude/x" "+blocked-write $H/.cursor/x"
check "codex: secrets unreadable, workspace readable" 0 "+blocked-read $H/.ssh/config" "+read $W/in.txt"
run f claude write:"$H/.claude/x" write:"$H/.codex/x"
check "claude: own state yes, codex state no"     0 "+wrote $H/.claude/x" "+blocked-write $H/.codex/x"
run f opencode write:"$H/.local/share/opencode/x" write:"$H/.claude/x"
check "opencode: own state yes, claude state no"  0 "+wrote $H/.local/share/opencode/x" "+blocked-write $H/.claude/x"
run f cursor-agent write:"$H/.cursor/x" write:"$H/.codex/x"
check "cursor-agent: own state yes, codex state no" 0 "+wrote $H/.cursor/x" "+blocked-write $H/.codex/x"
run f sometool write:"$W/in.txt" write:"$H/.claude/x"
check "unknown tool: warned, workspace only"      0 "+unknown tool 'sometool'" "+wrote $W/in.txt" "+blocked-write $H/.claude/x"

run f --read-only codex write:"$W/ro.txt" write:"$H/.codex/state"
check "--read-only: workspace blocked, own state allowed" 0 "+blocked-write $W/ro.txt" "+wrote $H/.codex/state"
run f --workspace "$H/extra" codex write:"$H/extra/x" write:"$W/x"
check "--workspace DIR replaces the current dir"  0 "+wrote $H/extra/x" "+blocked-write $W/x"
run f --allow-write "$H/outside" codex write:"$H/outside/x"
check "--allow-write adds a folder"               0 "+wrote $H/outside/x"
run f --protect "$W/protected" codex write:"$W/protected/x" write:"$W/ok.txt"
check "--protect wins inside the workspace"       0 "+blocked-write $W/protected/x" "+wrote $W/ok.txt"
run f --allow-secrets codex read:"$H/.ssh/config"
check "--allow-secrets makes ~/.ssh readable"     0 "+read $H/.ssh/config"

echo v > "$W/a.txt"
run f codex mv:"$W/a.txt":"$W/b.txt"
check "default: renames allowed in the workspace" 0 "+moved $W/a.txt"
echo v > "$W/a.txt"
run f --no-delete codex write:"$W/edit.txt" mv:"$W/a.txt":"$W/c.txt" commit:"$W"
check "--no-delete: edits ok, renames blocked, git commit still works" 0 \
      "+wrote $W/edit.txt" "+blocked-mv $W/a.txt" "+committed $W"

run bash -c 'cd "$1" && HOME="$1" PATH="$1/bin:$PATH" exec "$0" codex x' "$FENCE" "$H"
check "refuses HOME as workspace"                 2 "+too broad" "-wrote"
run bash -c 'cd / && HOME="$1" PATH="$1/bin:$PATH" exec "$0" codex x' "$FENCE" "$H"
check "refuses / as workspace"                    2 "+too broad" "-wrote"
run f --workspace "$H/nope" codex x
check "missing workspace dir is an error"         2 "+not a directory"
run f --bogus codex
check "unknown option is an error"                2 "+unknown option"
run f --protect
check "missing option value is an error"          2 "+needs a directory"
run f no-such-agent-binary
check "missing tool is an error"                  1 "+not found"
run f --dry-run --no-delete codex exec hi
check "--dry-run prints the profile, runs nothing" 0 "+(deny file-write*)" "+file-write-unlink" "+;; command:" "-wrote"

# structural scan (ast-grep): calibrated on fixed samples, then run on the real files
SCAN="$HERE/nodelete-scan"
run "$SCAN" "$HERE/samples/delete-real.py" "$HERE/samples/delete-real.sh"
check "nodelete-scan finds real delete calls (5 in samples)" 1 "+delete-real.py:8:" "+delete-real.py:9:" \
      "+delete-real.py:10:" "+delete-real.sh:4:" "+delete-real.sh:5:"
run "$SCAN" "$HERE/samples/delete-look-alike.py" "$HERE/samples/delete-look-alike.sh"
check "nodelete-scan ignores the same words in strings and comments" 0
run "$SCAN" "$FENCE" "$SCAN" "$HERE/test.sh"
check "no delete calls in agent-fence, nodelete-scan, test.sh" 0

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
