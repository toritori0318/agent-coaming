import CoamingCore
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        let language = model.language
        VStack(spacing: 0) {
            content(language)
            Divider()
            footer(language)
        }
        .frame(minWidth: 560, minHeight: 640)
        .toolbar {
            ToolbarItem(placement: .principal) {
                SettingsTitle()
            }
        }
    }

    private func content(_ language: AppLanguage) -> some View {
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

                GroupBox(label: Text(language.pick(ja: "通知", en: "Notifications")).font(.headline)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(language.pick(
                            ja: "使用率が上限に近づいたら通知する",
                            en: "Notify when usage nears a limit"
                        ), isOn: Binding(
                            get: { model.notifyOnLimit },
                            set: { model.setNotifyOnLimit($0) }
                        ))
                        if model.notifyOnLimit {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                                GridRow {
                                    Text(language.pick(ja: "通知する使用率", en: "Notify at"))
                                        .foregroundStyle(.secondary)
                                    notifyOption("75%", get: { model.notifyAt75 }, set: { model.setNotifyAt75($0) })
                                    notifyOption("90%", get: { model.notifyAt90 }, set: { model.setNotifyAt90($0) })
                                }
                                GridRow {
                                    Text(language.pick(ja: "対象の枠", en: "Windows"))
                                        .foregroundStyle(.secondary)
                                    notifyOption("5h", get: { model.notifyFiveHour }, set: { model.setNotifyFiveHour($0) })
                                    notifyOption("1w", get: { model.notifyWeekly }, set: { model.setNotifyWeekly($0) })
                                    #if COAMING_CURSOR
                                    notifyOption("1mo", get: { model.notifyMonth }, set: { model.setNotifyMonth($0) })
                                    #endif
                                }
                            }
                            .padding(.leading, 20)
                            Text(notifyCaption(language))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
            }
            .padding(20)
        }
    }

    /// Pinned below the scroll view. The app has no Dock icon and keeps running after this window closes,
    /// so this is the one visible way to quit, and the note says that closing is not quitting.
    private func footer(_ language: AppLanguage) -> some View {
        HStack(spacing: 12) {
            Text(language.pick(
                ja: "このウィンドウを閉じても、インジケータは動き続けます。",
                en: "Closing this window keeps the indicator running."
            ))
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer()
            Button(language.pick(ja: "Agent Coaming を終了", en: "Quit Agent Coaming")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func notifyOption(_ title: String, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle(title, isOn: Binding(get: get, set: set))
            .toggleStyle(.checkbox)
    }

    private func notifyCaption(_ language: AppLanguage) -> String {
        language.pick(
            ja: "対象の枠が、通知する使用率を下から超えた瞬間に一度だけ通知します。例: Claude の 5h が 75% を超えたとき。下回ってから再び超えると、もう一度通知します。",
            en: "Notifies once when a selected window crosses a selected line from below. For example, when Claude's 5h passes 75%. After usage falls below that line and crosses it again, it notifies once more."
        )
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

/// Centered in the title bar. The window title is hidden so this icon and name are the header.
private struct SettingsTitle: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
            Text("Agent Coaming")
                .font(.system(size: 13, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
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
                if id == .claude, model.snapshot.provider(.claude)?.needsClaudeResetSetup ?? true {
                    ClaudeResetSetup(language: language)
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
        case .claude: "Claude"
        case .codex: "Codex"
        case .cursor: "Cursor"
        }
    }
}

private struct ClaudeResetSetup: View {
    var language: AppLanguage
    @State private var installed = ClaudeStatusLineScript.isInstalled
    @State private var notice: String?

    private var snippet: String {
        #""statusLine": {"type": "command", "command": "~/Library/Application\\ Support/Agent\\ Coaming/claude-statusline.sh"}"#
    }

    var body: some View {
        GroupBox(language.pick(ja: "Claude Code の statusline", en: "Claude Code status line")) {
            VStack(alignment: .leading, spacing: 6) {
                Text(language.pick(
                    ja: "Claude Code から使用率とリセット時刻を受け取る設定です。Claude Desktop（Cowork を含む）だけなら、使用率はこれなしで出ます。リセット時刻が必要なときや、Claude Code だけを使うときは、下の設定を使います。すでに statusline がある場合は、設定手順(github) を見てください。",
                    en: "Receives used percents and reset times from Claude Code. With only Claude Desktop, including Cowork, percents appear without this. Use the setting below when you want reset times, or when you use Claude Code alone. If a status line is already set, see Setup steps (GitHub)."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(installed
                        ? language.pick(ja: "スクリプトを置き直す", en: "Replace the script")
                        : language.pick(ja: "スクリプトを置く", en: "Install the script")) {
                        install()
                    }
                    Link(language.pick(ja: "設定手順(github)", en: "Setup steps (GitHub)"), destination: guideURL)
                        .font(.caption)
                }
                if let notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(language.pick(
                    ja: "Claude Code の settings.json に、次を追加してください。",
                    en: "Add this to Claude Code's settings.json."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(snippet)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button(language.pick(ja: "設定文をコピー", en: "Copy the setting")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                }
                // Copy waits for the script: a settings.json entry that points at a missing script writes nothing.
                .disabled(!installed)
                Text(installed
                    ? language.pick(
                        ja: "次の更新、または「今すぐ更新」で反映されます。",
                        en: "It appears on the next update, or when you choose Refresh now."
                    )
                    : language.pick(
                        ja: "先にスクリプトを置くと、設定文をコピーできます。",
                        en: "Install the script first, then copy the setting."
                    ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    /// Headings on main. GitHub's slug drops punctuation, including the Japanese parentheses.
    private var guideURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path = language.pick(
            ja: "/toritori0318/agent-coaming/blob/main/README.ja.md",
            en: "/toritori0318/agent-coaming/blob/main/README.md"
        )
        components.fragment = language.pick(
            ja: "claude-code-の-statusline-を設定する任意cli-のみで使用率とリセット時刻を出したい場合",
            en: "claude-code-status-line-optional-for-the-cli-only-to-show-usage-and-reset-times"
        )
        return components.url!
    }

    private func install() {
        do {
            try ClaudeStatusLineScript.install()
            installed = true
            notice = language.pick(ja: "置きました。", en: "Installed.")
        } catch {
            notice = language.pick(ja: "置けませんでした。", en: "Could not install it.")
        }
    }
}

private enum ClaudeStatusLineScript {
    static var destination: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Agent Coaming/claude-statusline.sh")
    }

    static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: destination.path)
    }

    static func install() throws {
        guard let source = Bundle.main.url(forResource: "claude-statusline", withExtension: "sh") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = destination.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
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
                        ja: "有効なサービスの 5h と 1w のうち、それぞれいちばん高い使用率を出します。例: 5h 10% 1w 35%。2 つの値は別のサービスのことがあります。前回の値が混ざると薄く表示します。",
                        en: "Shows the highest 5h and 1w usage among enabled services. For example, 5h 10% 1w 35%. The two readings can come from different services. It dims when a reading is a previous value."
                    )
                )
                reads
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

    /// Each path and sentence is its own line, so a path stays readable when the window wraps text.
    private var reads: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(language.pick(ja: "読むもの", en: "What it reads"))
                .font(.caption.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                readSource("Claude", lines: [
                    "~/Library/Application Support/Claude/plan-usage-history.json",
                    language.pick(ja: "Claude Desktop が書く使用率", en: "Usage written by Claude Desktop"),
                    "~/Library/Application Support/Agent Coaming/claude-rate-limits.json",
                    language.pick(ja: "Claude Code の statusline が書く使用率", en: "Usage written by the Claude Code status line"),
                    language.pick(ja: "新しい方を使います。", en: "Whichever is newer is used."),
                ])
                readSource("Codex", lines: [
                    language.pick(
                        ja: "インストール済みの codex コマンドに使用量を聞きます。",
                        en: "Asks the installed codex command for usage."
                    ),
                    language.pick(ja: "このアプリは auth.json を読みません。", en: "This app does not read auth.json."),
                    language.pick(
                        ja: "問い合わせる CLI が自分のログインファイルを更新することがあります。",
                        en: "The CLI may update its own login file."
                    ),
                ])
                // Cursor is compiled only when COAMING_CURSOR=1. See ProviderID.included.
                #if COAMING_CURSOR
                readSource("Cursor", lines: [
                    "~/Library/Application Support/Cursor/User/globalStorage/state.vscdb",
                    language.pick(
                        ja: "読み取り専用。無ければ Keychain の cursor-access-token。",
                        en: "Read-only, or the Keychain item cursor-access-token."
                    ),
                ])
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readSource(_ title: String, lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.medium))
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(line.hasPrefix("~/") ? .caption.monospaced() : .caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var networkText: String {
        #if COAMING_CURSOR
        language.pick(
            ja: "このアプリが直接通信するのは cursor.com（Cursor の使用量）だけです。Codex の使用量は codex CLI が chatgpt.com に問い合わせます。",
            en: "The only host this app calls is cursor.com, for Cursor usage. The codex CLI asks chatgpt.com for Codex usage."
        )
        #else
        language.pick(
            ja: "このアプリ自身は通信しません。Codex の使用量は、codex CLI が chatgpt.com に問い合わせます。そのとき CLI が自分のログインファイルを更新することがあります。",
            en: "This app does not send requests. The codex CLI asks chatgpt.com for Codex usage, and may update its own login file."
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
            // Nothing is said while values are current. A note appears when bars are empty, old, or not fetched yet.
            if provider.planLabel?.isEmpty == false || statusLabel != nil {
                HStack(spacing: 8) {
                    if let plan = provider.planLabel, !plan.isEmpty {
                        Text(plan).foregroundStyle(.secondary)
                    }
                    if let statusLabel {
                        Text(statusLabel).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption)
            }
            Group {
                if provider.id != .cursor {
                    barRow(title: "5h", window: window(.fiveHour))
                }
                barRow(title: weekTitle, window: weekWindow)
            }
            .opacity(isOld ? 0.55 : 1)
        }
    }

    private var isOld: Bool {
        WidgetLayout.isDimmed(provider, now: Date())
    }

    private var locale: Locale {
        Locale(identifier: language == .ja ? "ja_JP" : "en_US")
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

    private var statusLabel: String? {
        switch provider.status {
        case .ok where !isOld:
            return nil
        case .ok, .stale:
            guard let fetched = provider.fetchedAt else { return missingFetchLabel }
            let age = formatAgeWords(since: fetched, now: Date(), locale: locale)
            // Claude values come from files that Claude Desktop and Claude Code write only while in use.
            // An old ok value means neither was used since, not that this app stopped.
            if provider.id == .claude, provider.status == .ok {
                return language.pick(
                    ja: "Claude を使っていないため、\(age)の値です。",
                    en: "Value from \(age). Claude was not in use."
                )
            }
            return language.pick(ja: "\(age)の値です。", en: "Value from \(age).")
        case .needsLogin:
            return language.pick(ja: "再ログインが必要", en: "Sign in again")
        case .notInstalled:
            return language.pick(ja: "未インストール", en: "Not installed")
        case .unsupported:
            return language.pick(ja: "対象外", en: "Unsupported")
        case .notConfigured:
            return language.pick(ja: "未取得（Desktop 起動か statusline 設定）", en: "No data yet (run Desktop or set up status line)")
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
            Text(resetText(window))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 124, alignment: .trailing)
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

    /// Same split as the widget: the first snapshot is waiting, and any other fetch with no prior value failed.
    private var missingFetchLabel: String {
        if provider.staleReason == "waiting" {
            return language.pick(ja: "読み込み中", en: "Loading")
        }
        return language.pick(ja: "取得できませんでした", en: "Could not fetch")
    }

    private func resetText(_ window: UsageWindow?) -> String {
        guard let resets = window?.resetsAt else { return "" }
        return formatResetRemaining(resets, now: Date(), locale: locale)
    }
}
