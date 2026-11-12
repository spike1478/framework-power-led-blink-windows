#requires -RunAsAdministrator
# Framework Laptop (Windows): blink the power-button LED while Windows Hello is likely
# waiting for a fingerprint. Windows publishes no "Hello is waiting" event, so this watches
# for the screens that use it:
#   LogonUI.exe            lock screen / sign-in screen
#   consent.exe            UAC admin prompt
#   CredentialUIBroker.exe "Windows Security" credential pop-up (also hosts Hello on UAC)
# Windows port of https://github.com/alejandroqh/framework-fingerprint-led-blink (Apache-2.0).
# This is a reimplementation in PowerShell; no code from the original is included.
#
# LED control uses the raw EC LED command (EC_CMD_LED_CONTROL 0x29, version 1, power LED
# id 1, white channel) through framework_tool, because `--fp-brightness <n>` is rejected
# by some EC firmware.
#
# Safety: blinking stops after $MaxBlinkSeconds per prompt, and the LED is always handed
# back to the EC (automatic) when a prompt closes, at the cap, at start-up and on exit.
#
# Test without installing (elevated):  .\power-led-blink.ps1 -RunForSeconds 90

param(
    [int]$RunForSeconds = 0,
    [string]$FrameworkTool = ''
)

$OnMs            = 250
$OffMs           = 250
$PollMs          = 250        # how often to check for prompts while not blinking
$MaxBlinkSeconds = 60
$Watch           = @('LogonUI', 'consent', 'CredentialUIBroker')

# framework_tool: explicit path, else a copy next to this script (installed layout),
# else whatever is on PATH (e.g. winget install, for test runs).
# The installed copy never falls back to PATH: PATH includes folders the user can write to,
# and this runs as administrator.
$installDir = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'FrameworkPowerLedBlink'
$installed  = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ieq $installDir
if (-not $FrameworkTool) {
    $local = Join-Path $PSScriptRoot 'framework_tool.exe'
    if (Test-Path $local) { $FrameworkTool = $local }
    elseif (-not $installed) {
        $cmd = Get-Command framework_tool -ErrorAction SilentlyContinue
        if ($cmd) { $FrameworkTool = $cmd.Source }
    }
}
if (-not $FrameworkTool -or -not (Test-Path $FrameworkTool)) {
    throw 'framework_tool.exe not found. Install it with: winget install FrameworkComputer.framework_tool'
}
$FT  = $FrameworkTool
$Log = Join-Path $PSScriptRoot 'power-led-blink.log'

function Write-Log([string]$msg) {
    try {
        if ((Test-Path $Log) -and (Get-Item $Log).Length -gt 256KB) {
            Move-Item $Log "$Log.old" -Force
        }
        ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) | Add-Content $Log
    } catch { }
}

# brightness array order: red, green, blue, yellow, white, amber
function Set-Led([string]$mode) {
    switch ($mode) {
        'on'   { $a = '0','0','0','0','0','100','0' }
        'off'  { $a = '0','0','0','0','0','0','0' }
        'auto' { $a = '2','0','0','0','0','0','0' }
    }
    $out = & $FT --host-command 0x29 1 1 @a 2>&1 | Out-String
    if ($out -match 'ERROR') { Write-Log "LED $mode failed: $($out.Trim())" }
}

function Get-Prompt {
    foreach ($n in $Watch) {
        $p = [Diagnostics.Process]::GetProcessesByName($n)
        if ($p.Count -gt 0) { foreach ($x in $p) { $x.Dispose() }; return $n }
    }
    return $null
}

$active   = $null      # name of the prompt we are reacting to, or $null
$capped   = $false     # hit the time cap for this prompt; wait for it to close
$ledOn    = $false
$started  = $null
$deadline = if ($RunForSeconds -gt 0) { (Get-Date).AddSeconds($RunForSeconds) } else { $null }

Write-Log "start (pid $PID, framework_tool $FT)"
Set-Led 'auto'
try {
    while ($null -eq $deadline -or (Get-Date) -lt $deadline) {
        $prompt = Get-Prompt

        if ($prompt -and -not $active) {
            $active = $prompt; $capped = $false; $started = Get-Date
            Write-Log "blink: $prompt"
        }
        elseif (-not $prompt -and $active) {
            Set-Led 'auto'; $ledOn = $false
            Write-Log "stop: $active closed after $([int]((Get-Date) - $started).TotalSeconds)s"
            $active = $null; $capped = $false
        }

        if ($active -and -not $capped) {
            if (((Get-Date) - $started).TotalSeconds -ge $MaxBlinkSeconds) {
                Set-Led 'auto'; $ledOn = $false; $capped = $true
                Write-Log "cap: $active still open after ${MaxBlinkSeconds}s, LED back to auto"
                continue
            }
            $sw = [Diagnostics.Stopwatch]::StartNew()
            if ($ledOn) { Set-Led 'off' } else { Set-Led 'on' }
            $ledOn = -not $ledOn
            $wait = $(if ($ledOn) { $OnMs } else { $OffMs }) - $sw.ElapsedMilliseconds
            if ($wait -gt 0) { Start-Sleep -Milliseconds $wait }
        }
        else {
            Start-Sleep -Milliseconds $PollMs
        }
    }
}
finally {
    Set-Led 'auto'
    Write-Log "exit, LED back to auto"
}
