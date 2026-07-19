# opencode-lark one-click startup script
# Usage: .\start-opencode-remote.ps1 [-WorkingDir <path>]
#
# This script starts opencode serve on a RANDOM free port, auto-detects that
# port, then launches opencode-lark pointed at it. No fixed port required,
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

Write-Host "Starting opencode-lark remote control..." -ForegroundColor Green

# Resolve tool paths from environment variables for portability across users.
$BunBin      = Join-Path $env:USERPROFILE ".bun\bin"
$OpencodeExe = Join-Path $env:APPDATA "npm\node_modules\opencode-ai\bin\opencode.exe"

# Ensure Bun is in PATH (opencode-lark lives here)
if (Test-Path $BunBin) { $env:Path = "$BunBin;" + $env:Path }

# Use the real .exe, NOT the "opencode" shell shim. The extensionless shim is
# not a valid Win32 app and fails under Start-Process.
if (-not (Test-Path $OpencodeExe)) {
    Write-Host "[!!] opencode.exe not found at:" -ForegroundColor Red
    Write-Host "   $OpencodeExe" -ForegroundColor Cyan
    exit 1
}

# Find the listening TCP port owned by a given process id (opencode serve).
function Get-ListenPortForPid {
    param([int]$ProcessId)
    $conn = Get-NetTCPConnection -OwningProcess $ProcessId -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($conn) { return $conn.LocalPort }
    return $null
}

# True only if the process was launched as "opencode serve". This distinguishes
# a real server from a TUI instance even if a TUI ever bound a TCP port.
function Test-IsServeProcess {
    param([int]$ProcessId)
    $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue).CommandLine
    return ($cmd -match '\bserve\b')
}

# Query the opencode serve REST API for the session opencode-lark is bound to.
# opencode-lark names its sessions "Feishu chat <id>", so we filter by that
# title and return the most recently updated one. This is reliable even when
# opencode-lark REUSES an existing session (in which case it prints no
# "Observing session" line and the sessions.db is WAL-locked from outside).
function Get-FeishuSessionId {
    param([int]$Port)
    try {
        $sessions = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/session" `
            -Headers @{ Accept = 'application/json' } -TimeoutSec 3
    } catch {
        return $null
    }
    $feishu = $sessions | Where-Object { $_.title -like 'Feishu chat*' }
    if (-not $feishu) { return $null }
    $newest = $feishu | Sort-Object { $_.time.updated } -Descending | Select-Object -First 1
    return $newest.id
}

# Detect an already-running opencode serve: an opencode.exe launched with
# "serve" that owns a listening port. TUI instances are skipped. When several
# serves are running, prefer the most recently started one (deterministic).
function Find-ExistingServePort {
    $procs = Get-Process -Name opencode -ErrorAction SilentlyContinue |
        Sort-Object StartTime -Descending
    foreach ($proc in $procs) {
        if (-not (Test-IsServeProcess -ProcessId $proc.Id)) { continue }
        $p = Get-ListenPortForPid -ProcessId $proc.Id
        if ($p) { return $p }
    }
    return $null
}

# Track a serve that WE start, so we can clean it up on exit. Stays $null when
# we reuse an existing serve (which we must not kill).
$script:StartedServe = $null

# Track an opencode-lark that WE start, so we can clean it up on exit. Stays
# $null when we reuse an existing opencode-lark (which we must not kill).
$script:StartedLark = $null

# Track the TUI window that WE start, so we can close it on exit.
$script:StartedTui = $null

