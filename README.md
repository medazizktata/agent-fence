# agent-fence — run any agent CLI or TUI inside a macOS sandbox

**For:** anyone letting coding agents (Claude Code, Codex, opencode, cursor-agent) run
commands on their Mac.
**Job:** stop accidents. The agent can change your project and its own files, nothing else
on disk, enforced by the OS rather than by the agent's own settings.
**Not:** a defence against a hostile or prompt-injected agent (see Limits), a network
firewall, a container or VM.

Used by `ccfind ask` ([medazizktata/ccfind](https://github.com/medazizktata/ccfind)) to fence
its search agent. It stands on its own.

    agent-fence claude                       # Claude Code TUI, can write only the current project
    agent-fence opencode run "fix the test"  # one-shot runs work the same way
    agent-fence --no-delete cursor-agent     # also no deletes/renames in the project (except .git)
    agent-fence --read-only claude -p "…"    # no project writes at all
    agent-fence --dry-run codex              # print the sandbox rules, run nothing
    agent-fence codex --sandbox danger-full-access   # codex: the fence replaces its own sandbox

| | Allowed | Blocked |
|---|---|---|
| Writes | the workspace (current dir or `--workspace DIR`), the tool's own state folders, `$TMPDIR`, `/private/tmp`, `~/Library/Caches` | everything else: other projects, home, other agents' state and transcripts |
| Reads | everything else | `~/.ssh ~/.aws ~/.gnupg ~/.netrc ~/.config/gh`, and the ssh-agent socket is hidden (`--allow-secrets` to allow) |
| Network | everything | nothing (agents need their API) |

Own state folders:
- **claude:** `~/.claude` (or `$CLAUDE_CONFIG_DIR`), plus `~/.claude.json` and its temp files
  when `CLAUDE_CONFIG_DIR` is unset
- **codex:** `~/.codex` (or `$CODEX_HOME`)
- **opencode:** `~/.local/share/opencode`, `~/.local/state/opencode`, `~/.config/opencode`,
  `~/.cache/opencode`
- **cursor-agent** (also `agent`): `~/.cursor`, `~/.local/share/cursor-agent`

Other tools get only the temp folders. Add their state with `--allow-write DIR`.
`--protect DIR` blocks writes even where they are otherwise allowed. `--hide PATH` blocks
reading and writing a file or folder (`ccfind ask` hides the calling session's transcript). Tools run with
`DISABLE_AUTOUPDATER=1`, because their install folders are not writable.

**Refusals:**
- A workspace or any writable folder that is `/`, your home, `/Users`, `/private`, `/var`,
  `/Volumes`, `/Library`, `/System`, `/usr`, `/etc`, `/opt`, `/Applications` or `~/Library`.
- That includes folders from `TMPDIR`, `CODEX_HOME` or `CLAUDE_CONFIG_DIR`, and any spelling
  of them: folders are compared by identity, not by name.
- `~/Desktop` and `~/Documents` as a workspace only warn.

**macOS does not nest sandboxes.** Inside any restricted sandbox, starting another one fails
("sandbox_apply: Operation not permitted"). So a tool's own sandbox cannot start inside the
fence, and the fence replaces it. For codex, use `--sandbox danger-full-access` inside the
fence; agent-fence prints this reminder. For the same reason `test.sh` must run from a normal
terminal, not inside a fenced agent.

**`--no-delete`:**
- It blocks deletes and renames in the workspace only. State, temp and `--allow-write` folders
  stay deletable.
- It does not stop overwriting or truncating a file.
- macOS counts a rename as a delete. So tools that save by renaming a temp file over the
  original fail or leave `*.tmp` files behind. Claude Code's Write tool falls back to a
  direct write.
- Deletes stay possible inside `.git/`, which git needs. A `.git` folder's contents can be
  wiped; the empty folder remains.

## Limits (read before trusting it)
- `sandbox-exec` is deprecated by Apple (`man sandbox-exec`). It still works on macOS today.
- The profile is open by default. Only file writes and five secret paths are restricted.
  Network, IPC and starting programs are not.
- Programs started through launchd, `open`, AppleScript or XPC are not descendants, so the
  fence does not cover them.
- Anything readable can be sent over the network, and the secret list is short: cloud, docker
  and npm tokens, keychains and browser profiles are readable. The tool's own state folder is
  writable, and that is its config, hooks and MCP definitions, which apply on the next
  unfenced run.
- Rules are by path. Hard links were not tested.
- For untrusted input, use a separate macOS user or a VM or container with only the project
  mounted and filtered egress, or work on a copy (`cp -c`, `git worktree`) and review the diff.

## Tested (2026-10-17/18)
- `./test.sh`: 37 checks with stub agents in a fake home, so the OS really blocks or allows
  each write. Calibration (`--calibrate`) runs 12 sabotaged copies of agent-fence, one per
  defence. Each must fail the check meant to catch it, and does.
- Real tools with their own safety on, each creating a file in a fenced project: claude ✓,
  cursor-agent ✓, opencode ✓. Their TUIs start fenced.
- codex 0.160.0 (2026-10-20): `codex exec` answers fenced. With its own sandbox on
  (`--sandbox workspace-write`), its file write fails inside the fence, as the nesting limit
  predicts. Fenced writes with `--sandbox danger-full-access` are not tested here.
- A blind audit (an agent given only this repo) reproduced the profile, option and refusal
  behaviour. It found the nesting limit, a lower-case path bypass, unchecked env paths and
  scanner gaps, all fixed since.
- Real delete attempts (`/bin/rm` on throwaway files, run by a human with
  `check-delete-blocking.sh`): `--no-delete` kept the workspace file, a file outside the
  workspace was kept, and the default mode deleted the workspace file.

## Tests
    ./test.sh               37 checks (free, ~5 s); exits 3 if run inside a sandbox
    ./test.sh --calibrate   12 sabotaged copies, each caught by its own check
    ./check-delete-blocking.sh   for you: real delete attempts on throwaway files

`nodelete-scan FILE...` is a structural (ast-grep) scan of `.py`, `.sh` and extensionless
scripts:
- **Finds:** bash deletes (`rm` and friends, by path too, through `sudo`, `env`, `xargs`,
  `command` and other wrappers, `find -delete`, `git clean`, `rsync --delete`) and Python
  deletes and moves.
- **Misses:** code inside strings (`bash -c`, `eval`, `python3 -c`, subprocess), here-doc
  bodies, aliases, bash `mv`.
- **Other files** are refused (exit 2), not reported clean.
- **Known false positive:** a wrapper command with an rm-like word anywhere in it.

It is calibrated on `samples/` every run.
