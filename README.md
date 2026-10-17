# agent-fence — run any agent CLI or TUI inside a macOS sandbox

**For:** anyone letting coding agents (Claude Code, Codex, opencode, cursor-agent) run
commands on their Mac.
**Job:** let the agent change only the project you started it in, enforced by the OS rather
than by the agent's own settings.
**Not:** a network firewall, a container or VM, or a replacement for each tool's own
permission prompts (it sits under them).

Used by `ccfind ask` (~/Desktop/ccfind) to fence its search agent. It stands on its own.

    agent-fence claude                       # Claude Code TUI, can write only the current project
    agent-fence codex                        # same for Codex
    agent-fence opencode run "fix the test"  # one-shot runs work the same way
    agent-fence --no-delete cursor-agent     # also no deletes/renames in the project (except .git)
    agent-fence --read-only claude -p "…"    # no project writes at all
    agent-fence --dry-run codex              # print the sandbox rules, run nothing

The OS enforces it for the agent and everything it starts, whatever the model decides. Your
tool's own permission prompts and sandbox still apply on top (macOS sandboxes nest).

| | Allowed | Blocked |
|---|---|---|
| Writes | the workspace (current dir or `--workspace DIR`), the tool's own state folder, temp folders, `~/Library/Caches` | everything else: other projects, home, other agents' state and transcripts |
| Reads | everything else | `~/.ssh ~/.aws ~/.gnupg ~/.netrc ~/.config/gh` (`--allow-secrets` to allow) |
| Network | everything | nothing (agents need their API) |

Own state folders: claude `~/.claude` (or `$CLAUDE_CONFIG_DIR`) · codex `~/.codex` ·
opencode `~/.local/share|state|config/opencode`, `~/.cache/opencode` · cursor-agent `~/.cursor`,
`~/.local/share/cursor-agent`. Other tools get temp folders only; add their state with
`--allow-write DIR`. `--protect DIR` blocks writes even where they are otherwise allowed.

It refuses `/` or your home folder as a workspace. `cd` into a project first.

`--no-delete` caveat: macOS counts a rename as a delete. So it also blocks tools that save files
by renaming a temp file over the original. Deletes stay possible inside `.git/`, which git needs,
so a `.git` folder can still be wiped.

## Tested here (2026-10-17)
- Real runs, each with its own safety on (accept-edits, default permissions), creating a file
  in a fenced workspace: claude ✓, cursor-agent ✓, opencode ✓ (gemini-3-flash-preview).
  codex ✗: it fails the same way unfenced ("timed out waiting for cloud config bundle"), so
  that is a Codex-side problem. A fenced `codex login status` works.
- Interactive TUIs start fenced and draw their screens with no blocked-write errors: claude
  (folder-trust prompt), cursor-agent, opencode. codex shows only its name (same Codex issue).
- Not done: running agents with their own safety off to prove only the fence stops them.
  Claude Code's classifier blocks that as creating unsafe agents. The fence's blocking is
  proven with plain processes in `./test.sh` instead.

## Tests
    ./test.sh               25 offline checks with stub agents (free, ~3s)
    ./test.sh --calibrate   proves the checks can fail (3 broken fences must be caught)
    ./check-delete-blocking.sh   for you to run: real delete attempts on throwaway files

`nodelete-scan FILE...` is a structural (ast-grep) scan for delete/move calls. It finds real
calls only, not the same words in strings or comments. Rules are in `nodelete-rules.yml`, and
it is calibrated on `samples/` every test run.
