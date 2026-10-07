param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('start', 'check')]
    [string]$Mode,
    [string]$Minutes = '0'
)

$ErrorActionPreference = 'Stop'

$debugDir = Join-Path $PSScriptRoot '..\..\debug'
if (-not (Test-Path -LiteralPath $debugDir)) {
    New-Item -ItemType Directory -Path $debugDir | Out-Null
}
$debugDir = [System.IO.Path]::GetFullPath($debugDir)
$stateFile = Join-Path $debugDir 'idle-budget.txt'
$logFile = Join-Path $debugDir 'idle-budget.log'

function Write-BudgetLog {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

if ($Mode -eq 'start') {
    $minutes = 0
    if (-not [int]::TryParse($Minutes, [ref]$minutes) -or $minutes -lt 0) {
        $minutes = 0
    }
    if ($minutes -eq 0) {
        Set-Content -LiteralPath $stateFile -Value 'unlimited' -Encoding ascii
        Write-BudgetLog 'start unlimited'
    }
    else {
        $deadline = (Get-Date).AddMinutes($minutes).Ticks
        Set-Content -LiteralPath $stateFile -Value "$deadline" -Encoding ascii
        Write-BudgetLog ("start {0} minutes" -f $minutes)
    }
    exit 0
}

try {
    if (-not (Test-Path -LiteralPath $stateFile)) { exit 0 }
    $text = ([System.IO.File]::ReadAllText($stateFile)).Trim()
    if ($text -eq '' -or $text -eq 'unlimited') { exit 0 }
    $ticks = [int64]$text
    if ((Get-Date).Ticks -ge $ticks) {
        Write-BudgetLog 'time up'
        exit 1
    }
    exit 0
}
catch {
    exit 0
}
