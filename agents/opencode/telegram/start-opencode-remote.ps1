# opencode-telegram one-click startup script
# Usage: .\start-opencode-remote.ps1 [-WorkingDir <path>] [-NoTui]
#
# This script starts opencode serve on a RANDOM free port, auto-detects that
# port, then launches opencode-telegram pointed at it. No fixed port required,
# so there is never a port conflict (e.g. with Kilo Code on 4096).
#
# The script always starts a dedicated serve so Telegram stays isolated from
# other channels, then stops that serve when the script exits.
#
# By default, this script also starts a local OpenCode TUI attached to the
# same serve for desktop/mobile context switching. Use -NoTui to disable.
#
# By default, opencode serve inherits the current working directory (cwd) from
# the PowerShell session that runs this script. Use -WorkingDir to specify a
# custom project directory for the serve process.

param(
    [string]$WorkingDir,  # Custom project directory for opencode serve
    [switch]$NoTui        # Disable automatic OpenCode TUI startup
)

Write-Host "Starting opencode-telegram remote control..." -ForegroundColor Green
$shouldStartTui = -not $NoTui

# Resolve tool paths from environment variables for portability across users.
$appData = [Environment]::GetEnvironmentVariable('APPDATA', 'Process')
$OpencodeExe = Join-Path $appData "npm\node_modules\opencode-ai\bin\opencode.exe"
$TelegramExe = Join-Path $appData "npm\node_modules\@grinev\opencode-telegram-bot\dist\cli.js"

# Dedicated Windows Terminal profile used to host the OpenCode TUI. It sets
# closeOnExit=always so the tab/window closes automatically when we kill the
# opencode process (a forced kill exits with code 1, which the default
# "graceful" behavior would otherwise keep open). The GUID is fixed so the
# profile is added at most once (idempotent).
$WtTuiProfileName = 'opencode-remote-tui'
$WtTuiProfileGuid = '{2b8f9d7a-6c41-4e2b-9a3d-7f0e1c5a4b6d}'

# Find the listening TCP port owned by a given process id (opencode serve).
function Get-ListenPortForPid {
    param([int]$ProcessId)
    $conn = Get-NetTCPConnection -OwningProcess $ProcessId -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) { return $conn.LocalPort }
    return $null
}

# Ask Windows for an ephemeral port, then pass that nonzero value explicitly.
# OpenCode currently treats --port 0 as falsy and falls back to port 4096.
function Get-FreeTcpPort {
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    } finally {
        $listener.Stop()
    }
}

# Return the ancestor opencode serve when this script was launched by an agent
# task running inside that serve. Replacing that bridge from here is unsafe:
# the old supervisor kills the serve tree, which includes this script.
function Get-AncestorServeProcess {
    $processId = $PID
    for ($depth = 0; $depth -lt 32; $depth++) {
        $process = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
        if (-not $process -or -not $process.ParentProcessId) { return $null }
        $processId = [int]$process.ParentProcessId
        $parent = Get-CimInstance Win32_Process -Filter "ProcessId=$processId" -ErrorAction SilentlyContinue
        if (-not $parent) { return $null }
        if ($parent.Name -eq 'opencode.exe' -and [string]$parent.CommandLine -match '\bserve\b') {
            return $parent
        }
    }
    return $null
}

function Get-ExistingTelegramProcess {
    $escapedCliPath = [Regex]::Escape($TelegramExe)
    return Get-CimInstance Win32_Process -Filter "Name='node.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match $escapedCliPath -and $_.CommandLine -match '\bstart\b' }
}

function Stop-ExistingTelegramProcesses {
    $existing = @(Get-ExistingTelegramProcess)
    if ($existing.Count -eq 0) { return $true }

    $pids = ($existing | ForEach-Object { $_.ProcessId }) -join ', '
    Write-Host "[..] Found existing opencode-telegram process(es): $pids" -ForegroundColor Yellow
    Write-Host "[..] Stopping existing opencode-telegram process tree(s)..." -ForegroundColor Yellow

    foreach ($proc in $existing) {
        try {
            taskkill /PID $proc.ProcessId /T /F 2>$null | Out-Null
        } catch {
            # Ignore and verify after attempting all pids.
        }
    }

    Start-Sleep -Milliseconds 600
    $remaining = @(Get-ExistingTelegramProcess)
    if ($remaining.Count -gt 0) {
        $leftPids = ($remaining | ForEach-Object { $_.ProcessId }) -join ', '
        Write-Host "[!!] Failed to stop existing opencode-telegram process(es): $leftPids" -ForegroundColor Red
        return $false
    }

    Write-Host "[OK] Existing opencode-telegram process(es) stopped." -ForegroundColor Green
    return $true
}

