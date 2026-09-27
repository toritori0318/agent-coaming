import CoamingCore
import Foundation

@main
struct AIW {
    static func main() async {
        let arguments = CommandLine.arguments
        if arguments.contains("--check") {
            for line in await CredentialChecker.lines() {
                print(line)
            }
            return
        }
        let snapshot = await CoamingLive.makeRefresher(previous: nil).refresh(force: true)
        if arguments.contains("--json") {
            do {
                FileHandle.standardOutput.write(try snapshot.encode())
                FileHandle.standardOutput.write(Data("\n".utf8))
            } catch {
                fputs("could not write the snapshot\n", stderr)
                exit(1)
            }
            return
        }
        print(render(snapshot))
    }
}

private func render(_ snapshot: Snapshot) -> String {
    let now = Date()
    var lines: [String] = []
    for provider in snapshot.providers {
        switch provider.status {
        case .notInstalled:
            lines.append("\(provider.displayName)\tnot installed")
        case .needsLogin:
            lines.append("\(provider.displayName)\tsign in again\t\(provider.staleReason ?? "")")
        case .unsupported:
            lines.append("\(provider.displayName)\tAPI key not supported")
        case .notConfigured:
            lines.append("\(provider.displayName)\tno data yet (run Claude Desktop or set up the status line)")
        case .ok, .stale:
            let state = provider.status == .ok ? "fetched" : "stale \(provider.staleReason ?? "")"
            lines.append("\(provider.displayName)\t\(provider.planLabel ?? "")\t\(state)")
            for window in provider.windows {
                let value = window.label == "∞" ? "∞" : formatUsedPercent(window.usedFraction)
                let reset = window.resetsAt.map { "resets \(DateParsing.iso8601($0))" } ?? ""
                lines.append("  \(window.label)\t\(value)\t\(reset)")
            }
            if provider.status == .stale, let fetchedAt = provider.fetchedAt {
                lines.append("  \(formatAge(since: fetchedAt, now: now))")
            }
        }
    }
    return lines.joined(separator: "\n")
}
