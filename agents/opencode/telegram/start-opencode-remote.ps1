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
        Where-Object { $_.CommandLine -match $escapedCliPath -and $_.CommandLine -match '\bstart\b' } |
        Select-Object -First 1
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

# Track the dedicated serve so we can clean it up on exit.
$startedServe = $null

# Track a TUI window started by this script so we can close it on exit.
$startedTui = $null

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
    $existingTelegram = Get-ExistingTelegramProcess
    if ($existingTelegram) {
        Write-Host "[!!] opencode-telegram is already running (PID $($existingTelegram.ProcessId))." -ForegroundColor Red
        Write-Host "   Stop the existing bot before starting another instance." -ForegroundColor Cyan
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

    if ($shouldStartTui) {
        Write-Host "[..] Starting OpenCode TUI attached to $serverUrl ..." -ForegroundColor Green
        try {
            $startedTui = Start-Process -FilePath $OpencodeExe `
                -ArgumentList @('attach', $serverUrl, '--dir', $effectiveCwd) `
                -WorkingDirectory $effectiveCwd -WindowStyle Normal -PassThru
            Write-Host "[OK] OpenCode TUI started (PID $($startedTui.Id))" -ForegroundColor Green
        } catch {
            Write-Host "[!!] Failed to start OpenCode TUI: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

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

    # Start opencode-telegram in foreground (blocking).
    # The bot uses long polling — no inbound port needed.
    # It will stay running until Ctrl+C or the bot exits.
    Write-Host "[..] Starting opencode-telegram -> $serverUrl" -ForegroundColor Green
    Write-Host "[i] Config dir: $TelegramConfigDir" -ForegroundColor DarkGray
    Write-Host "[i] Bot will use long polling (no inbound port required)" -ForegroundColor DarkGray
    if ($NoTui) {
        Write-Host "[i] TUI disabled for this run (-NoTui)." -ForegroundColor DarkGray
    }

    # Use node to run the CLI directly, passing the OPENCODE_API_URL env var.
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) {
        Write-Host "[!!] node not found in PATH" -ForegroundColor Red
        exit 1
    }
    [Environment]::SetEnvironmentVariable('NODE_USE_SYSTEM_CA', '1', 'Process')

    Write-Host ""
    Write-Host "Bot is running. Send a message on Telegram to start chatting." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

    # Run in the current console so Ctrl+C reaches the bot. Once it exits,
    # PowerShell continues into finally and cleans up the dedicated serve.
    Push-Location $TelegramConfigDir
    try {
        & $nodeExe $TelegramExe start
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[!!] opencode-telegram exited with code $LASTEXITCODE." -ForegroundColor Red
            Write-TelegramConflictHint -ConfigDir $TelegramConfigDir
        }
    } finally {
        Pop-Location
    }

} finally {
    # Stop processes that this script started.

    if ($startedServe) {
        Write-Host "[..] Stopping opencode serve (PID $($startedServe.Id))..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $startedServe.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # Process may have already exited.
        }
    }
    if ($startedTui) {
        Write-Host "[..] Closing OpenCode TUI (PID $($startedTui.Id))..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $startedTui.Id -Force -ErrorAction SilentlyContinue
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
