# AGENTS.md

Instructions for coding agents in this repository.

## Product

The display name is Agent Coaming. The app is `Agent Coaming.app`, bundle ID `io.github.toritori0318.agentcoaming`, App Group `group.agentcoaming`, support directory `~/Library/Application Support/Agent Coaming`. Read-only macOS indicator for Claude Code, Codex CLI, and Cursor usage. It shows the used fraction and the reset time. This app does not refresh tokens and does not write credentials. The Codex CLI it spawns may update its own login file.

The daily UI is the corner overlay (bars, no numbers). The menu bar item is opt-in. The Notification Center widget reads a snapshot and has no network entitlement.

## Language

Code, comments, CLI output, `README.md`, and this file are English. Settings copy is bilingual through `AppLanguage.pick(ja:en:)`. When you change a settings string, update both languages. Do not add Japanese comments.

## Do not commit

- `internal/` — private design notes
- `Config.xcconfig` — personal Team ID, written by `make generate`
- `build/` and `CoamingCore/.build/` — local paths and a signed Team ID
- The Sparkle EdDSA private key, in any form. It lives in the login keychain. See Release.

## Boundaries

`scripts/check.py` fails the build if these are violated. Do not weaken the check to make a change pass.

- Usage fetches in the default build have no network hosts (`Constants.allowedHosts` is empty). `allowedHosts` governs `HTTPClient` only. Claude usage comes from local files. Codex usage comes from the local `codex app-server`, which asks chatgpt.com. Do not call Anthropic or ChatGPT from this app.
- The settings button Check for updates uses Sparkle, which opens its own connection to the GitHub release (github.com and its download hosts). Sparkle is linked by the host only. `SUEnableAutomaticChecks` is false and `SUFeedURL` is an `https://github.com/` URL; `check.py` fails otherwise. The widget does not import Sparkle, its Info.plist has no `SU*` keys, and `check.py --app` fails if an extension contains Sparkle. The widget still has no network entitlement.
- Cursor is compiled only when `COAMING_CURSOR=1`. See `ProviderID.included`. That path may read `state.vscdb` or the Keychain and call `cursor.com`. Do not enable it in the default build. `make check` builds the package without that flag and fails if the product contains `cursor.com`, `usage-summary`, or `state.vscdb`.
- These substrings are forbidden in implementation files (fixtures, `internal/`, and `check.py` itself are skipped): `oauth/token`, `oauth/usage`, `api.anthropic.com`, `api2.cursor.sh`, `auth.openai.com`, `platform.claude.com`, `console.anthropic.com`, `chatgpt.com/backend-api`, `wham/usage`, `SQLITE_OPEN_READWRITE`, `SQLITE_OPEN_CREATE`, `sqlite3_exec`, `SecItemAdd`, `SecItemUpdate`, `SecItemDelete`.
- The check collapses `"a" + "b"` and adjacent string literals, so splitting a forbidden word does not hide it.
- `refresh_token` / `refreshToken` may appear only on a `//` comment line that contains `do not read`.
- `CoamingWidget.entitlements` must not contain `com.apple.security.network.client`.
- This app reads credentials and does not refresh tokens. Do not write `auth.json`, `state.vscdb`, or the Keychain. The spawned Codex CLI may update its own `auth.json`.
- Cursor's database opens with `SQLITE_OPEN_READONLY`. The `immutable=1` URI is only a fallback when open or prepare returns `SQLITE_CANTOPEN` and both `-wal` and `-shm` are absent.
- `snapshot.json` in the App Group must not contain tokens, account IDs, email, or JWTs. Tokens stay in the host process.
- Thresholds and intervals live in `Constants.swift`. Do not scatter new magic numbers.

## Where usage comes from

Claude uses the newer of two local files:

1. Claude Desktop's `plan-usage-history.json` (used percent only, about every 15 minutes while the person works in Desktop; nothing while Desktop sits in the background). The format is unpublished. If it fails to parse, return nil and keep the other file.
2. `claude-rate-limits.json`, written by `scripts/claude-statusline.sh` from the `rate_limits` object Claude Code passes to its status line. The script keeps only `five_hour` and `seven_day` `used_percentage` and `resets_at`.

Codex spawns the installed `codex` binary (`codex app-server`) and sends `account/rateLimits/read`. Do not read `auth.json` or `refresh_token`. The CLI keeps both, asks chatgpt.com, and may refresh its own login file. `chatgpt authentication required` is `unsupported` (API key only). Any other `authentication required` is `needsLogin` with the fixed reason `sign in with ChatGPT in Codex`. An RPC error containing `429` or `rate limit exceeded` is an HTTP 429 so the refresher backs off. Messages that only say `rate limits` (the method name) stay auth or semantic failures. Prefer `rateLimitsByLimitId.codex` over the top-level `rateLimits` snapshot, and do not keep `accountId`. A background poll sets `excludeResetCreditDetails`. Lookup is `PATH`, then `/opt/homebrew/bin/codex`, `/usr/local/bin/codex`, `~/.local/bin/codex`, the Homebrew nodebrew `current/bin`, and `~/.nvm/versions/node/*/bin/codex`. If the candidate is the npm wrapper, launch the vendor binary next to it so a GUI app does not need `node` on `PATH`. The app-server protocol can change without notice.

