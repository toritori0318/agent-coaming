# Agent Coaming

[English](README.md)

<img src="docs/app-icon.png" width="128" alt="アプリアイコン。紺のパネルと、目に見える2本の使用量ゲージ。">

macOS のデスクトップウィジェットに、Claude Code と Codex CLI の使用量（使った割合とリセット時刻）を出すアプリです。Cursor は既定のビルドには入っていません。任意で、`COAMING_CURSOR=1` を付けて自分でビルドしたときだけ入ります。

![既定ビルドの端のインジケータ。Claude と Codex は 5h と 1w。Cursor は入っていません。](docs/indicator.jpg)

![既定ビルドの設定画面。Claude と Codex は 5h と 1w。Cursor は入っていません。](docs/settings.jpg)

- このアプリはログイン情報を読むだけで、書き換え・複製・トークン更新はしません。Codex CLI が自分のログインファイルを更新することはあります
- このアプリ自身は、既定のビルドでは通信しません。Claude は手元のファイルです。Codex の使用量は、手元の `codex` コマンドが chatgpt.com に問い合わせます
- 個人利用向け。App Store には出していません。GitHub の Release にある DMG は公証済みです。`make install` はこの Mac 向けの開発用ビルドです

## 仕組み

| サービス | 使用量の取り方 |
|---|---|
| Claude | 2 つのローカルファイルの新しい方を読む。(1) Claude Desktop が 15 分ごとに書く `plan-usage-history.json`（使用率のみ）、(2) Claude Code が statusline に渡す `rate_limits` を同梱スクリプトが書いたファイル（リセット時刻つき）。OAuth トークンには触らない |
| Codex CLI | インストール済みの `codex` コマンド（`codex app-server`）に `account/rateLimits/read` を聞く。問い合わせるのは CLI で、CLI が chatgpt.com にアクセスし、自分のログインファイルを更新することがあります。このアプリは `auth.json` を読みません |
| Cursor | 既定のビルドには入らない。`COAMING_CURSOR=1` で、読み取り専用の `state.vscdb`（または Keychain のトークン）と `cursor.com` への通信をコンパイルする |

Claude の OAuth トークンは Anthropic が Claude Code とネイティブアプリ専用としているため、このアプリでは使いません。代わりに Claude Desktop / Claude Code が手元に残す値を読みます。

Cursor には個人向けの使用量 API がありません。手元のログイン情報を読んで `cursor.com` に問い合わせる形は、自動アクセスを禁じる Cursor の規約にいちばん近いので、既定のビルドからは外しています。`COAMING_CURSOR=1` でその経路をコンパイルできます。入れるかどうかはビルドする人の判断です。上の画像は既定のビルドで、Claude と Codex だけです。

- **Claude Desktop（Cowork 含む）を起動していれば、設定なしで 5 時間 / 7 日の使用率が出ます**（15 分ごとに更新。リセット時刻は出ません）
- Claude Code だけの場合は、下の statusline を設定すると使用率とリセット時刻が出ます
- どちらも更新していない間は、「n分前の値」として薄く表示されます

Desktop の `plan-usage-history.json` は公開された形式ではないので、Desktop の更新で読めなくなる可能性があります。その場合は statusline 側だけで動きます。

## 必要なもの

- macOS 15 以上、Xcode 16 以上
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）
- Apple ID（無料の Personal Team で可）。ウィジェットが App Group を使うため、署名なしでは動きません

## ビルドとインストール

```sh
COAMING_TEAM_ID=XXXXXXXXXX make install
```

Cursor を含める場合:

```sh
COAMING_CURSOR=1 COAMING_TEAM_ID=XXXXXXXXXX make install
```

`XXXXXXXXXX` は Xcode → Settings → Accounts に出る Team ID です。`~/Applications/Agent Coaming.app` に置き、Claude 用の statusline スクリプトを `~/Library/Application Support/Agent Coaming/claude-statusline.sh` にコピーします。

### 公証済みの DMG

`make install` はこの Mac 用です。無料の Personal Team の署名は期限があり、公証もできません。別の Mac で開ける DMG は次で作ります。

```sh
COAMING_TEAM_ID=XXXXXXXXXX make dmg
```

ここで渡す ID は、有料の Apple Developer Program のチームです。初回だけ、公証用パスワードをログインキーチェーンに預けます。パスワードは入力を求められ、このリポジトリには書きません。

```sh
xcrun notarytool store-credentials "coaming-notary" \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "XXXXXXXXXX"
```

Team ID は環境変数で渡します。書き出されるのは git に入らない `Config.xcconfig` と `build/` だけです。`make dmg` は `COAMING_CURSOR` を拒否し、出来たアプリにその任意パスが無いことも確認して、`build/AgentCoaming-<version>.dmg` を作ります。

### Claude Code の statusline を設定する（任意。CLI のみで使用率とリセット時刻を出したい場合）

Claude Desktop は、この設定なしで約 15 分ごとに使用率を書きます。リセット時刻は含まれません。

Claude Code だけで Desktop を使っていない場合は、この設定がないと使用率も出ません。このアプリは Claude に使用量を問い合わせません。

設定画面の「スクリプトを置く」で、`claude-statusline.sh` を `~/Library/Application Support/Agent Coaming/` にコピーできます。`make install` も同じ場所にコピーします。そのあと `~/.claude/settings.json` に次を追加します。

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh"
  }
}
```

すでに statusline を使っている場合は、そのコマンドを引数に付けると表示はそのまま残ります。

```json
"command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh ~/.claude/statusline.sh"
```

`command` はシェルで実行されるため、パス中のスペースはそれぞれ `\` でエスケープします（JSON の中なので `\\` と書きます）。

使用率のファイルは、Claude Code が statusline を実行し、`rate_limits` に枠があるときに作られます。スクリプトを置いただけでは作られません。

スクリプトは `rate_limits` の `five_hour` / `seven_day` だけを `~/Library/Application Support/Agent Coaming/claude-rate-limits.json` に書きます。会話内容やパスは書きません。

## 開発

```sh
make test    # CoamingCore のユニットテスト
make check   # test + 禁止文字列の検査（scripts/check.py）
make run     # ビルドしてホストを起動
coaming --check  # CLI: 各サービスのログイン情報が見つかるかだけを出す
```

## ライセンス

MIT
