# Claude Code Notify

Windows notification system for Claude Code CLI. Get notified when Claude stops working.

## Features

- Windows Toast notification when Claude Code stops
- Shows summary of the last AI response

## Requirements

- Windows 10/11
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

1. **Stop Hook**: When Claude Code stops, a PowerShell hook captures the session info and sends a Toast notification with a summary of the last AI response

## Files Installed

| File | Location | Purpose |
|------|----------|---------|
| `stop-hook-handler.ps1` | `~/.claude/` | Main hook script |

## License

MIT
