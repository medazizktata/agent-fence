#!/bin/bash
# Offline tests for agent-fence, free (no model calls).
#   ./test.sh              run the checks
#   ./test.sh --calibrate  prove the checks bite: each sabotaged copy of agent-fence must fail
#                          the specific check meant to catch it, and the real one must pass
# Stub "agents" named after each tool try writes, reads, moves and a git commit. The fake
# HOME is .test-home next to this script, outside /tmp (which the fence always allows).
# Run it outside any sandbox: macOS cannot start one inside another restricted one (exit 3).
# Nothing is deleted. Each run moves files to new names, so nothing is renamed over.
set -uo pipefail

HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
FENCE="${FENCE_BIN:-$HERE/agent-fence}"

if ! sandbox-exec -p '(version 1)(allow default)' /usr/bin/true 2>/dev/null; then
  echo "test.sh: cannot start a sandbox here: this shell is probably inside one already, and" >&2
  echo "macOS does not nest restricted sandboxes. Run test.sh from a normal terminal." >&2
  exit 3
fi

if [ "${1:-}" = --calibrate ]; then
  C="$HERE/.calibrate"; mkdir -p "$C"
  # sabotage <name> <exact line in agent-fence> <replacement>: a copy with one line changed
  sabotage() {
    python3 -I - "$FENCE" "$C/$1" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:]
t = open(src).read()
n = t.count(old + "\n")
open(dst, "w").write(t.replace(old + "\n", new + "  # sabotaged\n") if n == 1 else t)
sys.exit(0 if n == 1 else 1)
PY
  }
  printf '#!/bin/bash\n# sabotaged: no sandbox at all\nwhile [ $# -gt 0 ]; do case "$1" in --) shift; break ;; --workspace|--allow-write|--protect) shift; [ $# -gt 0 ] && shift ;; -*) shift ;; *) break ;; esac; done\nexec "$@"\n' > "$C/no-sandbox"
  specs=(
    "no-sandbox||codex: blocked outside the workspace"
    "no-default-deny|  echo '(deny file-write*)'|codex: blocked outside the workspace"
    "no-nodelete|    printf '(deny file-write-unlink (subpath %s))\\n' \"\$(q \"\$ws\")\"|renames blocked"
    "no-git-exception|    printf '(allow file-write-unlink (require-all (subpath %s) (regex #\"/\\\\.git/\")))\\n' \"\$(q \"\$ws\")\"|git commit still works"
    "no-secrets|  if [ \$secrets = 0 ]; then|secrets unreadable"
    "no-protect|  if [ \${#protect[@]} -gt 0 ]; then|--protect wins"
    "no-hide|  if [ \${#hide[@]} -gt 0 ]; then|--hide blocks reading"
    "no-codex-state|    state=(\"\${CODEX_HOME:-\$HOME/.codex}\")|codex: writes its workspace and own state"
    "no-broad-check|      die \"refusing to allow writes to '\$1' (\$2): too broad. Pick a narrower folder.\"|refuses HOME as workspace"
    "no-inode-compare|    if [ -e \"\$b\" ] && [ \"\$1\" -ef \"\$b\" ]; then|refuses HOME spelled in lower case"
    "no-ssh-hide|[ \$secrets = 1 ] || envs=(-u SSH_AUTH_SOCK \"\${envs[@]}\")|ssh-agent socket hidden"
    "no-claude-json|    [ -n \"\${CLAUDE_CONFIG_DIR:-}\" ] || claude_json=1   # ~/.claude.json and its temp siblings|claude.json and its temp files"
  )
  bad=0
  for s in "${specs[@]}"; do
    name=${s%%|*}; rest=${s#*|}; line=${rest%|*}; want=${rest##*|}
    case "$name" in
      no-sandbox) ;;
      no-secrets|no-protect|no-hide) sabotage "$name" "$line" "  if false; then" || { echo "  FAIL  $name: line not found"; bad=1; continue; } ;;
      no-broad-check) sabotage "$name" "$line" "      return 0" || { echo "  FAIL  $name: line not found"; bad=1; continue; } ;;
      no-inode-compare) sabotage "$name" "$line" '    if [ -e "$b" ] && [ "$1" = "$b" ]; then' || { echo "  FAIL  $name: line not found"; bad=1; continue; } ;;
      no-codex-state) sabotage "$name" "$line" "    state=()" || { echo "  FAIL  $name: line not found"; bad=1; continue; } ;;
      *) sabotage "$name" "$line" "  :" || { echo "  FAIL  $name: line not found"; bad=1; continue; } ;;
    esac
    chmod +x "$C/$name"
    res=$(FENCE_BIN="$C/$name" gtimeout 120 "$HERE/test.sh" 2>&1); rc=$?   # a hanging mutant must not stall the run
    if [ $rc -ne 0 ] && grep '^  FAIL' <<<"$res" | grep -qF -- "$want"; then
      echo "  ok    $name is caught by \"$want\" ($(grep -c '^  FAIL' <<<"$res") failing checks)"
    else
      echo "  FAIL  $name was NOT caught by \"$want\" (exit $rc)"; bad=1
    fi
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

