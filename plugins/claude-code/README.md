# Backseat for Claude Code

Asks you before Claude takes over your Mac's mouse, keyboard or screen, and shows you while it's in control.
Claude calls `request_control` before GUI work, `check_control` before each action and `release_control` when done.
A frosted panel lets you Allow, say Not Now, or just wait 10 seconds. The menu bar has **Take Back Control**.

Needs the Backseat menu-bar app and the `backseat` CLI on your PATH (see https://github.com/olekslitus/backseat).
