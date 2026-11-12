#requires -RunAsAdministrator
# Installs the power-LED blink watcher.
#
# The watcher runs as administrator, so it must not run from a folder an ordinary user can
# edit (anything able to change the script would get admin rights at the next sign-in).
# This copies the script and framework_tool.exe into Program Files, which only
# administrators can write to, and registers a scheduled task that runs that copy at logon.
#
# Usage (elevated):  .\install-task.ps1          # re-run after updating to refresh the copy
#                    .\install-task.ps1 -Force   # skip the "is this a Framework laptop" check

param([switch]$Force)

$ErrorActionPreference = 'Stop'
$task       = 'FrameworkPowerLedBlink'
$installDir = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'FrameworkPowerLedBlink'
$user       = "$env:USERDOMAIN\$env:USERNAME"

$maker = (Get-CimInstance Win32_ComputerSystem).Manufacturer
if ($maker -notmatch 'Framework' -and -not $Force) {
    throw "This PC reports manufacturer '$maker', not Framework. Re-run with -Force to install anyway."
}

$cmd = Get-Command framework_tool -ErrorAction SilentlyContinue
if (-not $cmd) {
    throw 'framework_tool.exe not found on PATH. Install it with: winget install FrameworkComputer.framework_tool'
}
$ftSource = $cmd.Source
$item = Get-Item $ftSource
if ($item.LinkType -and $item.Target) { $ftSource = @($item.Target)[0] }   # winget links to the real exe

# framework_tool lives in a folder the user can write to, and the copy will run as
# administrator from now on, so only accept it if Framework's code signature is intact.
$sig = Get-AuthenticodeSignature $ftSource
if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Framework Computer Inc') {
    throw "framework_tool.exe at $ftSource is not validly signed by Framework Computer Inc (status: $($sig.Status)). Reinstall it with winget and try again."
}

# Stop a running copy so the files can be replaced.
Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'power-led-blink.ps1') $installDir -Force
Copy-Item $ftSource (Join-Path $installDir 'framework_tool.exe') -Force

$script    = Join-Path $installDir 'power-led-blink.ps1'
$action    = New-ScheduledTaskAction -Execute 'powershell.exe' `
             -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User $user
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
             -RestartCount 5 -RestartInterval (New-TimeSpan -Minutes 1) `
             -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -StartWhenAvailable

Register-ScheduledTask -TaskName $task `
    -Description 'Blinks the Framework power-button LED while Windows Hello is likely waiting for a fingerprint (lock screen, UAC, credential pop-ups).' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $task

"Installed to $installDir"
Get-ScheduledTask -TaskName $task | Select-Object TaskName, State
