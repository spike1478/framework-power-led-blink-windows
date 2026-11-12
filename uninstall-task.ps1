#requires -RunAsAdministrator
# Removes the scheduled task, hands the power LED back to the EC, and deletes the
# Program Files copy made by install-task.ps1.
$task       = 'FrameworkPowerLedBlink'
$installDir = Join-Path ([Environment]::GetFolderPath('ProgramFiles')) 'FrameworkPowerLedBlink'

Stop-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction SilentlyContinue

$ft = Join-Path $installDir 'framework_tool.exe'
if (-not (Test-Path $ft)) { $ft = (Get-Command framework_tool -ErrorAction SilentlyContinue).Source }
if ($ft) { & $ft --host-command 0x29 1 1 2 0 0 0 0 0 0 | Out-Null }

if (Test-Path $installDir) { Remove-Item $installDir -Recurse -Force }
'Removed. Power LED is back to automatic.'
