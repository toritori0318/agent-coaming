# Agent Coaming

[日本語](README.ja.md)

A macOS app that shows only the usage of Claude Code, Codex CLI, and Cursor: how much of the limit is used, and when it resets.

![Corner indicator. Claude and Codex show 5h and 1w. Cursor shows 1mo.](docs/indicator.jpg)

- Login material is **read-only**. Nothing is rewritten, copied, or refreshed
- The only network hosts are `chatgpt.com` (Codex) and `cursor.com` (Cursor). There is no network call for Claude
- For personal use. Not distributed on the App Store and not notarized

## How it reads usage

| Service | Source |
|---|---|
| Claude | The newer of two local files. (1) `plan-usage-history.json`, written by Claude Desktop about every 15 minutes (used percent only). (2) A file written by the bundled script from the `rate_limits` Claude Code passes to its status line (includes reset times). OAuth tokens are not touched |
| Codex CLI | The token in `$CODEX_HOME/auth.json`, then the usage API on `chatgpt.com` |
| Cursor | A read-only `state.vscdb`, or the Keychain token, then the usage API on `cursor.com` |

This app does not use Claude's OAuth token. Anthropic reserves that token for Claude Code and its native apps. The app reads the values Claude Desktop and Claude Code already keep locally.

- **If Claude Desktop (including Cowork) is running, the 5-hour and 7-day percents appear with no extra setup** (updated about every 15 minutes; no reset time)
- Setting the Claude Code status line adds reset times while a session is running
- While neither is running, the last value stays on screen, dimmed, as "n ago"

`plan-usage-history.json` is not a published format, so a Desktop update can make it unreadable. The status line path still works on its own.

## Requirements

- macOS 15 or later, Xcode 16 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- An Apple ID (a free Personal Team is enough). The widget uses an App Group, so it will not run unsigned

## Build and install

```sh
COAMING_TEAM_ID=XXXXXXXXXX make install
```

`XXXXXXXXXX` is the Team ID shown in Xcode → Settings → Accounts. This installs `~/Applications/Agent Coaming.app` and copies the Claude status line script to `~/Library/Application Support/Agent Coaming/claude-statusline.sh`.

### Claude Code status line (optional, for reset times)

Add a status line to `~/.claude/settings.json`.

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh"
  }
}
```

If you already have a status line, pass that command as an argument and its display stays.

```json
"command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh ~/.claude/statusline.sh"
```

`command` is executed by a shell, so escape each space in the path with `\` (`\\` inside JSON).

The script writes only `five_hour` and `seven_day` from `rate_limits` to `~/Library/Application Support/Agent Coaming/claude-rate-limits.json`. It does not write conversation text or paths.

## Development

```sh
make test    # unit tests for CoamingCore
make check   # tests plus the forbidden-string check (scripts/check.py)
make run     # build and launch the host
coaming --check  # CLI: whether each service's login material was found
```

## License

MIT
