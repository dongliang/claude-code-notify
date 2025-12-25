# Claude Code 通知系统安装脚本
# 功能：Claude 停止时发送 Windows Toast 通知，点击可跳转回对应终端标签
# 依赖：Windows Terminal + PowerShell 7 + BurntToast 模块

param(
    [switch]$Uninstall  # 卸载模式
)

$ErrorActionPreference = 'Stop'
$claudeDir = "$env:USERPROFILE\.claude"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Claude Code 通知系统安装器" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

if ($Uninstall) {
    Write-Host "`n[卸载模式]" -ForegroundColor Yellow

    # 删除脚本文件
    $filesToRemove = @(
        "$claudeDir\stop-hook-handler.ps1",
        "$claudeDir\protocol-handler.ps1",
        "$claudeDir\register-protocol.ps1",
        "$claudeDir\tab-sessions.json",
        "$claudeDir\tab-focus-debug.log"
    )
    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item $file -Force
            Write-Host "  已删除: $file" -ForegroundColor Gray
        }
    }

    # 删除协议注册
    $regPath = "HKCU:\Software\Classes\claude-focus"
    if (Test-Path $regPath) {
        Remove-Item $regPath -Recurse -Force
        Write-Host "  已删除协议注册: claude-focus://" -ForegroundColor Gray
    }

    # 清理 settings.json 中的 hook
    $settingsFile = "$claudeDir\settings.json"
    if (Test-Path $settingsFile) {
        $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
        if ($settings.hooks -and $settings.hooks.Stop) {
            $settings.hooks.PSObject.Properties.Remove('Stop')
            if ($settings.hooks.PSObject.Properties.Count -eq 0) {
                $settings.PSObject.Properties.Remove('hooks')
            }
            $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
            Write-Host "  已清理 Claude Code hooks 配置" -ForegroundColor Gray
        }
    }

    Write-Host "`n卸载完成!" -ForegroundColor Green
    exit 0
}

# ============ 安装模式 ============

Write-Host "`n[1/4] 检查依赖..." -ForegroundColor Yellow

# 检查 PowerShell 版本
if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Host "  ! 警告: 推荐使用 PowerShell 7+" -ForegroundColor Yellow
}

# 检查/安装 BurntToast
if (-not (Get-Module -ListAvailable -Name BurntToast)) {
    Write-Host "  安装 BurntToast 模块..." -ForegroundColor Gray
    Install-Module -Name BurntToast -Force -Scope CurrentUser
    Write-Host "  BurntToast 已安装" -ForegroundColor Green
} else {
    Write-Host "  BurntToast 已存在" -ForegroundColor Green
}

# 创建 .claude 目录
if (-not (Test-Path $claudeDir)) {
    New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
}

Write-Host "`n[2/4] 创建脚本文件..." -ForegroundColor Yellow

# ============ stop-hook-handler.ps1 ============
$stopHookScript = @'
# Claude Code Stop Hook - 优化版（使用 wt.exe 跳转）
$ErrorActionPreference = 'SilentlyContinue'

# 读取 hook 数据
$input = @()
while ($null -ne ($line = [Console]::ReadLine())) { $input += $line }
$json = $input -join "`n"

# 提取摘要
$summary = "请回来查看"
if ($json) {
    try {
        $data = $json | ConvertFrom-Json
        if ($data.messages) {
            for ($i = $data.messages.Count - 1; $i -ge 0; $i--) {
                $msg = $data.messages[$i]
                if ($msg.role -eq "assistant" -and $msg.content) {
                    if ($msg.content -is [string]) {
                        $summary = $msg.content
                    } elseif ($msg.content -is [array]) {
                        foreach ($block in $msg.content) {
                            if ($block.type -eq "text") {
                                $summary = $block.text
                                break
                            }
                        }
                    }
                    break
                }
            }
        }
    } catch {}
}

# 清理摘要
$summary = ($summary -replace '[\r\n]+', ' ').Trim()
if ($summary.Length -gt 80) { $summary = $summary.Substring(0, 77) + "..." }

# 获取会话信息
$sessionId = $env:WT_SESSION
$windowId = if ($env:WT_WINDOW) { $env:WT_WINDOW } else { "0" }
$workDir = $PWD.Path
$tabTitle = $Host.UI.RawUI.WindowTitle
$dir = Split-Path -Leaf $workDir