function Write-TelegramConflictHint {
    param([string]$ConfigDir)

    $foundConflict = $false
    $latestLog = Get-ChildItem -Path (Join-Path $ConfigDir 'logs') -Filter 'bot-*.log' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($latestLog) {
        $recentLog = Get-Content -LiteralPath $latestLog.FullName -Tail 80 -ErrorAction SilentlyContinue
        $foundConflict = $recentLog -match 'getUpdates.+409.+Conflict'
    }

    if ($foundConflict) {
        Write-Host "[!!] Telegram getUpdates conflict detected." -ForegroundColor Red
    } else {
        Write-Host "[i] If the error above says 'getUpdates' and '409: Conflict':" -ForegroundColor Cyan
    }
    Write-Host "     Another running process is using the same Telegram Bot Token." -ForegroundColor Cyan
    Write-Host "     Stop the old bot on every machine, or revoke/regenerate the token in @BotFather." -ForegroundColor Cyan
    Write-Host "     This is not an OpenCode port, SQLite, or serve startup problem." -ForegroundColor Cyan
}

# Read the current session ID from Telegram bot log
function Get-TelegramSessionId {
    param(
        [string]$LogPath
    )
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }

    $sessionId = $null
    $lines = @(Get-Content -LiteralPath $LogPath -Tail 200 -ErrorAction SilentlyContinue)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match '\[Attach\] (?:Attached to session|Restored followed session on startup): session=(ses_[A-Za-z0-9]+)') {
            $sessionId = $Matches[1]
            break
        }
    }
    return $sessionId
}

function Stop-TuiProcesses {
    param(
        [string]$ServerUrl,
        [System.Collections.Generic.List[int]]$Pids
    )

    # 1) Deterministic: kill every TUI PID this script started, tree included.
    #    This does not depend on WMI command-line matching being up to date,
    #    which is the reliable way to close the old TUI on session switch and
    #    on Ctrl+C.
    if ($Pids -and $Pids.Count -gt 0) {
        foreach ($tuiPid in @($Pids)) {
            taskkill /PID $tuiPid /T /F 2>$null | Out-Null
        }
        $Pids.Clear()
    }

    # 2) Backstop: sweep any stray "opencode attach" against our serve URL that
    #    we may not have tracked (e.g. a TUI that was reparented).
    if ($ServerUrl) {
        $escapedUrl = [Regex]::Escape($ServerUrl)
        $attachProcs = Get-CimInstance Win32_Process -Filter "Name='opencode.exe'" -ErrorAction SilentlyContinue |
            Where-Object { [string]$_.CommandLine -match '\battach\b' -and [string]$_.CommandLine -match $escapedUrl }
        foreach ($p in $attachProcs) {
            taskkill /PID $p.ProcessId /T /F 2>$null | Out-Null
        }
    }

    Start-Sleep -Milliseconds 400
}

