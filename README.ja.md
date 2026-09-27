# Agent Coaming

[English](README.md)

macOS のデスクトップウィジェットに、Claude Code / Codex CLI の使用量（使った割合とリセット時刻）だけを出すアプリです。Cursor は別にコンパイルできます。

![端のインジケータ。Claude と Codex は 5h と 1w。Cursor の列は COAMING_CURSOR ビルドだけ。](docs/indicator.jpg)

- このアプリはログイン情報を読むだけで、書き換え・複製・トークン更新はしません。Codex CLI が自分のログインファイルを更新することはあります
- このアプリ自身は、既定のビルドでは通信しません。Claude は手元のファイルです。Codex の使用量は、手元の `codex` コマンドが chatgpt.com に問い合わせます
- 個人利用向け。App Store 配布や公証はしていません

## 仕組み

| サービス | 使用量の取り方 |
|---|---|
| Claude | 2 つのローカルファイルの新しい方を読む。(1) Claude Desktop が 15 分ごとに書く `plan-usage-history.json`（使用率のみ）、(2) Claude Code が statusline に渡す `rate_limits` を同梱スクリプトが書いたファイル（リセット時刻つき）。OAuth トークンには触らない |
| Codex CLI | インストール済みの `codex` コマンド（`codex app-server`）に `account/rateLimits/read` を聞く。問い合わせるのは CLI で、CLI が chatgpt.com にアクセスし、自分のログインファイルを更新することがあります。このアプリは `auth.json` を読みません |
| Cursor | 既定のビルドには入らない。`COAMING_CURSOR=1` で、読み取り専用の `state.vscdb`（または Keychain のトークン）と `cursor.com` への通信をコンパイルする |

Claude の OAuth トークンは Anthropic が Claude Code とネイティブアプリ専用としているため、このアプリでは使いません。代わりに Claude Desktop / Claude Code が手元に残す値を読みます。

Cursor には個人向けの使用量 API がありません。手元のログイン情報を読んで `cursor.com` に問い合わせる形は、自動アクセスを禁じる Cursor の規約にいちばん近いので、既定のビルドからは外しています。`COAMING_CURSOR=1` でその経路をコンパイルできます。入れるかどうかはビルドする人の判断です。上の画像には、その任意の列が含まれています。

- **Claude Desktop（Cowork 含む）を起動していれば、設定なしで 5 時間 / 7 日の使用率が出ます**（15 分ごとに更新。リセット時刻は出ません）
- Claude Code の statusline を設定すると、セッション中はリセット時刻つきで更新されます
- どちらも動いていない間は更新されず、「n分前の値」として薄く表示されます

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

### Claude Code の statusline を設定する（任意。リセット時刻を出したい場合）

`~/.claude/settings.json` に statusline を設定します。

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
