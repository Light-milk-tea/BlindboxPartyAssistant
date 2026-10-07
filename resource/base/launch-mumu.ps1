param(
    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $PSScriptRoot '..\..\debug'
if (-not (Test-Path -LiteralPath $logDir)) {
    $logDir = $PSScriptRoot
}
$script:LogFile = Join-Path ([System.IO.Path]::GetFullPath($logDir)) 'launch-mumu.log'

function Write-Log {
    param([string]$Message)
    $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
    Write-Output $line
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Read-JsonFile {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path)
    return $text | ConvertFrom-Json
}

function Add-ManagerCandidate {
    param(
        [System.Collections.Generic.List[string]]$List,
        [string]$Path
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return }
    $candidate = $Path.Trim().Trim('"')
    $name = [System.IO.Path]::GetFileName($candidate)
    if ($name -ieq 'MuMuNxMain.exe') {
        $candidate = Join-Path (Split-Path -Parent $candidate) 'MuMuManager.exe'
    }
    elseif ($name -ine 'MuMuManager.exe') {
        $joined = Join-Path $candidate 'nx_main\MuMuManager.exe'
        if (Test-Path -LiteralPath $joined) {
            $candidate = $joined
        }
    }
    if (-not (Test-Path -LiteralPath $candidate)) { return }
    if ([System.IO.Path]::GetFileName($candidate) -ine 'MuMuManager.exe') { return }
    $full = [System.IO.Path]::GetFullPath($candidate)
    if (-not $List.Contains($full)) {
        [void]$List.Add($full)
    }
}

function Get-InstanceFiles {
    $dirs = New-Object System.Collections.Generic.List[string]
    $addDir = {
        param($Dir)
        if ([string]::IsNullOrWhiteSpace($Dir)) { return }
        try { $Dir = [System.IO.Path]::GetFullPath($Dir) } catch { return }
        if ((Test-Path -LiteralPath $Dir) -and -not $dirs.Contains($Dir)) {
            [void]$dirs.Add($Dir)
        }
    }
    & $addDir (Join-Path (Get-Location) '..\..\config\instances')
    & $addDir (Join-Path $PSScriptRoot '..\..\.create-maa-project\runtime\mfaa\win-x64\config\instances')
    Get-CimInstance Win32_Process -Filter "Name = 'MFAAvalonia.exe'" | ForEach-Object {
        if ($_.ExecutablePath) {
            & $addDir (Join-Path (Split-Path -Parent $_.ExecutablePath) 'config\instances')
        }
    }
    $files = @()
    foreach ($dir in $dirs) {
        $files += @(Get-ChildItem -LiteralPath $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)
    }
    return @($files | Sort-Object LastWriteTime -Descending)
}

function Get-LaunchConfig {
    if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
        $file = Get-Item -LiteralPath $ConfigPath
        $config = Read-JsonFile $file.FullName
        return [pscustomobject]@{ File = $file; Config = $config }
    }
    foreach ($file in @(Get-InstanceFiles)) {
        $config = Read-JsonFile $file.FullName
        $item = @($config.TaskItems) | Where-Object { $_.name -eq 'LaunchMuMu' } | Select-Object -First 1
        if ($null -ne $item) {
            return [pscustomobject]@{ File = $file; Config = $config }
        }
    }
    return $null
}

function Find-MuMuManager {
    param($Config)
    $found = New-Object System.Collections.Generic.List[string]
    Add-ManagerCandidate $found ([string]$Config.SoftwarePath)
    $rawConfig = [string]$Config.AdbDevice.Config
    if (-not [string]::IsNullOrWhiteSpace($rawConfig)) {
        try {
            $extra = $rawConfig | ConvertFrom-Json
            Add-ManagerCandidate $found ([string]$extra.extras.mumu.path)
        }
        catch {
            Write-Log ("ignore device config: {0}" -f $_.Exception.Message)
        }
    }
    Get-CimInstance Win32_Process | Where-Object {
        $_.Name -match '^MuMu(Manager|NxMain|NxDevice|Player)'
    } | ForEach-Object {
        Add-ManagerCandidate $found ([string]$_.ExecutablePath)
    }
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue | ForEach-Object {
            $entry = Get-ItemProperty -LiteralPath $_.PSPath -ErrorAction SilentlyContinue
            if ([string]$entry.DisplayName -notmatch 'MuMu') { return }
            Add-ManagerCandidate $found ([string]$entry.InstallLocation)
            Add-ManagerCandidate $found ([string]$entry.DisplayIcon)
        }
    }
    return $found
}

