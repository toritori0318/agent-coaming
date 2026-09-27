import Foundation

enum ClaudeBinary {
    static func candidates(home: URL, environment: [String: String]) -> [String] {
        var found: [String] = []
        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let binary = URL(fileURLWithPath: String(directory)).appendingPathComponent("claude").path
                if FileManager.default.isExecutableFile(atPath: binary), !found.contains(binary) {
                    found.append(binary)
                }
            }
        }
        let extras = [
            home.appendingPathComponent(".claude/local/claude").path,
            "/opt/homebrew/bin/claude",
        ]
        for binary in extras where FileManager.default.isExecutableFile(atPath: binary) && !found.contains(binary) {
            found.append(binary)
        }
        return found
    }
}

struct ToolPaths: Sendable {
    var home: URL
    var environment: [String: String]

    static func live() -> ToolPaths {
        ToolPaths(
            home: FileManager.default.homeDirectoryForCurrentUser,
            environment: ProcessInfo.processInfo.environment
        )
    }

    var claudeDirectory: URL { home.appendingPathComponent(".claude") }
    var supportDirectory: URL { home.appendingPathComponent("Library/Application Support/Agent Coaming", isDirectory: true) }
    var claudeRateLimits: URL { supportDirectory.appendingPathComponent("claude-rate-limits.json") }
    var claudeDesktopDirectory: URL { home.appendingPathComponent("Library/Application Support/Claude", isDirectory: true) }
    var claudeDesktopUsageHistory: URL { claudeDesktopDirectory.appendingPathComponent("plan-usage-history.json") }
    // Cursor's local session is read only by a COAMING_CURSOR build. See ProviderID.included.
    #if COAMING_CURSOR
    var cursorSupport: URL { home.appendingPathComponent("Library/Application Support/Cursor") }
    var cursorDatabase: URL { cursorSupport.appendingPathComponent("User/globalStorage/state.vscdb") }
    #endif
    var claudeBinaryExists: Bool { !ClaudeBinary.candidates(home: home, environment: environment).isEmpty }
}

func widgetUserAgent() -> String {
    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? Constants.appVersion
    return "AgentCoaming/\(version) (macOS)"
}
