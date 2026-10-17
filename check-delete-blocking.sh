#!/bin/bash
# For YOU to run (`! ~/Desktop/agent-fence/check-delete-blocking.sh`). Claude Code cannot run
# it: it really attempts deletes, which your no-delete hook rightly blocks for agents.
# Every target is a throwaway file this script creates under .test-home/.
set -uo pipefail
HERE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
W="$HERE/.test-home/ws"; O="$HERE/.test-home/outside"
mkdir -p "$W" "$O"
try() {  # try <expect: kept|gone> <label> <file> <agent-fence options...>
  local want=$1 label=$2 f=$3; shift 3
  echo throwaway > "$f"
  (cd "$W" && agent-fence "$@" /bin/rm -f "$f") >/dev/null 2>&1
  local got=gone; [ -e "$f" ] && got=kept
  if [ "$got" = "$want" ]; then echo "  ok    $label ($got)"; else echo "  FAIL  $label (file $got, want $want)"; fi
}
echo "delete checks (targets are throwaway files under $HERE/.test-home):"
try kept "--no-delete blocks deletes in the workspace" "$W/del-me.txt" --no-delete
try kept "deletes outside the workspace are blocked"   "$O/del-me.txt"
try gone "default mode allows deletes in the workspace" "$W/del-me-2.txt"