function Get-InstanceIndex {
    param($Config)
    $rawConfig = [string]$Config.AdbDevice.Config
    if (-not [string]::IsNullOrWhiteSpace($rawConfig)) {
        try {
            $extra = $rawConfig | ConvertFrom-Json
            if ($null -ne $extra.extras.mumu.index -and "$($extra.extras.mumu.index)" -ne '') {
                return [int]$extra.extras.mumu.index
            }
        }
        catch { }
    }
    if ([string]$Config.EmulatorConfig -match '-v\s+(\d+)') {
        return [int]$Matches[1]
    }
    return 0
}

function Invoke-MuMu {
    param(
        [string]$Manager,
        [string[]]$ArgumentList
    )
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $Manager
    $psi.WorkingDirectory = Split-Path -Parent $Manager
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.Arguments = ($ArgumentList -join ' ')
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output   = ($stdout + "`n" + $stderr)
    }
}

function Get-MuMuInfo {
    param(
        [string]$Manager,
        [int]$Index
    )
    $result = Invoke-MuMu $Manager @('info', '-v', "$Index")
    $output = [string]$result.Output
    $start = $output.IndexOf('{')
    $end = $output.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        Write-Log ("MuMu info has no json: {0}" -f $output.Trim())
        return $null
    }
    $json = $output.Substring($start, $end - $start + 1)
    return $json | ConvertFrom-Json
}

function Test-AndroidStarted {
    param($Info)
    if ($null -eq $Info) { return $false }
    $value = $Info.is_android_started
    return ($value -eq $true) -or ("$value" -eq 'true')
}

function Connect-MuMuAdb {
    param(
        [string]$Manager,
        $Info
    )
    if ($null -eq $Info -or $null -eq $Info.adb_port) { return }
    $adb = Join-Path (Split-Path -Parent $Manager) 'adb.exe'
    if (-not (Test-Path -LiteralPath $adb)) {
        Write-Log 'adb.exe not found beside MuMuManager'
        return
    }
    $hostIp = [string]$Info.adb_host_ip
    if ([string]::IsNullOrWhiteSpace($hostIp)) { $hostIp = '127.0.0.1' }
    $address = '{0}:{1}' -f $hostIp, $Info.adb_port
    $result = Invoke-MuMu $adb @('connect', $address)
    Write-Log ("adb connect {0}: {1}" -f $address, ([string]$result.Output).Trim())
}

try {
    $loaded = Get-LaunchConfig
    if ($null -eq $loaded) {
        Write-Log 'LaunchMuMu is not in the instance config yet, skip'
        exit 0
    }
    $config = $loaded.Config
    $item = @($config.TaskItems) | Where-Object { $_.name -eq 'LaunchMuMu' } | Select-Object -First 1
    if ($null -eq $item) {
        Write-Log 'LaunchMuMu is not in the instance config yet, skip'
        exit 0
    }
    $checked = $item.default_check
    if ($null -eq $checked) { $checked = $true }
    if (-not $checked) {
        Write-Log 'LaunchMuMu unchecked, skip'
        exit 0
    }

    $managers = @(Find-MuMuManager $config)
    if ($managers.Count -eq 0) {
        Write-Log 'MuMuManager.exe not found'
        exit 1
    }
    $manager = $managers[0]
    $index = Get-InstanceIndex $config
    Write-Log ("use {0} -v {1}" -f $manager, $index)

    $info = Get-MuMuInfo $manager $index
    if (Test-AndroidStarted $info) {
        Write-Log 'android already started, skip launch'
        Connect-MuMuAdb $manager $info
        exit 0
    }

    Write-Log 'launching MuMu'
    $launch = Invoke-MuMu $manager @('control', '-v', "$index", 'launch')
    Write-Log ("launch exit {0}" -f $launch.ExitCode)
    $deadline = (Get-Date).AddSeconds(180)
    do {
        Start-Sleep -Seconds 2
        $info = Get-MuMuInfo $manager $index
        if (Test-AndroidStarted $info) {
            Write-Log 'android started'
            Connect-MuMuAdb $manager $info
            exit 0
        }
    } while ((Get-Date) -lt $deadline)

    Write-Log 'timed out waiting for MuMu android'
    exit 2
}
catch {
    Write-Log ("failed: {0}" -f $_.Exception.Message)
    exit 1
}
