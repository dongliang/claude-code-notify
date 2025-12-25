# Claude Code Notify

Windows notification system for Claude Code CLI. Get notified when Claude stops working, with one-click jump back to the terminal tab.

## Features

- Windows Toast notification when Claude Code stops
- Shows summary of the last AI response
- "Jump" button to switch back to the exact terminal tab
- Works with Windows Terminal multi-tab sessions

## Requirements

- Windows 10/11
- Windows Terminal
- PowerShell 7+
- Claude Code CLI

## Installation

```powershell
# Download and run the installer
irm https://raw.githubusercontent.com/dongliang/claude-code-notify/master/install.ps1 | iex
```

Or manually:

```powershell
# Clone the repo
git clone https://github.com/dongliang/claude-code-notify.git
cd claude-code-notify

# Run installer
.\install.ps1
```

## Uninstall

```powershell
.\install.ps1 -Uninstall
```

## How It Works

1. **Stop Hook**: When Claude Code stops, a PowerShell hook captures the session info and sends a Toast notification
2. **Protocol Handler**: The "Jump" button uses a custom `claude-focus://` protocol to identify the terminal window/tab
3. **Tab Focus**: Uses Windows Terminal's `wt.exe focus-tab` command to switch to the correct tab

## Files Installed

| File | Location | Purpose |
|------|----------|---------|
| `stop-hook-handler.ps1` | `~/.claude/` | Main hook script |
| `protocol-handler.ps1` | `~/.claude/` | Handles jump button clicks |
| `register-protocol.ps1` | `~/.claude/` | Registers claude-focus:// protocol |

## License

MIT