H="$HERE/.test-home"; W="$H/ws"; RUNID="$(date +%s)-$$"
mkdir -p "$H/bin" "$W" "$H/outside" "$H/.ssh" "$H/.claude" "$H/.codex" "$H/.cursor" \
         "$H/.local/share/opencode" "$H/extra" "$W/protected"
echo "secret" > "$H/.ssh/config"
cat > "$H/bin/stub" <<'STUB'
#!/bin/bash
# stub agent: write:<f> read:<f> mv:<src>:<dst> commit:<repo> env:<VAR>
for a in "$@"; do
  case "$a" in
    write:*) f=${a#write:}; if (echo x > "$f") 2>/dev/null; then echo "wrote $f"; else echo "blocked-write $f"; fi ;;
    read:*)  f=${a#read:};  if cat "$f" >/dev/null 2>&1; then echo "read $f"; else echo "blocked-read $f"; fi ;;
    mv:*)    x=${a#mv:}; s=${x%%:*}; d=${x#*:}
             if mv "$s" "$d" 2>/dev/null; then echo "moved $s"; else echo "blocked-mv $s"; fi ;;
    commit:*) r=${a#commit:}
             if (cd "$r" && date +%s%N >> log.txt && git add log.txt && git -c user.email=t@t -c user.name=t commit -qm t) >/dev/null 2>&1
             then echo "committed $r"; else echo "blocked-commit $r"; fi ;;
    env:*)   v=${a#env:}; echo "env $v=${!v:-unset}" ;;
  esac
done
STUB
chmod +x "$H/bin/stub"
for t in claude codex opencode cursor-agent sometool; do [ -L "$H/bin/$t" ] || ln -s stub "$H/bin/$t"; done
# A fresh repo per run: a sabotaged fence can leave a stale index.lock, and nothing here is deleted.
REPO="$W/repo-$RUNID"
(mkdir -p "$REPO" && cd "$REPO" && git init -q && touch log.txt && git add log.txt \
  && git -c user.email=t@t -c user.name=t commit -qm init) >/dev/null 2>&1

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
run f claude write:"$H/.claude.json" write:"$H/.claude.json.tmp.1" write:"$H/.claudeX"
check "claude: ~/.claude.json and its temp files writable, nothing else" 0 \
      "+wrote $H/.claude.json" "+wrote $H/.claude.json.tmp.1" "+blocked-write $H/.claudeX"
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
echo hidden > "$W/hidden.txt"
run f --hide "$W/hidden.txt" codex read:"$W/hidden.txt" read:"$W/in.txt"
check "--hide blocks reading that file only"      0 "+blocked-read $W/hidden.txt" "+read $W/in.txt"
run f --allow-secrets codex read:"$H/.ssh/config"
check "--allow-secrets makes ~/.ssh readable"     0 "+read $H/.ssh/config"
SSH_AUTH_SOCK=/tmp/fake-agent.sock run f codex env:SSH_AUTH_SOCK
check "ssh-agent socket hidden by default"        0 "+env SSH_AUTH_SOCK=unset"
SSH_AUTH_SOCK=/tmp/fake-agent.sock run f --allow-secrets codex env:SSH_AUTH_SOCK
check "--allow-secrets keeps the ssh-agent socket" 0 "+env SSH_AUTH_SOCK=/tmp/fake-agent.sock"

echo v > "$W/a-$RUNID.txt"
run f codex mv:"$W/a-$RUNID.txt":"$W/b-$RUNID.txt"
check "default: renames allowed in the workspace" 0 "+moved $W/a-$RUNID.txt"
echo v > "$W/c-$RUNID.txt"
run f --no-delete codex write:"$W/edit.txt" mv:"$W/c-$RUNID.txt":"$W/d-$RUNID.txt" commit:"$REPO"
check "--no-delete: edits ok, renames blocked, git commit still works" 0 \
      "+wrote $W/edit.txt" "+blocked-mv $W/c-$RUNID.txt" "+committed $REPO"

run bash -c 'cd "$1" && HOME="$1" PATH="$1/bin:$PATH" exec "$0" codex x' "$FENCE" "$H"
check "refuses HOME as workspace"                 2 "+too broad" "-wrote"
LOWER_H=$(tr '[:upper:]' '[:lower:]' <<<"$H")
run bash -c 'cd / && HOME="$1" PATH="$1/bin:$PATH" exec "$0" --workspace "$2" codex x' "$FENCE" "$H" "$LOWER_H"
check "refuses HOME given as a lower-case workspace" 2 "+too broad" "-wrote"
run bash -c 'cd "$2" && HOME="$1" PATH="$2/bin:$PATH" exec "$0" codex x' "$FENCE" "$LOWER_H" "$H"
check "refuses HOME spelled in lower case"        2 "+too broad" "-wrote"
run bash -c 'cd / && HOME="$1" PATH="$1/bin:$PATH" exec "$0" codex x' "$FENCE" "$H"
check "refuses / as workspace"                    2 "+too broad" "-wrote"
run bash -c 'cd "$1/ws" && HOME="$1" PATH="$1/bin:$PATH" TMPDIR="$1" exec "$0" codex x' "$FENCE" "$H"
check "refuses a TMPDIR that is HOME"             2 "+TMPDIR" "-wrote"
run bash -c 'cd "$1/ws" && HOME="$1" PATH="$1/bin:$PATH" CODEX_HOME="$1" exec "$0" codex x' "$FENCE" "$H"
check "refuses a CODEX_HOME that is HOME"         2 "+codex state folder" "-wrote"
run f --read-only --workspace "$W" codex x
check "--read-only with --workspace is an error"  2 "+not both"
run f --workspace "$H/nope" codex x
check "missing workspace dir is an error"         2 "+not a directory"
run f --bogus codex
check "unknown option is an error"                2 "+unknown option"
run f --protect
check "missing option value is an error"          2 "+needs a directory"
run f no-such-agent-binary
check "missing tool is an error"                  1 "+not found"
run f --dry-run --no-delete codex exec 'two words'
check "--dry-run prints the profile and exact args, runs nothing" 0 "+(deny file-write*)" \
      "+file-write-unlink" "+;; command:" "+two\\ words" "-wrote"
run "$FENCE" -h
check "-h prints the help only"                   0 "+--dry-run" "-die()" "-set -uo"

# structural scan (ast-grep): calibrated on fixed samples, then run on the real files
SCAN="$HERE/nodelete-scan"
run "$SCAN" "$HERE/samples/delete-real.py" "$HERE/samples/delete-real.sh"
check "nodelete-scan finds all 15 real delete calls in samples" 1 "+delete-real.py:8:" "+delete-real.py:9:" \
      "+delete-real.py:10:" "+delete-real.sh:4:" "+delete-real.sh:6:" "+delete-real.sh:7:" "+delete-real.sh:10:" \
      "+delete-real.sh:11:" "+delete-real.sh:12:" "+delete-real.sh:13:" "+delete-real.sh:14:" "+delete-real.sh:15:"
[ "$(grep -c '^/.*delete-real' <<<"$OUT")" = 15 ] && RC=1 || RC=99
check "nodelete-scan reports exactly 15 lines for them" 1
run "$SCAN" "$HERE/samples/delete-look-alike.py" "$HERE/samples/delete-look-alike.sh"
check "nodelete-scan ignores the same words in strings, comments and harmless commands" 0
printf 'const x = 1\n' > "$H/probe.js"
run "$SCAN" "$H/probe.js"
check "nodelete-scan refuses files it cannot parse" 2 "+cannot scan"
run "$SCAN" "$FENCE" "$SCAN" "$HERE/test.sh"
check "no delete calls in agent-fence, nodelete-scan, test.sh" 0

echo
echo "$pass passed, $fail failed"
[ $fail -eq 0 ]
