# Security Policy

## Supported versions

Only the latest release is supported. Please upgrade before reporting an issue.

## Scope

Tankful is local-only by design: it makes zero network requests, of any kind, from the app or from the bundled `TankfulBridge` helper. This is auditable directly:

```sh
grep -rn "URLSession\|import Network\|Keychain" Sources/
```

That command should return nothing. If it ever returns a match, that's a regression worth reporting.

The app process itself only **reads**: Codex's session logs, Claude's plan-tier field, and the one snapshot file the bridge writes. It never writes to disk.

The bridge helper (`TankfulBridge`) is the one piece of Tankful that writes anything, and it writes exactly one file: `~/Library/Application Support/Tankful/claude-rate-limits.json`, created with mode `0600`, containing only per-window used-percentages and reset timestamps. It edits nothing else on disk.

The installer (`Scripts/install-claude-bridge.sh`) is the only thing that modifies your Claude Code configuration, and it touches exactly one key: `statusLine.command` in `~/.claude/settings.json`. Before writing, it saves a timestamped backup of the whole file next to it. It supports `--dry-run`, which prints the settings file it would edit, the current `statusLine.command`, the command it would write in its place, and the keys it is leaving alone, then exits without writing. `--uninstall` restores the command that was there before, using the same backup-then-write discipline.

## What Tankful deliberately never touches

- **Keychain or any stored credential** — it never authenticates as you and never needs to.
- **Transcript content** — `~/.claude/projects` is not read at all. Nothing in Tankful parses conversation, prompt, or completion text; the only Claude-side data captured is the official `rate_limits` percentages and reset times Claude Code already hands to its statusline command.
- **The network** — no outbound connection of any kind, to any host, from either the app or the bridge helper.

## Reporting a vulnerability

Please report privately through GitHub, not in a public issue: open the repository's **Security** tab and choose **Report a vulnerability** ([private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability)). That keeps the details between us until a fix is out.

Include reproduction steps if you have them, and the Tankful version you are running. Expect a best-effort response within 7 days — this is a personal project, not a staffed product.
