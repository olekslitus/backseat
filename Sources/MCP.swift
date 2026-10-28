// Minimal MCP server over stdio (newline-delimited JSON-RPC 2.0), no dependencies.
import Foundation

private let instructions = """
Backseat asks the user before you take over their Mac's mouse, keyboard or screen, and shows them while you're in control. \
Call request_control before any GUI automation (computer use, clicks, typing, AppleScript/System Events, screenshots that \
change focus). If it is denied, do not touch the GUI and tell the user. Call check_control before each GUI action and stop \
immediately if it says the user took back control. Call release_control as soon as you're done.
"""

private let tools: [[String: Any]] = [
    [
        "name": "request_control",
        "description": "Ask the user for permission to control their Mac (mouse, keyboard, screen). Shows a request with " +
            "Allow / Not Now that auto-allows after a countdown, then an in-control indicator. Blocks until answered. " +
            "Call before any GUI automation; do not touch the GUI unless the result is 'allowed'.",
        "inputSchema": [
            "type": "object",
            "properties": [
                "task": ["type": "string", "description": "Short description shown to the user, e.g. 'Testing the settings window'"],
                "agent": ["type": "string", "description": "Your name as shown to the user (defaults to the configured agent name)"],
                "minutes": ["type": "number", "description": "How long control may last before it auto-expires (default 10)"],
                "countdown": ["type": "number", "description": "Seconds before the request auto-allows (default 10)"],
            ],
            "required": ["task"],
        ],
    ],
    [
        "name": "check_control",
        "description": "Check that you still have control. Call before each GUI action; if the result is 'stop', " +
            "the user took back control: stop immediately and tell them.",
        "inputSchema": ["type": "object", "properties": [String: Any]()],
    ],
    [
        "name": "release_control",
        "description": "Give control back to the user and hide the indicator. Call as soon as GUI work is done.",
        "inputSchema": ["type": "object", "properties": [String: Any]()],
    ],
]

private func callTool(_ name: String, _ args: [String: Any]) -> (String, Bool) {
    switch name {
    case "request_control":
        let task = args["task"] as? String ?? "Controlling the Mac"
        let agent = args["agent"] as? String ?? Seat.defaultAgent
        let minutes = args["minutes"] as? Double ?? 10
        let countdown = args["countdown"] as? Double ?? 10
        switch Seat.request(agent: agent, reason: task, minutes: minutes, countdown: countdown) {
        case .allowed:
            return ("allowed: you may control the Mac for up to \(Int(minutes)) minutes. Call check_control before each " +
                    "GUI action and release_control when done.", false)
        case .denied:
            return ("denied: the user said Not Now. Do not use the mouse, keyboard or screen; tell the user and ask how to proceed.", false)
        case .noAnswer:
            return ("error: the Backseat menu-bar app didn't answer. Is it installed (Backseat.app)? Do not touch the GUI.", true)
        }
    case "check_control":
        if Seat.aborted {
            return ("stop: the user took back control. Stop all GUI actions now and tell the user.", false)
        }
        let state = Seat.read()
        if state.isActive {
            let elapsed = Int(Seat.now - (state.since ?? Seat.now))
            return ("ok: you still have control (task: \(state.reason ?? ""), \(elapsed)s so far).", false)
        }
        return ("inactive: you don't have control (it expired or was released). Call request_control first.", false)
    case "release_control":
        Seat.release()
        return ("released: the user has their Mac back.", false)
    default:
        return ("unknown tool \(name)", true)
    }
}

private func send(_ message: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

func runMCP() {
    while let line = readLine(strippingNewline: true) {
        guard let data = line.data(using: .utf8),
              let msg = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = msg["method"] as? String else { continue }
        guard let id = msg["id"] else { continue }  // notifications need no reply
        let params = msg["params"] as? [String: Any] ?? [:]
        var result: [String: Any]?
        var error: [String: Any]?
        switch method {
        case "initialize":
            result = [
                "protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "backseat", "version": "0.1.0"],
                "instructions": instructions,
            ]
        case "ping":
            result = [:]
        case "tools/list":
            result = ["tools": tools]
        case "tools/call":
            let (text, isError) = callTool(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:])
            result = ["content": [["type": "text", "text": text]], "isError": isError]
        default:
            error = ["code": -32601, "message": "Method not found: \(method)"]
        }
        var reply: [String: Any] = ["jsonrpc": "2.0", "id": id]
        if let result { reply["result"] = result }
        if let error { reply["error"] = error }
        send(reply)
    }
}
