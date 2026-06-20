<#
.SYNOPSIS  定时把 OpenClawGateway 归档自动提交并推送 GitHub（带机密扫描守卫）。
.DESCRIPTION
  由 "OpenClawGateway AutoPush" 计划任务每日调用：有改动才提交；推送前扫描机密，命中即中止。
.NOTES  无改动则静默退出。
#>
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$logDir = Join-Path $repo 'logs'; New-Item -ItemType Directory -Force $logDir | Out-Null
$log = Join-Path $logDir 'auto-push.log'
function Log([string]$m){ ('{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) | Out-File $log -Append -Encoding utf8 }

# 1. 有改动才继续
$dirty = git -C $repo status --porcelain
if (-not $dirty) { Log 'no changes'; exit 0 }

# 2. 暂存 + 机密扫描守卫
git -C $repo add -A | Out-Null
# 排除本脚本自身（它定义了模式串，避免自我误报）
$staged = git -C $repo diff --cached --text -- . ':(exclude)tools/auto-archive-push.ps1' 2>$null | Out-String
# 模式拆分拼接，使本文件源码不字面包含完整模式
$patterns = (('8857'+'353244'),('sk-'+'ws-'),('wlySecure'+'Claw2026'),('-----BEGIN '+'PRIVATE KEY-----'),('AAHswW0'+'qeNXs'),('Vvul'+'WjvTbSDx')) -join '|'
if ($staged -match $patterns) {
    git -C $repo reset | Out-Null
    Log '[ABORT] 检测到疑似机密，已中止自动推送（请人工检查）'
    exit 1
}

# 3. 提交 + 推送
$msg = 'chore: auto-archive ' + (Get-Date -Format 'yyyy-MM-dd HH:mm')
git -C $repo -c user.name='吴乐阳' -c user.email='wlyaaaaa@gmail.com' commit -q -m $msg | Out-Null
$branch = git -C $repo rev-parse --abbrev-ref HEAD
git -C $repo push -q origin $branch 2>&1 | Out-Null
Log ('[OK] pushed: ' + (git -C $repo rev-parse --short HEAD))
