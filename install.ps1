# Claude Code 通知系统安装脚本
# 功能：Claude 停止时发送 Windows Toast 通知
# 依赖：PowerShell 7 + BurntToast 模块

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
        "$claudeDir\stop-hook-handler.ps1"
    )
    foreach ($file in $filesToRemove) {
        if (Test-Path $file) {
            Remove-Item $file -Force
            Write-Host "  已删除: $file" -ForegroundColor Gray
        }
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

Write-Host "`n[1/2] 检查依赖..." -ForegroundColor Yellow

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

Write-Host "`n[2/2] 创建脚本并配置 hooks..." -ForegroundColor Yellow

# ============ stop-hook-handler.ps1 ============
$stopHookScript = @'
# Claude Code Stop Hook - 发送通知
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

# 获取目录信息
$workDir = $PWD.Path
$tabTitle = $Host.UI.RawUI.WindowTitle
$dir = Split-Path -Leaf $workDir

# 发送通知
Import-Module BurntToast -ErrorAction SilentlyContinue
if (Get-Module BurntToast) {
    try {
        New-BurntToastNotification -Text "Claude 已停止", $summary, "标题: $tabTitle | 目录: $dir"
    } catch {
        New-BurntToastNotification -Text "Claude 已停止", $summary, "目录: $dir"
    }
}
'@

Set-Content -Path "$claudeDir\stop-hook-handler.ps1" -Value $stopHookScript -Encoding UTF8
Write-Host "  stop-hook-handler.ps1" -ForegroundColor Green

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
Write-Host "`n卸载命令:" -ForegroundColor White
Write-Host "  .\install.ps1 -Uninstall" -ForegroundColor Gray