try {
    # When the user explicitly requests a working directory, we must NOT reuse
    # an existing serve (it may be running in a different cwd, which would
    # silently ignore -WorkingDir). In that case always start a fresh serve.
    if ($WorkingDir) {
        if (-not (Test-Path $WorkingDir)) {
            Write-Host "[!!] Working directory does not exist: $WorkingDir" -ForegroundColor Red
            exit 1
        }
        $port = $null
    } else {
        $port = Find-ExistingServePort
    }

    if ($port) {
        Write-Host "[OK] Reusing existing opencode serve on port $port" -ForegroundColor Green
    } else {
        Write-Host "[..] Starting opencode serve (random port)..." -ForegroundColor Yellow
        $serveArgs = @{
            FilePath = $OpencodeExe
            ArgumentList = "serve"
            WindowStyle = "Hidden"
            PassThru = $true
        }
        if ($WorkingDir) {
            $serveArgs.WorkingDirectory = $WorkingDir
            Write-Host "[i] Using custom working directory: $WorkingDir" -ForegroundColor Cyan
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

    # Start opencode-lark in background, capturing stdout to a log file.
    # Must use the .exe directly — the extensionless shim fails under
    # Start-Process with redirection ("%1 is not a valid Win32 application").
    #
    # Check the exact .exe we will actually run (single source of truth), not
    # a separate Get-Command PATH lookup which could disagree with this path.
    $OpencodeLarkExe = Join-Path $BunBin "opencode-lark.exe"
    if (-not (Test-Path $OpencodeLarkExe)) {
        Write-Host "[!!] opencode-lark.exe not found at:" -ForegroundColor Red
        Write-Host "   $OpencodeLarkExe" -ForegroundColor Cyan
        Write-Host "   Install it with: bun add -g opencode-lark" -ForegroundColor Cyan
        exit 1
    }

    $serverUrl = "http://127.0.0.1:$port"
    $env:OPENCODE_SERVER_URL = $serverUrl

    # opencode-lark stores its data (sessions.db, memory.db) in a "data/"
    # subdirectory of its working directory. Since sessions are scoped by cwd,
    # we MUST isolate data per project — otherwise the same Feishu chat would
    # be mapped to a session from a different project.
    #
    # Strategy: hash the effective working directory and store data under
    # ~/.config/opencode-lark/<hash>/. Same cwd → same hash → same data dir
    # (reuses existing bindings). Different cwd → different hash → isolated.
    #
    # Normalize the path first (Resolve-Path) so that different spellings of the
    # SAME directory — trailing slash, case differences, relative paths — all
    # hash to the same value. Otherwise the session bindings would split.
    $effectiveCwd = if ($WorkingDir) { (Resolve-Path -LiteralPath $WorkingDir).Path } else { (Get-Location).Path }
    $cwdBytes = [Text.Encoding]::UTF8.GetBytes($effectiveCwd.ToLowerInvariant())
    $cwdStream = [IO.MemoryStream]::new($cwdBytes)
    $cwdHash = (Get-FileHash -InputStream $cwdStream -Algorithm SHA256).Hash.Substring(0, 16)
    $cwdStream.Dispose()
    $LarkDataDir = Join-Path $env:USERPROFILE ".config\opencode-lark\$cwdHash"
    if (-not (Test-Path $LarkDataDir)) { New-Item -ItemType Directory -Path $LarkDataDir -Force | Out-Null }
    Write-Host "[i] opencode-lark data dir: $LarkDataDir (cwd=$effectiveCwd)" -ForegroundColor DarkGray

    # opencode-lark binds a single webhook on port 3001, so only ONE instance
    # can run at a time. The listener may show up as "bun" (the runtime) rather
    # than "opencode-lark", so we detect it BY PORT, not by process name.
    #
    # If a bridge is already there (e.g. left over from a prior run, possibly
    # pointing at a stale serve), stop it and start fresh against the serve we
    # just resolved. Restarting is safe: opencode-lark reconnects to the session
    # it previously bound (persisted in data/sessions.db), so no context is lost.
    #
    # SAFETY: only kill the holder if it is bun or opencode-lark. If some other
    # app (e.g. a dev server) happens to use 3001, we warn and exit instead of
    # destroying unrelated work.
    $larkWebhookPort = 3001
    $existing = Get-NetTCPConnection -LocalPort $larkWebhookPort -State Listen -ErrorAction SilentlyContinue
    if ($existing) {
        $holderPid = ($existing | Select-Object -First 1).OwningProcess
        $holderProc = Get-Process -Id $holderPid -ErrorAction SilentlyContinue
        $holderName = $holderProc.ProcessName
        if ($holderName -and ($holderName -eq 'bun' -or $holderName -eq 'opencode-lark')) {
            Write-Host "[..] Port $larkWebhookPort is in use by $holderName (PID $holderPid). Stopping old bridge..." -ForegroundColor Yellow
            Stop-Process -Id $holderPid -Force -ErrorAction SilentlyContinue
            Get-Process -Name opencode-lark -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            for ($i = 0; $i -lt 10; $i++) {
                Start-Sleep -Milliseconds 500
                if (-not (Get-NetTCPConnection -LocalPort $larkWebhookPort -State Listen -ErrorAction SilentlyContinue)) { break }
            }
        } else {
            Write-Host "[!!] Port $larkWebhookPort is held by $holderName (PID $holderPid), which is NOT opencode-lark." -ForegroundColor Red
            Write-Host "   Refusing to kill an unrelated process. Free port $larkWebhookPort and retry." -ForegroundColor Cyan
            exit 1
        }
    }

    Write-Host "[..] Starting opencode-lark -> $serverUrl" -ForegroundColor Green
    $larkLogOut = Join-Path $env:TEMP "opencode-lark-stdout.log"
    $larkLogErr = Join-Path $env:TEMP "opencode-lark-stderr.log"
    Remove-Item $larkLogOut, $larkLogErr -ErrorAction SilentlyContinue
    $larkProc = Start-Process -FilePath $OpencodeLarkExe `
        -WorkingDirectory $LarkDataDir `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $larkLogOut -RedirectStandardError $larkLogErr
    $script:StartedLark = $larkProc

    # Verify opencode-lark actually stayed alive. It exits within a second if
    # startup fails (e.g. port 3001 still busy), so poll briefly before claiming
    # it is running.
    for ($i = 0; $i -lt 4; $i++) {
        Start-Sleep -Seconds 1
        $larkProc.Refresh()
        if ($larkProc.HasExited) { break }
    }
    if ($larkProc.HasExited) {
        Write-Host "[!!] opencode-lark exited immediately (code $($larkProc.ExitCode))." -ForegroundColor Red
        $errTail = Get-Content $larkLogErr -ErrorAction SilentlyContinue -Tail 5
        if ($errTail) {
            Write-Host "   --- stderr ---" -ForegroundColor DarkGray
            $errTail | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
        }
        Write-Host "   Tip: port $larkWebhookPort may still be held by another process." -ForegroundColor Cyan
        $script:StartedLark = $null
        exit 1
    }
    Write-Host "[OK] opencode-lark started (PID $($larkProc.Id))" -ForegroundColor Green

    # Wait for opencode-lark to bind its Feishu session, then read the session
    # id straight from the serve REST API (not from stdout or the WAL-locked db).
    # Also bail out early if opencode-lark crashes during the wait.
    $sessionId = $null
    for ($i = 0; $i -lt 15; $i++) {
        Start-Sleep -Seconds 1
        $sessionId = Get-FeishuSessionId -Port $port
        if ($sessionId) { break }
        $larkProc.Refresh()
        if ($larkProc.HasExited) {
            Write-Host "[!!] opencode-lark crashed while waiting for session." -ForegroundColor Red
            break
        }
    }

    if ($sessionId) {
        Write-Host "[OK] opencode-lark bound to session: $sessionId" -ForegroundColor Green
        Write-Host "[..] Starting TUI attached to same session..." -ForegroundColor Green
        $script:StartedTui = Start-Process -FilePath $OpencodeExe -ArgumentList "attach", "http://127.0.0.1:$port", "--session", $sessionId -WindowStyle Normal -PassThru
    } else {
        Write-Host "[!!] Could not detect session ID. TUI not started automatically." -ForegroundColor Yellow
        Write-Host "   You can manually attach later:" -ForegroundColor Cyan
        Write-Host "   opencode attach http://127.0.0.1:$port --session <session_id>" -ForegroundColor Cyan
    }

    # Keep the script running until opencode-lark exits. Ctrl+C (or closing the
    # window) breaks out of this loop and runs the finally block, which stops
    # whatever THIS script started.
    Write-Host "" 
    Write-Host "[..] Running. opencode-lark PID $($larkProc.Id)." -ForegroundColor Yellow
    Write-Host "    Press Ctrl+C here to stop everything this script started." -ForegroundColor Yellow
    while ($true) {
        $larkProc.Refresh()
        if ($larkProc.HasExited) {
            Write-Host "[!!] opencode-lark has exited." -ForegroundColor Red
            break
        }
        Start-Sleep -Seconds 2
    }
}
finally {
    # Stop ONLY what this script started; leave reused serve/lark untouched.
    # opencode-lark.exe spawns a child "bun" process that actually holds the
    # webhook port, so we kill the whole process tree (/T) to avoid orphaning
    # the child (which would keep port 3001 busy).
    if ($script:StartedLark -and -not $script:StartedLark.HasExited) {
        Write-Host "[..] Stopping opencode-lark started by this script (PID $($script:StartedLark.Id))..." -ForegroundColor Yellow
        taskkill /PID $script:StartedLark.Id /T /F 2>$null | Out-Null
    }
    if ($script:StartedServe -and -not $script:StartedServe.HasExited) {
        Write-Host "[..] Stopping opencode serve started by this script (PID $($script:StartedServe.Id))..." -ForegroundColor Yellow
        taskkill /PID $script:StartedServe.Id /T /F 2>$null | Out-Null
    }
    if ($script:StartedTui -and -not $script:StartedTui.HasExited) {
        Write-Host "[..] Closing TUI window started by this script (PID $($script:StartedTui.Id))..." -ForegroundColor Yellow
        taskkill /PID $script:StartedTui.Id /T /F 2>$null | Out-Null
    }
}
