// `backseat` command line: start / stop / check / status / quit / mcp.
import Foundation

let usage = """
backseat: ask before an AI agent drives your Mac, and show that it is.

  backseat start [--agent NAME] "task" [minutes=10] [countdown=10]
        Ask the user (Allow / Not Now; auto-allows when the countdown ends, 0 = don't ask),
        then show the in-control indicator. NAME defaults to $BACKSEAT_AGENT.
        Exit 0 = allowed, 4 = the user said Not Now, 5 = the Backseat app didn't answer.
  backseat check    exit 3 if the user clicked Take Back Control (run before each GUI action)
  backseat stop     release control
  backseat status   print the current state
  backseat quit     quit the menu-bar app
  backseat mcp      run the MCP server on stdio (tools: request_control, check_control, release_control)
"""

let cliCommands: Set<String> = ["start", "stop", "check", "status", "quit", "mcp", "help", "--help", "-h"]

func printErr(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

func runCLI(_ args: [String]) -> Int32 {
    var rest = Array(args.dropFirst())
    switch args[0] {
    case "start":
        var agent = Seat.defaultAgent
        if rest.first == "--agent" {
            guard rest.count >= 2 else { printErr("--agent needs a name"); return 2 }
            agent = rest[1]
            rest.removeFirst(2)
        }
        let reason = rest.first ?? "Controlling the Mac"
        let minutes = rest.count > 1 ? Double(rest[1]) ?? 10 : 10
        let countdown = rest.count > 2 ? Double(rest[2]) ?? 10 : 10
        switch Seat.request(agent: agent, reason: reason, minutes: minutes, countdown: countdown) {
        case .allowed: return 0
        case .denied:
            printErr("backseat: the user said Not Now — don't touch the GUI")
            return 4
        case .noAnswer:
            printErr("backseat: the Backseat app didn't answer — is it installed?")
            return 5
        }
    case "stop":
        Seat.release()
        return 0
    case "check":
        if Seat.aborted {
            printErr("backseat: the user clicked Take Back Control — stop GUI actions")
            return 3
        }
        return 0
    case "status":
        let s = Seat.read()
        print("phase: \(s.phase ?? "idle")")
        if s.isPending || s.isActive {
            print("agent: \(s.agentName)\ntask: \(s.reason ?? "")")
        }
        if Seat.aborted { print("user took back control") }
        print("app: \(Seat.appRunning ? "running" : "not running")")
        return 0
    case "quit":
        Seat.quitApp()
        return 0
    case "mcp":
        runMCP()
        return 0
    default:
        print(usage)
        return 0
    }
}
