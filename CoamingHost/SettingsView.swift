import CoamingCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        let language = model.language
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Picker(language.pick(ja: "言語", en: "Language"), selection: Binding(
                        get: { model.language },
                        set: { model.setLanguage($0) }
                    )) {
                        ForEach(AppLanguage.allCases) { item in
                            Text(item.segment).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    .labelsHidden()
                }

                if !model.containerAvailable {
                    Text(language.pick(
                        ja: "App Group のコンテナを解決できません。署名の Team ID と App Group（group.agentcoaming）を確認してください。使用量はウィジェットへ書き込めません。",
                        en: "The App Group container could not be resolved. Check the signing Team ID and the App Group (group.agentcoaming). Usage cannot be written for the widget."
                    ))
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                }

                GroupBox(label: Text(language.pick(ja: "起動", en: "Startup")).font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(language.pick(ja: "ログイン時に起動", en: "Launch at login"), isOn: Binding(
                            get: { model.launchAtLogin },
                            set: { model.setLaunchAtLogin($0) }
                        ))
                        Toggle(language.pick(ja: "画面の端にインジケータを表示", en: "Show the corner indicator"), isOn: Binding(
                            get: { model.overlayVisible },
                            set: { model.setOverlay($0) }
                        ))
                        Toggle(language.pick(ja: "メニューバーに表示", en: "Show in the menu bar"), isOn: Binding(
                            get: { model.menuBar },
                            set: { model.setMenuBar($0) }
                        ))
                        if let notice = model.launchAtLoginNotice {
                            Text(noticeText(notice, language: language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(model.refreshing
                                ? language.pick(ja: "更新中", en: "Refreshing")
                                : language.pick(ja: "今すぐ更新", en: "Refresh now")) {
                                Task { await model.refresh(force: true) }
                            }
                            .disabled(model.refreshing)
                            if model.refreshSkipped {
                                Text(language.pick(
                                    ja: "前回の取得から 60 秒未満のため、更新しませんでした。",
                                    en: "Skipped because the last fetch was less than 60 seconds ago."
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                GroupBox(label: Text("LLM").font(.headline)) {
                    VStack(alignment: .leading, spacing: 12) {
                        ProviderSettingsSection(id: .claude, model: model)
                        Divider()
                        ProviderSettingsSection(id: .codex, model: model)
                        // Cursor settings exist only in a COAMING_CURSOR build. See ProviderID.included.
                        #if COAMING_CURSOR
                        Divider()
                        ProviderSettingsSection(id: .cursor, model: model)
                        #endif
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }

                UsageGuide(language: language)

                Button(language.pick(ja: "終了", en: "Quit")) {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
            .padding(20)
        }
        .frame(minWidth: 560, minHeight: 640)
    }

    private func noticeText(_ notice: LoginItemNotice, language: AppLanguage) -> String {
        switch notice {
        case .needsApproval:
            language.pick(
                ja: "システム設定でログイン項目の承認が必要です。",
                en: "Approve the login item in System Settings."
            )
        case .placeInApplications:
            language.pick(
                ja: "ログイン項目を変更できませんでした。アプリを ~/Applications に置いてからもう一度試してください。",
                en: "The login item could not be changed. Put the app in ~/Applications and try again."
            )
        }
    }
}

private struct ProviderSettingsSection: View {
    var id: ProviderID
    @Bindable var model: AppModel

    var body: some View {
        let language = model.language
        let enabled = model.isEnabled(id)
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle).font(.headline)
            Toggle(language.pick(ja: "有効にする", en: "Enable"), isOn: Binding(
                get: { model.isEnabled(id) },
                set: { model.setEnabled(id, $0) }
            ))
            if enabled {
                detail(language)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ language: AppLanguage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
                if id == .claude, model.snapshot.provider(.claude)?.status != .ok {
                    Text(language.pick(
                        ja: "Claude Desktop を起動していれば、15 分ごとに使用率が出ます。リセット時刻まで出すには Claude Code の settings.json に statusLine を設定します。既存の statusline は引数に付けると残せます。",
                        en: "With Claude Desktop running, usage appears every 15 minutes. To also show reset times, set statusLine in Claude Code's settings.json. Pass an existing status line command as the argument to keep it."
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(#""statusLine": {"type": "command", "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh"}"#)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }

                if let provider = model.snapshot.provider(id) {
                    UsageStatusBars(provider: provider, language: language)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(4)
    }

    private var sectionTitle: String {
        switch id {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

private struct UsageGuide: View {
    var language: AppLanguage
    @State private var expanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                block(
                    language.pick(ja: "更新", en: "Updates"),
                    language.pick(
                        ja: "約 5 分ごとです。取得を断られたサービスは、自動更新が最大 60 分あきます。今すぐ更新は、その間でも前回から 60 秒以上あいていれば通ります。",
                        en: "About every 5 minutes. If a service refuses the request, automatic updates pause for up to 60 minutes. Refresh now still goes through if at least 60 seconds have passed since the last fetch."
                    )
                )
                block(language.pick(ja: "棒", en: "Bars"), barsText)
                block(
                    language.pick(ja: "メニューバー", en: "Menu bar"),
                    language.pick(
                        ja: "有効なサービスの中で、いちばん高い使用率だけ出します。",
                        en: "Shows only the highest usage among enabled services."
                    )
                )
                block(language.pick(ja: "読むもの", en: "What it reads"), readsText)
                block(language.pick(ja: "通信先", en: "Network"), networkText)
            }
            .padding(.top, 8)
        } label: {
            Text(language.pick(ja: "仕様の説明", en: "Specification"))
        }
    }

    // Copy differs because a COAMING_CURSOR build is the only one that reads Cursor. See ProviderID.included.
    private var barsText: String {
        #if COAMING_CURSOR
        language.pick(
            ja: "長いほど使っています。白は 75% 未満、オレンジは 75% 以上、赤は 90% 以上です。Claude と Codex は 5h と 1w、Cursor は 1mo です。ドラッグで移動、クリックでこの画面です。",
            en: "Longer means more used. White is under 75%, orange is 75% or more, and red is 90% or more. Claude and Codex show 5h and 1w. Cursor shows 1mo. Drag to move it. Click to open this window."
        )
        #else
        language.pick(
            ja: "長いほど使っています。白は 75% 未満、オレンジは 75% 以上、赤は 90% 以上です。Claude と Codex は 5h と 1w です。ドラッグで移動、クリックでこの画面です。",
            en: "Longer means more used. White is under 75%, orange is 75% or more, and red is 90% or more. Claude and Codex show 5h and 1w. Drag to move it. Click to open this window."
        )
        #endif
    }

    private var readsText: String {
        #if COAMING_CURSOR
        language.pick(
            ja: "Claude: ~/Library/Application Support/Claude/plan-usage-history.json（Claude Desktop が書く使用率）と ~/Library/Application Support/Agent Coaming/claude-rate-limits.json（Claude Code の statusline が書く使用率）。新しい方を使います。Codex: インストール済みの codex コマンドに使用量を聞きます。auth.json は読みません。Cursor: ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb（読み取り専用）、無ければ Keychain の cursor-access-token。すべて読むだけで、更新も書き換えもしません。",
            en: "Claude: ~/Library/Application Support/Claude/plan-usage-history.json (usage written by Claude Desktop) and ~/Library/Application Support/Agent Coaming/claude-rate-limits.json (usage written by the Claude Code status line), whichever is newer. Codex: asks the installed codex command for usage. auth.json is not read. Cursor: ~/Library/Application Support/Cursor/User/globalStorage/state.vscdb (read-only), or the Keychain item cursor-access-token. Everything is read only, never refreshed or rewritten."
        )
        #else
        language.pick(
            ja: "Claude: ~/Library/Application Support/Claude/plan-usage-history.json（Claude Desktop が書く使用率）と ~/Library/Application Support/Agent Coaming/claude-rate-limits.json（Claude Code の statusline が書く使用率）。新しい方を使います。Codex: インストール済みの codex コマンドに使用量を聞きます。auth.json は読みません。どちらも読むだけで、更新も書き換えもしません。",
            en: "Claude: ~/Library/Application Support/Claude/plan-usage-history.json (usage written by Claude Desktop) and ~/Library/Application Support/Agent Coaming/claude-rate-limits.json (usage written by the Claude Code status line), whichever is newer. Codex: asks the installed codex command for usage. auth.json is not read. Both are read only, never refreshed or rewritten."
        )
        #endif
    }

    private var networkText: String {
        #if COAMING_CURSOR
        language.pick(
            ja: "cursor.com（Cursor の使用量）だけです。Claude と Codex 向けには通信しません。",
            en: "Only cursor.com (Cursor usage). Nothing is sent for Claude or Codex."
        )
        #else
        language.pick(
            ja: "通信しません。Claude は手元のファイル、Codex は手元の codex コマンドです。",
            en: "This build does not use the network. Claude comes from local files. Codex asks the local codex command."
        )
        #endif
    }

    private func block(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold))
            Text(body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct UsageTrack: View {
    var fraction: Double
    var color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Color.primary.opacity(0.12))
            Capsule()
                .fill(color)
                .scaleEffect(x: fraction, y: 1, anchor: .leading)
                .opacity(fraction > 0 ? 1 : 0)
        }
        .frame(height: 8)
        .frame(maxWidth: .infinity)
    }
}

private struct UsageStatusBars: View {
    var provider: ProviderSnapshot
    var language: AppLanguage

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let plan = provider.planLabel, !plan.isEmpty {
                    Text(plan).foregroundStyle(.secondary)
                }
                Spacer()
                Text(statusLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            if provider.id != .cursor {
                barRow(title: "5h", window: window(.fiveHour))
            }
            barRow(title: weekTitle, window: weekWindow)
        }
    }

    private var weekTitle: String {
        if provider.windows.contains(where: { $0.kind == .weekly }) { return "1w" }
        return "1mo"
    }

    private var weekWindow: UsageWindow? {
        provider.windows.first { $0.kind == .weekly }
            ?? provider.windows.first { $0.kind == .billingPlan }
    }

    private func window(_ kind: WindowKind) -> UsageWindow? {
        provider.windows.first { $0.kind == kind }
    }

    private var statusLabel: String {
        switch provider.status {
        case .ok where WidgetLayout.isDimmed(provider, now: Date()):
            language.pick(ja: "前回の値", en: "Previous value")
        case .ok:
            language.pick(ja: "最新", en: "Up to date")
        case .stale:
            language.pick(ja: "前回の値", en: "Previous value")
        case .needsLogin:
            language.pick(ja: "再ログインが必要", en: "Sign in again")
        case .notInstalled:
            language.pick(ja: "未インストール", en: "Not installed")
        case .unsupported:
            language.pick(ja: "対象外", en: "Unsupported")
        case .notConfigured:
            language.pick(ja: "未取得（Desktop 起動か statusline 設定）", en: "No data yet (run Desktop or set up status line)")
        }
    }

    private func barRow(title: String, window: UsageWindow?) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption.monospaced())
                .frame(width: 44, alignment: .leading)
            UsageTrack(fraction: visibleFraction(window), color: fillColor(window))
            Text(valueText(window))
                .font(.caption.monospacedDigit())
                .frame(width: 48, alignment: .trailing)
        }
    }

    private func fillFraction(_ window: UsageWindow?) -> Double {
        guard let window, window.label != "∞" else { return 0 }
        return window.usedFraction
    }

    private func visibleFraction(_ window: UsageWindow?) -> Double {
        let fraction = fillFraction(window)
        guard (fraction * 100).rounded() >= 1 else { return 0 }
        return fraction
    }

    private func fillColor(_ window: UsageWindow?) -> Color {
        let fraction = fillFraction(window)
        if fraction >= Constants.usageRedThreshold { return .red }
        if fraction >= Constants.usageOrangeThreshold { return .orange }
        return .green
    }

    private func valueText(_ window: UsageWindow?) -> String {
        guard let window else { return "—" }
        if window.label == "∞" { return "∞" }
        return formatUsedPercent(window.usedFraction)
    }
}