# Ensure a dedicated Windows Terminal profile (closeOnExit=always) exists so the
# TUI window closes when we kill the opencode process. Idempotent: if a profile
# with our fixed GUID already exists, nothing is changed. Returns $true when the
# profile is available for launching, $false to fall back to a direct launch.
function Initialize-OpenCodeTuiProfile {
    param(
        [string]$ProfileName,
        [string]$ProfileGuid
    )

    if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) { return $false }

    $settingsPath = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
    if (-not (Test-Path -LiteralPath $settingsPath)) {
        $settingsPath = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json'
    }
    if (-not (Test-Path -LiteralPath $settingsPath)) { return $false }

    try {
        $raw = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop
        $json = $raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        # settings.json uses JSONC (comments/trailing commas) that PowerShell
        # cannot parse safely. Do not risk corrupting it; fall back instead.
        Write-Host "[i] Could not parse Windows Terminal settings.json; TUI windows will not auto-close." -ForegroundColor DarkGray
        return $false
    }

    if (-not $json.profiles) { return $false }
    $list = $json.profiles.list
    if ($null -eq $list) { return $false }

    if ($list | Where-Object { $_.guid -eq $ProfileGuid }) {
        return $true  # Already present; nothing to do.
    }

    $newProfile = [pscustomobject][ordered]@{
        guid                     = $ProfileGuid
        name                     = $ProfileName
        hidden                   = $true
        closeOnExit              = 'always'
        suppressApplicationTitle = $true
    }
    $json.profiles.list = @($list) + $newProfile

    try {
        Copy-Item -LiteralPath $settingsPath -Destination "$settingsPath.bak" -Force -ErrorAction SilentlyContinue
        ($json | ConvertTo-Json -Depth 32) | Set-Content -LiteralPath $settingsPath -Encoding UTF8
        Write-Host "[OK] Added Windows Terminal profile '$ProfileName' (closeOnExit=always)." -ForegroundColor Green
        Write-Host "[i] A backup was saved to settings.json.bak (file formatting may change)." -ForegroundColor DarkGray
        return $true
    } catch {
        Write-Host "[i] Failed to update Windows Terminal settings.json; TUI windows will not auto-close." -ForegroundColor DarkGray
        return $false
    }
}

# Start an OpenCode TUI attached to a session. When $UseWt is set, the TUI is
# launched in a dedicated Windows Terminal window using our closeOnExit=always
# profile (so the window auto-closes when the process is killed). Otherwise it
# is launched directly. Returns the opencode.exe PID (for deterministic
# cleanup) or $null.
function Start-OpenCodeTui {
    param(
        [string]$ServerUrl,
        [string]$SessionId,
        [string]$Dir,
        [bool]$UseWt,
        [string]$OpencodeExe,
        [string]$ProfileName
    )

    if ($UseWt) {
        Start-Process -FilePath 'wt.exe' -ArgumentList @(
            '-w', 'new',
            '-p', $ProfileName,
            $OpencodeExe, 'attach', $ServerUrl, '--session', $SessionId, '--dir', $Dir
        ) | Out-Null

        # wt.exe is only a launcher; poll for the real opencode attach process
        # so we can track and kill it deterministically later.
        $escapedUrl = [Regex]::Escape($ServerUrl)
        $escapedSession = [Regex]::Escape($SessionId)
        for ($i = 0; $i -lt 12; $i++) {
            Start-Sleep -Milliseconds 400
            $p = Get-CimInstance Win32_Process -Filter "Name='opencode.exe'" -ErrorAction SilentlyContinue |
                Where-Object {
                    [string]$_.CommandLine -match '\battach\b' -and
                    [string]$_.CommandLine -match $escapedUrl -and
                    [string]$_.CommandLine -match $escapedSession
                } | Select-Object -First 1
            if ($p) { return [int]$p.ProcessId }
        }
        return $null
    }

    $proc = Start-Process -FilePath $OpencodeExe `
        -ArgumentList @('attach', $ServerUrl, '--session', $SessionId, '--dir', $Dir) `
        -WorkingDirectory $Dir -WindowStyle Normal -PassThru
    return [int]$proc.Id
}

# Track the bot process started by this script.
$startedBot = $null

# Track every TUI window started by this script so we can close all of them on
# session switch and on exit. We track PIDs (not a single handle) so a stale
# TUI from a previous session is always reaped.
$startedTuiPids = New-Object System.Collections.Generic.List[int]

# Whether to host the TUI in a dedicated Windows Terminal profile that
# auto-closes its window when the process is killed.
$useWtForTui = $false

$serverUrl = $null

$processEnvironment = [Environment]::GetEnvironmentVariables('Process')
$hadOpencodeApiUrl = $processEnvironment.Contains('OPENCODE_API_URL')
$previousOpencodeApiUrl = [Environment]::GetEnvironmentVariable('OPENCODE_API_URL', 'Process')
$hadNodeUseSystemCa = $processEnvironment.Contains('NODE_USE_SYSTEM_CA')
$previousNodeUseSystemCa = [Environment]::GetEnvironmentVariable('NODE_USE_SYSTEM_CA', 'Process')

