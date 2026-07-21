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

# Read the exact session opencode-lark starts observing after a Feishu message,
# then verify via the serve API that it belongs to the requested project.
function Get-FeishuSessionId {
    param(
        [int]$Port,
        [string]$Directory,
        [string]$LogPath
    )
    if (-not (Test-Path -LiteralPath $LogPath)) { return $null }

    $sessionId = $null
    $lines = @(Get-Content -LiteralPath $LogPath -Tail 200 -ErrorAction SilentlyContinue)
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -match 'Observing session (ses_[A-Za-z0-9]+) for chat ') {
            $sessionId = $Matches[1]
            break
        }
    }
    if (-not $sessionId) { return $null }

    try {
        $session = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/session/$sessionId" `
            -Headers @{ Accept = 'application/json' } -TimeoutSec 3
    } catch {
        return $null
    }
    $targetDirectory = [IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    if (-not $session.directory) { return $null }
    $sessionDirectory = [IO.Path]::GetFullPath([string]$session.directory).TrimEnd('\', '/')
    if (-not $sessionDirectory.Equals($targetDirectory, [StringComparison]::OrdinalIgnoreCase)) {
        Write-Host "[!!] Feishu session $sessionId belongs to another directory: $sessionDirectory" -ForegroundColor Red
        return $null
    }
    return $sessionId
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

# Track an opencode-lark that WE start, so we can clean it up on exit. Stays
# $null when we reuse an existing opencode-lark (which we must not kill).
$script:StartedLark = $null

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
    $cwdBytes = [Text.Encoding]::UTF8.GetBytes($effectiveCwd.ToLowerInvariant())
    $cwdStream = [IO.MemoryStream]::new($cwdBytes)
    $cwdHash = (Get-FileHash -InputStream $cwdStream -Algorithm SHA256).Hash.Substring(0, 16)
    $cwdStream.Dispose()
    $LarkDataDir = Join-Path $env:USERPROFILE ".config\opencode-lark\$cwdHash"
    if (-not (Test-Path $LarkDataDir)) { New-Item -ItemType Directory -Path $LarkDataDir -Force | Out-Null }
    $env:OPENCODE_CWD = $effectiveCwd
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
        $holderInfo = Get-CimInstance Win32_Process -Filter "ProcessId=$holderPid" -ErrorAction SilentlyContinue
        $holderCommandLine = [string]$holderInfo.CommandLine
        $isLarkBridge = $holderName -eq 'opencode-lark' -or
            ($holderName -eq 'bun' -and $holderCommandLine -match 'opencode-lark')
        if ($isLarkBridge) {
            Write-Host "[..] Port $larkWebhookPort is in use by $holderName (PID $holderPid). Stopping old bridge..." -ForegroundColor Yellow
            $bridgeRootPid = if ($holderName -eq 'bun') { $holderInfo.ParentProcessId } else { $holderPid }
            taskkill /PID $bridgeRootPid /T /F 2>$null | Out-Null
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

    # opencode-lark creates a session lazily when the first Feishu message
    # arrives. Keep checking while the bridge runs and attach the TUI once.
    Write-Host "" 
    Write-Host "[..] Running. opencode-lark PID $($larkProc.Id)." -ForegroundColor Yellow
    Write-Host "    Waiting for the first Feishu session before starting TUI." -ForegroundColor Yellow
    Write-Host "    Press Ctrl+C here to stop everything this script started." -ForegroundColor Yellow
    while ($true) {
        $larkProc.Refresh()
        if ($larkProc.HasExited) {
            Write-Host "[!!] opencode-lark has exited." -ForegroundColor Red
            break
        }
        if (-not $script:StartedTui) {
            $sessionId = Get-FeishuSessionId -Port $port -Directory $effectiveCwd -LogPath $larkLogOut
            if ($sessionId) {
                Write-Host "[OK] Found project Feishu session: $sessionId" -ForegroundColor Green
                Write-Host "[..] Starting TUI attached to same session..." -ForegroundColor Green
                $script:StartedTui = Start-Process -FilePath $OpencodeExe -ArgumentList "attach", $serverUrl, "--session", $sessionId -WorkingDirectory $effectiveCwd -WindowStyle Normal -PassThru
            }
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