# 尝试获取当前标签索引（通过 UI Automation）
$tabIndex = -1
try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue

    $rootElement = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::ClassNameProperty,
        "CASCADIA_HOSTING_WINDOW_CLASS"
    )
    $wtWindow = $rootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $condition)

    if ($null -ne $wtWindow) {
        $tabCondition = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem
        )
        $tabItems = $wtWindow.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCondition)

        for ($i = 0; $i -lt $tabItems.Count; $i++) {
            try {
                $selectionPattern = $tabItems[$i].GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                if ($selectionPattern.Current.IsSelected) {
                    $tabIndex = $i
                    break
                }
            } catch {}
        }
    }
} catch {}

# 保存到映射表
if ($sessionId) {
    try {
        $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
        $mappingFile = "$scriptDir\tab-sessions.json"

        $mapping = @{}
        if (Test-Path $mappingFile) {
            $existingJson = Get-Content $mappingFile -Raw -Encoding UTF8
            if ($existingJson) {
                $mapping = $existingJson | ConvertFrom-Json -AsHashtable
            }
        }

        $mapping[$sessionId] = @{
            windowId  = $windowId
            tabIndex  = $tabIndex
            workDir   = $workDir
            tabTitle  = $tabTitle
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
        }

        # 清理超过 24 小时的旧数据
        $now = Get-Date
        $keysToRemove = @()
        foreach ($key in $mapping.Keys) {
            $ts = [DateTime]::Parse($mapping[$key].timestamp)
            if (($now - $ts).TotalHours -gt 24) {
                $keysToRemove += $key
            }
        }
        foreach ($key in $keysToRemove) {
            $mapping.Remove($key)
        }

        $mapping | ConvertTo-Json -Depth 10 | Set-Content $mappingFile -Encoding UTF8
    } catch {}
}