try {
    if (-not (Test-Path -LiteralPath $OpencodeExe -PathType Leaf)) {
        Write-Host "[!!] opencode.exe not found at:" -ForegroundColor Red
        Write-Host "   $OpencodeExe" -ForegroundColor Cyan
        exit 1
    }
    if (-not (Test-Path -LiteralPath $TelegramExe -PathType Leaf)) {
        Write-Host "[!!] opencode-telegram not found at:" -ForegroundColor Red
        Write-Host "   $TelegramExe" -ForegroundColor Cyan
        Write-Host "   Install it with: npm install -g @grinev/opencode-telegram-bot" -ForegroundColor Cyan
        exit 1
    }
    if (-not (Stop-ExistingTelegramProcesses)) {
        Write-Host "   Stop the existing bot manually, then retry." -ForegroundColor Cyan
        exit 1
    }
    if ($WorkingDir -and -not (Test-Path -LiteralPath $WorkingDir -PathType Container)) {
        Write-Host "[!!] Working directory does not exist: $WorkingDir" -ForegroundColor Red
        exit 1
    }
    $effectiveCwd = if ($WorkingDir) { (Resolve-Path -LiteralPath $WorkingDir).Path } else { (Get-Location).Path }

    $ancestorServe = Get-AncestorServeProcess
    if ($ancestorServe) {
        Write-Host "[!!] Refusing to switch projects from inside an OpenCode task." -ForegroundColor Red
        Write-Host "     This script is a descendant of serve PID $($ancestorServe.ProcessId)." -ForegroundColor Red
        Write-Host "     Replacing its bridge would make the old supervisor terminate this task mid-switch." -ForegroundColor Cyan
        Write-Host "     Run this command from an independent PowerShell window instead:" -ForegroundColor Cyan
        Write-Host "     $($MyInvocation.MyCommand.Path) -WorkingDir `"$effectiveCwd`"" -ForegroundColor Cyan
        exit 2
    }

    if ($WorkingDir) {
        Write-Host "[i] Using custom working directory: $effectiveCwd" -ForegroundColor Cyan
    }

    $requestedPort = Get-FreeTcpPort
    Write-Host "[..] Starting dedicated opencode serve on free port $requestedPort..." -ForegroundColor Yellow
    $startedServe = Start-Process -FilePath $OpencodeExe `
        -ArgumentList "serve --port $requestedPort" `
        -WindowStyle Hidden -PassThru `
        -WorkingDirectory $effectiveCwd

    # Poll for up to ~15s until the server binds a port, bailing out early
    # if the process crashes.
    $port = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        if ($startedServe.HasExited) {
            Write-Host "[!!] opencode serve exited unexpectedly (code $($startedServe.ExitCode))." -ForegroundColor Red
            $startedServe = $null
            break
        }
        $port = Get-ListenPortForPid -ProcessId $startedServe.Id
        if ($port) { break }
    }

    if ($port) {
        Write-Host "[OK] Dedicated opencode serve started on port $port (PID $($startedServe.Id))" -ForegroundColor Green
    } else {
        Write-Host "[!!] Failed to start opencode serve." -ForegroundColor Red
        exit 1
    }

    # opencode-telegram reads its config from %APPDATA%\opencode-telegram-bot\.env.
    # We override OPENCODE_API_URL to point at the serve we just resolved.
    # This ensures the bot talks to the correct project-scoped serve.
    $serverUrl = "http://127.0.0.1:$port"
    [Environment]::SetEnvironmentVariable('OPENCODE_API_URL', $serverUrl, 'Process')

    # opencode-telegram stores its config and data under:
    #   %APPDATA%\opencode-telegram-bot\  (on Windows)
    # Unlike opencode-lark, it does NOT hash by cwd — it uses a single config
    # directory. The OPENCODE_API_URL override above is what ties it to the
    # correct project. This is fine for the "one project per bot" model.
    $TelegramConfigDir = Join-Path $appData "opencode-telegram-bot"
    if (-not (Test-Path $TelegramConfigDir)) {
        New-Item -ItemType Directory -Path $TelegramConfigDir -Force | Out-Null
    }

    # Check if the bot has been configured (has a .env with a bot token).
    $envFile = Join-Path $TelegramConfigDir ".env"
    if (-not (Test-Path $envFile)) {
        Write-Host "[!!] opencode-telegram not configured yet." -ForegroundColor Red
        Write-Host "   Run: opencode-telegram config" -ForegroundColor Cyan
        Write-Host "   Then re-run this script." -ForegroundColor Cyan
        exit 1
    }

    # Check if a bot token is present.
    $envContent = Get-Content $envFile -Raw -ErrorAction SilentlyContinue
    if (-not $envContent -or $envContent -notmatch 'TELEGRAM_BOT_TOKEN=\S+') {
        Write-Host "[!!] TELEGRAM_BOT_TOKEN not found in $envFile" -ForegroundColor Red
        Write-Host "   Run: opencode-telegram config" -ForegroundColor Cyan
        exit 1
    }

    # Check if an allowed user ID is present.
    if ($envContent -notmatch 'TELEGRAM_ALLOWED_USER_ID=\d+') {
        Write-Host "[!!] TELEGRAM_ALLOWED_USER_ID not found in $envFile" -ForegroundColor Red
        Write-Host "   Run: opencode-telegram config" -ForegroundColor Cyan
        exit 1
    }

    $hasTelegramProxy = $envContent -match '(?m)^\s*TELEGRAM_PROXY_URL=\S+'
    $hasTelegramApiRoot = $envContent -match '(?m)^\s*TELEGRAM_API_ROOT=\S+'

    # Show the Telegram network mode before starting the bot. The bot itself
    # performs API connectivity through Node.js and honors its proxy settings.
    if ($hasTelegramProxy -or $hasTelegramApiRoot) {
        Write-Host "[i] Telegram proxy/reverse-proxy configured." -ForegroundColor Cyan
    } else {
        Write-Host "[i] No Telegram proxy configured; bot will use direct API access." -ForegroundColor Cyan
    }

    # Use node to run the CLI directly, passing the OPENCODE_API_URL env var.
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) {
        Write-Host "[!!] node not found in PATH" -ForegroundColor Red
        exit 1
    }
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', '1', 'Process')

    # Start opencode-telegram in background with log redirection
    Write-Host "[..] Starting opencode-telegram -> $serverUrl" -ForegroundColor Green
    Write-Host "[i] Config dir: $TelegramConfigDir" -ForegroundColor DarkGray
    Write-Host "[i] Bot will use long polling (no inbound port required)" -ForegroundColor DarkGray
    
    $botLogOut = Join-Path $env:TEMP "opencode-telegram-stdout.log"
    $botLogErr = Join-Path $env:TEMP "opencode-telegram-stderr.log"
    Remove-Item $botLogOut, $botLogErr -ErrorAction SilentlyContinue
    
    Push-Location $TelegramConfigDir
    try {
        $botProc = Start-Process -FilePath $nodeExe `
            -ArgumentList $TelegramExe, "start" `
            -WorkingDirectory $TelegramConfigDir `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $botLogOut -RedirectStandardError $botLogErr
        $startedBot = $botProc
    } finally {
        Pop-Location
    }
    
    # Verify bot actually stayed alive
    for ($i = 0; $i -lt 4; $i++) {
        Start-Sleep -Seconds 1
        $botProc.Refresh()
        if ($botProc.HasExited) { break }
    }
    if ($botProc.HasExited) {
        Write-Host "[!!] opencode-telegram exited immediately (code $($botProc.ExitCode))." -ForegroundColor Red
        $errTail = Get-Content $botLogErr -ErrorAction SilentlyContinue -Tail 10
        if ($errTail) {
            Write-Host "   --- stderr ---" -ForegroundColor DarkGray
            $errTail | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
        }
        Write-TelegramConflictHint -ConfigDir $TelegramConfigDir
        exit 1
    }
    Write-Host "[OK] opencode-telegram started (PID $($botProc.Id))" -ForegroundColor Green

    if ($shouldStartTui) {
        # Prepare a dedicated Windows Terminal profile so TUI windows auto-close
        # when we kill the opencode process on session switch / exit.
        $useWtForTui = Initialize-OpenCodeTuiProfile -ProfileName $WtTuiProfileName -ProfileGuid $WtTuiProfileGuid
        if ($useWtForTui) {
            Write-Host "[i] TUI windows will auto-close via Windows Terminal profile '$WtTuiProfileName'." -ForegroundColor DarkGray
        } else {
            Write-Host "[i] Auto-close profile unavailable; a killed TUI tab may need manual closing." -ForegroundColor DarkGray
        }

        # Wait for bot to create/restore session, then start TUI attached to it
        Write-Host ""
        Write-Host "[..] Waiting for Telegram bot session..." -ForegroundColor Yellow
        Write-Host "    Press Ctrl+C to stop everything." -ForegroundColor Yellow
        
        $currentSessionId = $null
        while ($true) {
            $botProc.Refresh()
            if ($botProc.HasExited) {
                Write-Host "[!!] opencode-telegram has exited." -ForegroundColor Red
                break
            }
            
            # Check for session in bot log
            $sessionId = Get-TelegramSessionId -LogPath $botLogOut
            if ($sessionId -and $sessionId -ne $currentSessionId) {
                $currentSessionId = $sessionId
                Write-Host "[OK] Found Telegram bot session: $sessionId" -ForegroundColor Green
                
                # Close the previous TUI(s) before opening the new one. We kill
                # the tracked PID tree first (deterministic), then sweep by URL.
                Write-Host "[..] Stopping old TUI window(s)..." -ForegroundColor Yellow
                Stop-TuiProcesses -ServerUrl $serverUrl -Pids $startedTuiPids
                
                # Start new TUI attached to this session
                Write-Host "[..] Starting TUI attached to session $sessionId..." -ForegroundColor Green
                try {
                    $tuiPid = Start-OpenCodeTui -ServerUrl $serverUrl -SessionId $sessionId -Dir $effectiveCwd `
                        -UseWt $useWtForTui -OpencodeExe $OpencodeExe -ProfileName $WtTuiProfileName
                    if ($tuiPid) {
                        $startedTuiPids.Add($tuiPid)
                        Write-Host "[OK] OpenCode TUI started (PID $tuiPid)" -ForegroundColor Green
                    } else {
                        Write-Host "[!!] Could not confirm the OpenCode TUI process (it may still have opened)." -ForegroundColor Red
                    }
                } catch {
                    Write-Host "[!!] Failed to start OpenCode TUI: $($_.Exception.Message)" -ForegroundColor Red
                }
            }
            
            Start-Sleep -Seconds 2
        }
    } else {
        Write-Host "[i] TUI disabled for this run (-NoTui)." -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "Bot is running. Send a message on Telegram to start chatting." -ForegroundColor Cyan
        Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray
        
        # Wait for bot process
        try {
            $botProc.WaitForExit()
        } catch {
            # Interrupted by Ctrl+C
        }
        
        if ($botProc.HasExited -and $botProc.ExitCode -ne 0) {
            Write-Host "[!!] opencode-telegram exited with code $($botProc.ExitCode)." -ForegroundColor Red
            Write-TelegramConflictHint -ConfigDir $TelegramConfigDir
        }
    }

} finally {
    # Stop processes that this script started.

    # Close TUI windows first so no stale attach console survives Ctrl+C.
    Write-Host "[..] Closing OpenCode TUI window(s)..." -ForegroundColor Yellow
    Stop-TuiProcesses -ServerUrl $serverUrl -Pids $startedTuiPids

    if ($startedBot) {
        Write-Host "[..] Stopping opencode-telegram (PID $($startedBot.Id))..." -ForegroundColor Yellow
        try {
            taskkill /PID $startedBot.Id /T /F 2>$null | Out-Null
        } catch {
            # Process may have already exited.
        }
    }

    if ($startedServe) {
        Write-Host "[..] Stopping opencode serve (PID $($startedServe.Id))..." -ForegroundColor Yellow
        try {
            taskkill /PID $startedServe.Id /T /F 2>$null | Out-Null
        } catch {
            # Process may have already exited.
        }
    }
    if ($hadOpencodeApiUrl) {
        [Environment]::SetEnvironmentVariable('OPENCODE_API_URL', $previousOpencodeApiUrl, 'Process')
    } else {
        [Environment]::SetEnvironmentVariable('OPENCODE_API_URL', $null, 'Process')
    }
    if ($hadNodeUseSystemCa) {
        [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', $previousNodeUseSystemCa, 'Process')
    } else {
        [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', $null, 'Process')
    }

    Write-Host "[OK] Cleanup complete." -ForegroundColor Green
}
