# opencode-telegram one-click startup script
# Usage: .\start-opencode-remote.ps1 [-WorkingDir <path>]
#
# This script starts opencode serve on a RANDOM free port, auto-detects that
# port, then launches opencode-telegram pointed at it. No fixed port required,
# so there is never a port conflict (e.g. with Kilo Code on 4096).
#
# A serve started by THIS script is stopped again when the script exits.
# An already-running serve that we merely reuse is left untouched.
#
# By default, opencode serve inherits the current working directory (cwd) from
# the PowerShell session that runs this script. Use -WorkingDir to specify a
# custom project directory for the serve process.

param(
    [string]$WorkingDir  # Custom project directory for opencode serve
)

Write-Host "Starting opencode-telegram remote control..." -ForegroundColor Green

# Resolve tool paths from environment variables for portability across users.
$OpencodeExe = Join-Path $env:APPDATA "npm\node_modules\opencode-ai\bin\opencode.exe"

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

# True only if the process was launched as "opencode serve". This distinguishes
# a real server from a TUI instance even if a TUI ever bound a TCP port.
function Test-IsServeProcess {
    param([int]$ProcessId)
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue).CommandLine
    return ($cmd -match '\bserve\b')
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

# Detect an already-running opencode serve: an opencode.exe launched with
# "serve" that owns a listening port. TUI instances are skipped. When several
# serves are running, prefer the most recently started one (deterministic).
function Find-ExistingServePort {
    param([string]$Directory)

    $targetDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    $procs = Get-Process -Name opencode -ErrorAction SilentlyContinue |
        Sort-Object StartTime -Descending
    foreach ($proc in $procs) {
        if (-not (Test-IsServeProcess -ProcessId $proc.Id)) { continue }
        $p = Get-ListenPortForPid -ProcessId $proc.Id
        if (-not $p) { continue }
        try {
            $serverPath = Invoke-RestMethod -Uri "http://127.0.0.1:$p/path" -TimeoutSec 2
            $serverDirectory = [IO.Path]::GetFullPath([string]$serverPath.directory).TrimEnd('\', '/')
            if ($serverDirectory.Equals($targetDirectory, [StringComparison]::OrdinalIgnoreCase)) {
                return $p
            }
        } catch {
            continue
        }
    }
    return $null
}

# Track a serve that WE start, so we can clean it up on exit. Stays $null when
# we reuse an existing serve (which we must not kill).
$script:StartedServe = $null

# Track the opencode-telegram process that WE start, so we can clean it up on exit.
$script:StartedTelegram = $null

# Track the TUI window that WE start, so we can close it on exit.
$script:StartedTui = $null

try {
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

    # Reuse a serve only when its API reports the same project directory.
    # Sessions are globally persisted, so process age or port alone is unsafe.
    $port = Find-ExistingServePort -Directory $effectiveCwd
    if ($WorkingDir) {
        Write-Host "[i] Using custom working directory: $effectiveCwd" -ForegroundColor Cyan
    }

    if ($port) {
        Write-Host "[OK] Reusing existing opencode serve on port $port" -ForegroundColor Green
    } else {
        $requestedPort = Get-FreeTcpPort
        Write-Host "[..] Starting opencode serve on free port $requestedPort..." -ForegroundColor Yellow
        $serveArgs = @{
            FilePath = $OpencodeExe
            ArgumentList = "serve --port $requestedPort"
            WindowStyle = "Hidden"
            PassThru = $true
        }
        if ($WorkingDir) {
            $serveArgs.WorkingDirectory = $effectiveCwd
        }
        $script:StartedServe = Start-Process @serveArgs

        # Poll for up to ~15s until the server binds a port, bailing out early
        # if the process crashes.
        for ($i = 0; $i -lt 15; $i++) {
            Start-Sleep -Seconds 1
            if ($script:StartedServe.HasExited) {
                Write-Host "[!!] opencode serve exited unexpectedly (code $($script:StartedServe.ExitCode))." -ForegroundColor Red
                $script:StartedServe = $null
                break
            }
            $port = Get-ListenPortForPid -ProcessId $script:StartedServe.Id
            if ($port) { break }
        }

        if ($port) {
            Write-Host "[OK] opencode serve started on port $port (PID $($script:StartedServe.Id))" -ForegroundColor Green
        } else {
            Write-Host "[!!] Failed to start opencode serve. Start it manually:" -ForegroundColor Red
            Write-Host "   $OpencodeExe serve" -ForegroundColor Cyan
            exit 1
        }
    }

    # Verify opencode-telegram is installed.
    $TelegramExe = Join-Path $env:APPDATA "npm\node_modules\@grinev\opencode-telegram-bot\dist\cli.js"
    if (-not (Test-Path $TelegramExe)) {
        Write-Host "[!!] opencode-telegram not found at:" -ForegroundColor Red
        Write-Host "   $TelegramExe" -ForegroundColor Cyan
        Write-Host "   Install it with: npm install -g @grinev/opencode-telegram-bot" -ForegroundColor Cyan
        exit 1
    }

    # opencode-telegram reads its config from ~/.config/opencode-telegram-bot/.env.
    # We override OPENCODE_API_URL to point at the serve we just resolved.
    # This ensures the bot talks to the correct project-scoped serve.
    $serverUrl = "http://127.0.0.1:$port"
    $env:OPENCODE_API_URL = $serverUrl

    # opencode-telegram stores its config and data under:
    #   %APPDATA%\opencode-telegram-bot\  (on Windows)
    # Unlike opencode-lark, it does NOT hash by cwd — it uses a single config
    # directory. The OPENCODE_API_URL override above is what ties it to the
    # correct project. This is fine for the "one project per bot" model.
    $TelegramConfigDir = Join-Path $env:APPDATA "opencode-telegram-bot"
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

    # Check Telegram API connectivity before starting the bot.
    Write-Host "[..] Checking Telegram API connectivity..." -ForegroundColor Yellow
    try {
        $tgTest = Invoke-WebRequest -Uri "https://api.telegram.org" -TimeoutSec 10 -UseBasicParsing
        if ($tgTest.StatusCode -eq 200) {
            Write-Host "[OK] Telegram API reachable" -ForegroundColor Green
        }
    } catch {
        Write-Host "[!!] Cannot reach Telegram API: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "   Configure a proxy in $envFile:" -ForegroundColor Cyan
        Write-Host "   TELEGRAM_PROXY_URL=socks5://127.0.0.1:7890" -ForegroundColor Cyan
        exit 1
    }

    # Start opencode-telegram in foreground (blocking).
    # The bot uses long polling — no inbound port needed.
    # It will stay running until Ctrl+C or the bot exits.
    Write-Host "[..] Starting opencode-telegram -> $serverUrl" -ForegroundColor Green
    Write-Host "[i] Config dir: $TelegramConfigDir" -ForegroundColor DarkGray
    Write-Host "[i] Bot will use long polling (no inbound port required)" -ForegroundColor DarkGray

    # Use node to run the CLI directly, passing the OPENCODE_API_URL env var.
    $nodeExe = (Get-Command node -ErrorAction SilentlyContinue).Source
    if (-not $nodeExe) {
        Write-Host "[!!] node not found in PATH" -ForegroundColor Red
        exit 1
    }

    $telegramProc = Start-Process -FilePath $nodeExe `
        -ArgumentList "`"$TelegramExe`"" `
        -WindowStyle Normal -PassThru `
        -WorkingDirectory $TelegramConfigDir

    $script:StartedTelegram = $telegramProc
    Write-Host "[OK] opencode-telegram started (PID $($telegramProc.Id))" -ForegroundColor Green
    Write-Host ""
    Write-Host "Bot is running. Send a message on Telegram to start chatting." -ForegroundColor Cyan
    Write-Host "Press Ctrl+C to stop." -ForegroundColor DarkGray

    # Wait for the bot process to exit.
    $telegramProc.WaitForExit()

} finally {
    # Cleanup: stop processes that THIS script started.
    # Reused processes (existing serve) are left untouched.

    if ($script:StartedTelegram) {
        Write-Host "[..] Stopping opencode-telegram (PID $($script:StartedTelegram.Id))..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $script:StartedTelegram.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # Process may have already exited.
        }
    }

    if ($script:StartedServe) {
        Write-Host "[..] Stopping opencode serve (PID $($script:StartedServe.Id))..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $script:StartedServe.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # Process may have already exited.
        }
    }

    if ($script:StartedTui) {
        Write-Host "[..] Closing TUI window..." -ForegroundColor Yellow
        try {
            Stop-Process -Id $script:StartedTui.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # Process may have already exited.
        }
    }

    Write-Host "[OK] Cleanup complete." -ForegroundColor Green
}