Cursor is behind `COAMING_CURSOR` because Cursor does not publish a personal usage API. The optional path reads `state.vscdb` or Keychain item `cursor-access-token`, then calls `https://cursor.com/api/usage-summary`. That poll is the closest fit to Cursor's rules against automated access, so the default binary must not contain it. The billing cycle is monthly. The overlay shows that bar as `1mo`, not under `5h` or `1w`, and not as `1m` (that reads as one minute). `totalPercentUsed` divided by 100 is the fraction: `0.36` means 0.36%, not 36%. `make test` defines `COAMING_CURSOR` so this path stays tested. `make build` does not, unless you pass `COAMING_CURSOR=1`.

## UI

- Overlay bars: white below 75%, orange at or above 75%, red at or above 90%. A fraction that rounds to 0% has no fill.
- Claude and Codex show `5h` and `1w`. A `COAMING_CURSOR` build shows Cursor as `1mo` only.
- Settings may show percents. The overlay does not.
- The host polls about every 5 minutes. A manual refresh is ignored when the last attempt was under 60 seconds. A 429 backs off, up to 60 minutes.

## Build

```sh
COAMING_TEAM_ID=XXXXXXXXXX make build   # writes Config.xcconfig, then xcodebuild
make test                           # swift test --package-path CoamingCore
make check                          # test, then python3 scripts/check.py
COAMING_TEAM_ID=XXXXXXXXXX make dmg     # notarized Developer ID disk image
```

`make dmg` (`scripts/release-dmg.sh`) refuses `COAMING_CURSOR` and scans the exported app with `scripts/check.py --app`. The Team ID comes from the environment and is written only to gitignored `Config.xcconfig` and `build/`. The notarization password is not an argument. It stays in the login keychain profile `coaming-notary` (`COAMING_NOTARY_PROFILE` overrides the name). A Personal Team cannot notarize.

`project.yml` is the XcodeGen source. `DEVELOPMENT_TEAM` is `$(COAMING_TEAM_ID)`. Swift 6, macOS 15, strict concurrency. The host is not sandboxed. The widget extension is sandboxed and has no network client entitlement.

## Release

Installed apps update through Sparkle from Settings → Check for updates. A release that skips a step below does not reach them, or fails to verify on their Mac. Go through every item.

1. Bump both numbers in `project.yml`: `MARKETING_VERSION` (shown to people) and `CURRENT_PROJECT_VERSION` (`CFBundleVersion`, what Sparkle compares). Sparkle treats a release with the same `CURRENT_PROJECT_VERSION` as not newer. Keep `Constants.appVersion` equal to `MARKETING_VERSION`.
2. Run `COAMING_TEAM_ID=XXXXXXXXXX make dmg`. It notarizes the app and the disk image, then writes `build/AgentCoaming-<version>.dmg` and `build/sparkle-feed/appcast.xml`. The appcast carries the EdDSA signature of that exact disk image. Do not rebuild the image after the appcast is written. Do not edit the appcast by hand.
3. Create the GitHub Release with tag `v<version>` and attach both files: the disk image, with its filename unchanged, and `appcast.xml`. The enclosure URL inside the appcast is `releases/download/v<version>/AgentCoaming-<version>.dmg`, so the tag and filename must match. The app reads `releases/latest/download/appcast.xml`, so the release must be marked latest and must not be a draft or pre-release.
4. Verify after publishing. Download the appcast from the `releases/latest/download` URL and confirm `sparkle:version` equals the new `CURRENT_PROJECT_VERSION` and the enclosure URL returns the file. On a Mac with the previous version installed, press Check for updates.

Signing key:

- The EdDSA private key stays in the login keychain under account `agent-coaming`. Do not export it into the repo, into `build/`, into chat, or into an environment variable. `make dmg` downloads Sparkle's tools into `build/sparkle-tools` and stops before the archive when that keychain item is missing or does not match `SUPublicEDKey` in `CoamingHost/Info.plist`.
- Installed apps trust the public key already in `Info.plist`. On a new Mac, import the existing private key (`generate_keys --account agent-coaming -f FILE`, from an offline backup). Running `generate_keys` without `-f` makes a new key, which installed apps will reject.
- Losing the key means generating a new pair, replacing `SUPublicEDKey`, and shipping that release by disk image.

Limits:

- A build without Sparkle (1.2.1 and earlier) cannot update itself. People on those builds install the next release from the disk image. The release notes say so.
- Automatic checks stay off (`SUEnableAutomaticChecks` false). The app contacts GitHub only when the button is pressed. Do not turn automatic checks on without a settings toggle and updated README copy.
- Sparkle is linked by the host only. Do not add it to `CoamingWidget`. The version is pinned in three places that must agree: `exactVersion` in `project.yml`, `Package.resolved`, and `sparkle_version` plus `sparkle_sha256` in `scripts/release-dmg.sh` (the hash is of `Sparkle-<version>.tar.xz` from the Sparkle GitHub release). Bumping it is its own PR, verified by a `make dmg` run that notarization still accepts the nested XPC services.
- `make dmg` is the only path that produces the appcast. Do not sign an image with `sign_update` by hand and paste the result.
