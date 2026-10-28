// One binary, three roles: the menu-bar app (no arguments), the `backseat` CLI, and the MCP server (`backseat mcp`).
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
if let command = arguments.first, cliCommands.contains(command) {
    exit(runCLI(arguments))
} else if let command = arguments.first, !command.hasPrefix("-") {
    print(usage)
    exit(2)
} else {
    runApp()
}
