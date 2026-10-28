// The Backseat protocol: a few files in ~/.backseat shared by the menu-bar app, the CLI and the MCP server.
//   state.json  written by the agent side: {"phase":"pending"|"active"|"idle","agent","reason","since","expires","countdown"}
//   response    written by the app: "allow <since>" | "deny <since>" (answer to a pending request; since = request id)
//   abort       written by the app when the user clicks Take Back Control
import AppKit

let bundleID = "dev.backseat.Backseat"

struct SeatState: Codable {
    var phase: String?        // "pending" | "active" | "idle"
    var agent: String?        // who is asking, e.g. "Claude", "Codex"
    var reason: String?
    var since: Double?        // request time (pending) or start time (active); also the request id
    var expires: Double?
    var countdown: Double?

    var isPending: Bool { phase == "pending" }
    var isActive: Bool { phase == "active" }
    var agentName: String { (agent?.isEmpty == false ? agent : nil) ?? "An AI agent" }
    static let idle = SeatState(phase: "idle")
}

enum Outcome {
    case allowed, denied, noAnswer
}

enum Seat {
    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".backseat")
    static let stateURL = dir.appendingPathComponent("state.json")
    static let responseURL = dir.appendingPathComponent("response")
    static let abortURL = dir.appendingPathComponent("abort")

    static var now: Double { Date().timeIntervalSince1970.rounded(.down) }
    static var defaultAgent: String { ProcessInfo.processInfo.environment["BACKSEAT_AGENT"] ?? "" }

    static func read() -> SeatState {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SeatState.self, from: data) else { return .idle }
        if let expires = state.expires, now > expires {
            return .idle  // the agent forgot to stop, or crashed: don't nag forever
        }
        return state
    }

    static func write(_ state: SeatState) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: stateURL, options: .atomic) }
    }

    static var aborted: Bool { FileManager.default.fileExists(atPath: abortURL.path) }

    /// App side: answer a pending request.
    static func respond(_ verdict: String, id: Double) {
        try? "\(verdict) \(Int(id))\n".write(to: responseURL, atomically: true, encoding: .utf8)
    }

    static func takeBack() {
        FileManager.default.createFile(atPath: abortURL.path, contents: Data("\(now)\n".utf8))
        write(.idle)
    }

    /// Agent side: ask the user (unless countdown is 0), then mark control as active. Blocks until answered.
    static func request(agent: String, reason: String, minutes: Double, countdown: Double) -> Outcome {
        try? FileManager.default.removeItem(at: abortURL)
        try? FileManager.default.removeItem(at: responseURL)
        launchApp()
        let id = now
        if countdown > 0 {
            write(SeatState(phase: "pending", agent: agent, reason: reason, since: id,
                            expires: id + countdown + minutes * 60, countdown: countdown))
            var verdict: String?
            let deadline = id + countdown + 8
            while verdict == nil && Date().timeIntervalSince1970 < deadline {
                if let text = try? String(contentsOf: responseURL, encoding: .utf8) {
                    let parts = text.split(separator: " ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    if parts.count == 2, parts[1] == "\(Int(id))" { verdict = parts[0] }
                }
                if verdict == nil { Thread.sleep(forTimeInterval: 0.2) }
            }
            try? FileManager.default.removeItem(at: responseURL)
            guard verdict == "allow" else {
                write(.idle)
                return verdict == "deny" ? .denied : .noAnswer
            }
        }
        let start = now
        write(SeatState(phase: "active", agent: agent, reason: reason, since: start,
                        expires: start + minutes * 60, countdown: 0))
        return .allowed
    }

    static func release() { write(.idle) }

    // MARK: the menu-bar app

    static var appURL: URL? {
        // the CLI is usually a symlink to Backseat.app/Contents/MacOS/Backseat
        if let exe = Bundle.main.executableURL?.resolvingSymlinksInPath() {
            let app = exe.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            if app.pathExtension == "app" { return app }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/Applications/Backseat.app", "\(home)/Applications/Backseat.app"]
            .map(URL.init(fileURLWithPath:)).first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var appRunning: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty }

    static func launchApp() {
        guard !appRunning, let url = appURL else { return }
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-g", url.path]
        try? open.run()
        open.waitUntilExit()
    }

    static func quitApp() {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).forEach { $0.terminate() }
    }
}
