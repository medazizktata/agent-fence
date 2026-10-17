# AGENTS.md — agent-fence

`agent-fence` builds a sandbox-exec profile and execs the tool under it. Usage is in
`README.md`. Read this before changing it.

## Profile, in order (later rules win, verified by probe)
1. `(allow default)` then `(deny file-write*)`.
2. Allow writes in: the tool's own state folders, `$TMPDIR`, `/private/tmp`,
   `~/Library/Caches`, the workspace, `--allow-write` folders, the `~/.claude.json` regex
   (claude with no CLAUDE_CONFIG_DIR), and /dev null, zero, dtracehelper, tty*, fd/*, ptmx.
   Every one of these folders first passes the breadth refusal.
3. `--no-delete`: deny `file-write-unlink` in the workspace, then allow it again only under
   `require-all (subpath ws) (regex /\.git/)`. Without `require-all`, the regex would allow
   unlinking any `.git` path on disk.
4. `--protect` folders: deny writes.
5. Secret folders: deny reads and writes, unless `--allow-secrets`.

Facts measured on this Mac. Don't re-derive them:
- sandbox-exec does NOT nest under a restricted profile. Any deny rule in the outer profile,
  even for a path that does not exist, makes an inner `sandbox_apply` fail with EPERM (exit
  71). Only a fully open outer profile nests. An earlier version of this file claimed the
  opposite from a probe that used an open outer profile; the blind audit caught it. So a
  tool's own sandbox cannot run inside the fence, and test.sh exits 3 if started in one.
- A rename is a `file-write-unlink`. Blocking unlink blocks `mv`, atomic saves and the
  `index.lock → index` step of `git commit`, hence the `.git` exception.
- Sandbox denials don't show in `log show` here. Find a tool's needed paths from its error
  messages when it runs fenced.
- bash 3.2 here-strings (`<<<`) and here-docs write a temp file in /tmp, even with TMPDIR set
  (confirmed by the blind audit). That is why `/private/tmp` stays writable.
- Paths are spelled with their on-disk case (`real()`), and refusals compare by identity
  (`-ef`). APFS is case-insensitive, so `/users/mac` is your home folder.
- In an SBPL `(regex #"…")`, Python's `re.escape` output works (probed); the
  `.claude.json` rule relies on it.

## Rules
- No deletes anywhere in this folder (the user's rule). Scripts truncate or overwrite, and
  temp files are left for the OS. Prove it with `./nodelete-scan <files>` (ast-grep), not
  grep: grep can't tell a call from the same word in a string.
- Never run agents with their own safety off to test the fence (`--dangerously-*`, `--yolo`,
  `--force`, `--auto`). The classifier blocks it, rightly. Test the fence with stub
  processes (`test.sh`) and test real tools with their safety on.
- Never run real delete attempts. `check-delete-blocking.sh` is for the user to run.

## Testing
`./test.sh` must end `0 failed`. `./test.sh --calibrate` must catch every sabotage by its
named check. Add a sabotage spec for every new defence. Run both from a normal terminal.

## Adding a tool
Add a `case` entry with its state folders. Run it fenced with a tiny task; if it fails, its
error names the blocked path. Add a stub line to `test.sh` ("own state yes, other state no").

## Searching this code (tools on this machine)
- Code-shape questions ("any call to X", "every function with Y"): `ast-grep run --lang
  bash|python --pattern '…'`, or a rule file like `nodelete-rules.yml`. ast-grep picks the
  language from the extension, so scan extensionless scripts through a typed copy, as
  `nodelete-scan` does. Learned the hard way: an awk-based split silently scanned nothing.
- Literal text: `rg -F`, `rg -c` to count, `rg --json` for scripts. PCRE2 depends on the
  build: `/opt/homebrew/bin/rg` (first on PATH here) has it (`-P`), `~/.cargo/bin/rg` does
  not. Check `rg --version` before using lookaround.
- Prove any check bites before trusting a clean result. A scan that finds 0 in files that
  contain calls is broken, not clean.
