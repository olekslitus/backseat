# Backseat

You take the backseat while an AI agent drives your Mac. Backseat asks before any agent (Claude, Codex, Cursor,
Gemini, anything) takes over your mouse, keyboard or screen, and shows you while it's in control.

- **Request:** a frosted panel under the notch says *"Codex wants to use your Mac"* with the task, **Not Now** /
  **Allow**, and a 10 s countdown ring. Doing nothing allows it. Clicking doesn't steal focus from your app.
- **In control:** *"Codex is using your Mac"* with the task and an elapsed timer. The panel is click-through and
  shows on every Space.
- **Menu bar:** a dashed square when idle, filled orange while an agent is in control (dimmer while asking). The
  menu has **Take Back Control**, which the agent checks before every action.
- Control auto-expires (default 10 min) if an agent crashes or forgets to release it.

One native binary is the menu-bar app, the `backseat` CLI and an MCP server. No runtime dependencies.

## Install
```sh
git clone https://github.com/olekslitus/backseat && cd backseat
./build.sh            # builds ~/Applications/Backseat.app and links ~/.local/bin/backseat
./build.sh /Applications
```
Needs macOS 13+ and the Xcode command line tools (`xcode-select --install`). Make sure `~/.local/bin` is on your PATH.

## Connect your agent
The MCP server is `backseat mcp` (tools: `request_control`, `check_control`, `release_control`).
Each package sets `BACKSEAT_AGENT` so the panel shows the right name, and adds instructions to ask before GUI work.

| Agent | Install |
|---|---|
| **Claude Code** | `/plugin marketplace add olekslitus/backseat` then `/plugin install backseat@backseat` |
| **Codex CLI** | append `plugins/codex/config.toml` to `~/.codex/config.toml`, and add `plugins/codex/AGENTS.md` to your `AGENTS.md` |
| **Cursor** | merge `plugins/cursor/mcp.json` into `~/.cursor/mcp.json`; copy `plugins/cursor/rules/backseat.mdc` to `.cursor/rules/` |
| **Gemini CLI** | clone the repo, then `gemini extensions install ./backseat/plugins/gemini` |
| **Anything else** | use the CLI below, or the file protocol |

Claude Code 2.1.275+ can do it in one step: `/plugin install backseat --marketplace olekslitus/backseat`.

## CLI
```sh
backseat start --agent Codex "Testing the settings window" [minutes=10] [countdown=10]
#   blocks while asking; exit 0 = go, 4 = user said Not Now, 5 = app not answering
backseat check    # before each GUI action; exit 3 = user clicked Take Back Control, stop now
backseat stop     # when done
backseat status | quit | mcp
```
`BACKSEAT_AGENT=Codex` sets the default name.

## Protocol
Everything lives in `~/.backseat/`:

| File | Written by | Content |
|---|---|---|
| `state.json` | agent | `{"phase":"pending"\|"active"\|"idle","agent":"Codex","reason":"…","since":<epoch>,"expires":<epoch>,"countdown":10}` |
| `response` | app | `allow <since>` or `deny <since>`: the answer to a pending request (`since` is the request id) |
| `abort` | app | present when the user clicked Take Back Control |

Write `pending`, wait for a `response` carrying your `since`, then write `active` (with a new `since` for the timer).
Write `idle` when done. The app ignores any state whose `expires` is in the past.

## License
MIT, see [LICENSE](LICENSE).