# 发送通知
Import-Module BurntToast -ErrorAction SilentlyContinue
if (Get-Module BurntToast) {
    try {
        if ($sessionId) {
            $protocolUrl = "claude-focus://$windowId/$sessionId"
            $button = New-BTButton -Content "跳转" -Arguments $protocolUrl
            New-BurntToastNotification `
                -Text "Claude 已停止", $summary, "标题: $tabTitle | 目录: $dir" `
                -Button $button `
                -UniqueIdentifier "claude-stop-$sessionId"
        } else {
            New-BurntToastNotification -Text "Claude 已停止", $summary, "目录: $dir"
        }
    } catch {
        New-BurntToastNotification -Text "Claude 已停止", $summary, "目录: $dir"
    }
}
'@

Set-Content -Path "$claudeDir\stop-hook-handler.ps1" -Value $stopHookScript -Encoding UTF8
Write-Host "  stop-hook-handler.ps1" -ForegroundColor Green

# ============ protocol-handler.ps1 ============
$protocolHandlerScript = @'
# 自定义协议处理器 - 使用 wt.exe 直接跳转到指定窗口和标签
# 接收格式：claude-focus://windowId/sessionId

param([string]$Url)

$ErrorActionPreference = 'Continue'

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $logFile = "$PSScriptRoot\tab-focus-debug.log"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Add-Content -Path $logFile -Value "[$timestamp] [$Level] $Message" -Encoding UTF8
}

try {
    Write-Log "协议处理器启动, URL: $Url"

    if ($Url -match 'claude-focus://([^/]+)/(.+)') {
        $windowId = $Matches[1]
        $sessionId = $Matches[2].TrimEnd('/')

        $mappingFile = "$PSScriptRoot\tab-sessions.json"
        if (-not (Test-Path $mappingFile)) {
            Write-Log "映射表文件不存在" "ERROR"
            exit 1
        }

        $mapping = Get-Content $mappingFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $sessionInfo = $mapping.$sessionId

        if ($null -eq $sessionInfo) {
            Write-Log "未找到会话 ID: $sessionId" "ERROR"
            exit 1
        }

        $tabIndex = $sessionInfo.tabIndex
        $workDir = $sessionInfo.workDir

        if ($tabIndex -ge 0) {
            & wt.exe -w $windowId focus-tab -t $tabIndex
            Write-Log "已切换到标签索引 $tabIndex" "SUCCESS"
        } else {
            & wt.exe -w $windowId new-tab -d $workDir
            Write-Log "创建新标签页: $workDir" "WARN"
        }
    } else {
        Write-Log "无效的 URL 格式: $Url" "ERROR"
    }
} catch {
    Write-Log "异常: $($_.Exception.Message)" "ERROR"
}
'@

Set-Content -Path "$claudeDir\protocol-handler.ps1" -Value $protocolHandlerScript -Encoding UTF8
Write-Host "  protocol-handler.ps1" -ForegroundColor Green

# ============ register-protocol.ps1 ============
$registerProtocolScript = @'
# 注册自定义协议处理器 claude-focus://
$ErrorActionPreference = 'Stop'

$protocol = "claude-focus"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$handlerScript = "$scriptDir\protocol-handler.ps1"

Write-Host "注册协议: $protocol" -ForegroundColor Cyan

$regPath = "HKCU:\Software\Classes\$protocol"

try {
    if (-not (Test-Path $regPath)) {
        New-Item -Path $regPath -Force | Out-Null
    }

    Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Claude Focus Protocol"
    Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

    $commandPath = "$regPath\shell\open\command"
    if (-not (Test-Path $commandPath)) {
        New-Item -Path $commandPath -Force | Out-Null
    }

    $command = "pwsh.exe -NoProfile -WindowStyle Hidden -File `"$handlerScript`" `"%1`""
    Set-ItemProperty -Path $commandPath -Name "(Default)" -Value $command

    Write-Host "协议注册成功" -ForegroundColor Green
} catch {
    Write-Error "注册失败: $_"
    exit 1
}
'@

Set-Content -Path "$claudeDir\register-protocol.ps1" -Value $registerProtocolScript -Encoding UTF8
Write-Host "  register-protocol.ps1" -ForegroundColor Green

Write-Host "`n[3/4] 注册协议..." -ForegroundColor Yellow

# 直接注册协议（不调用脚本）
$protocol = "claude-focus"
$handlerScript = "$claudeDir\protocol-handler.ps1"
$regPath = "HKCU:\Software\Classes\$protocol"

if (-not (Test-Path $regPath)) {
    New-Item -Path $regPath -Force | Out-Null
}
Set-ItemProperty -Path $regPath -Name "(Default)" -Value "URL:Claude Focus Protocol"
Set-ItemProperty -Path $regPath -Name "URL Protocol" -Value ""

$commandPath = "$regPath\shell\open\command"
if (-not (Test-Path $commandPath)) {
    New-Item -Path $commandPath -Force | Out-Null
}
$command = "pwsh.exe -NoProfile -WindowStyle Hidden -File `"$handlerScript`" `"%1`""
Set-ItemProperty -Path $commandPath -Name "(Default)" -Value $command

Write-Host "  claude-focus:// 协议已注册" -ForegroundColor Green

Write-Host "`n[4/4] 配置 Claude Code hooks..." -ForegroundColor Yellow

$settingsFile = "$claudeDir\settings.json"
$settings = @{}

if (Test-Path $settingsFile) {
    $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json -AsHashtable
}

if (-not $settings.hooks) {
    $settings.hooks = @{}
}

$settings.hooks.Stop = @(
    @{
        matcher = "*"
        hooks = @(
            @{
                type = "command"
                command = "pwsh -NoProfile -File `"$claudeDir\stop-hook-handler.ps1`""
            }
        )
    }
)

$settings | ConvertTo-Json -Depth 10 | Set-Content $settingsFile -Encoding UTF8
Write-Host "  已配置 Stop hook" -ForegroundColor Green

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " 安装完成!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`n功能说明:" -ForegroundColor White
Write-Host "  - Claude 停止时自动发送 Windows 通知" -ForegroundColor Gray
Write-Host "  - 通知显示最后一条 AI 回复摘要" -ForegroundColor Gray
Write-Host "  - 点击'跳转'按钮可切换到对应终端标签" -ForegroundColor Gray
Write-Host "`n卸载命令:" -ForegroundColor White
Write-Host "  .\claude-notification-installer.ps1 -Uninstall" -ForegroundColor Gray
