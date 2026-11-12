# Framework power LED blink (Windows)

Makes the power-button LED on a Framework Laptop blink while Windows Hello is waiting for your
fingerprint. The fingerprint reader is built into the power button, so the blink tells you
when to touch it.

This is a Windows port of
[alejandroqh/framework-fingerprint-led-blink](https://github.com/alejandroqh/framework-fingerprint-led-blink),
which does the same thing on Linux. It is a fresh implementation in PowerShell and contains no
code from the original, but the idea is theirs.

## Hardware

Tested on a **Framework Laptop 13 (AMD Ryzen 7040 series)** running Windows 11. It sends a
low-level command to the laptop's embedded controller (EC, the chip that runs the LEDs and
fans), and that command may behave differently on other models or firmware versions. Run the
test below before installing. If you try it on another model, please open an issue saying
whether it worked.

## How it decides when to blink

Windows has no public "Hello is waiting" event, so the script blinks while one of these
programs is running:

| Program | Screen |
|---|---|
| `LogonUI.exe` | lock screen, sign-in screen |
| `consent.exe` | UAC admin prompt |
| `CredentialUIBroker.exe` | "Windows Security" credential pop-up (this also shows the UAC prompt when Hello is on) |

The LED blinks 0.25 s on and 0.25 s off, for at most 60 s per prompt. It goes back to normal
(automatic) control when the prompt closes, when the 60 s cap is reached, and whenever the
script starts or stops.

Not covered: the sign-in screen straight after boot (the task starts when you sign in), and
apps that use Hello without opening one of the screens above.

## Requirements

- Windows 10 or 11 on a Framework Laptop
- [framework_tool](https://github.com/FrameworkComputer/framework-system), Framework's own
  command-line tool:

  ```powershell
  winget install FrameworkComputer.framework_tool
  ```

## Test it first

In an **administrator** PowerShell window, from this folder:

```powershell
.\power-led-blink.ps1 -RunForSeconds 90
```

Then lock the screen (Windows key + L). The power LED should blink until you unlock with your
fingerprint. The script stops by itself after 90 seconds.

If PowerShell refuses to run the script, allow it for this window only:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## Install

In an administrator PowerShell window:

```powershell
.\install-task.ps1
```

This copies the script and `framework_tool.exe` to `C:\Program Files\FrameworkPowerLedBlink\`
and creates a scheduled task called `FrameworkPowerLedBlink` that starts it, hidden, when you
sign in.

It runs from Program Files on purpose. The task needs administrator rights to talk to the EC,
and only administrators can change files in Program Files. If it ran from a folder you can
edit, any program running as you could change the script and get administrator rights at your
next sign-in.

The installer checks that the PC is a Framework. Use `.\install-task.ps1 -Force` to skip that
check. Re-run the installer after updating the script so the installed copy is refreshed.

A log of when it started and stopped blinking is kept at
`C:\Program Files\FrameworkPowerLedBlink\power-led-blink.log`.

## Uninstall

In an administrator PowerShell window:

```powershell
.\uninstall-task.ps1
```

This removes the task, puts the LED back to automatic and deletes the Program Files folder.

## LED commands

`framework_tool` has a `--fp-brightness` option, but some EC firmware rejects it when setting a
value, so the script uses the raw EC LED command (`EC_CMD_LED_CONTROL`, 0x29, version 1, power
LED id 1). The brightness bytes are red, green, blue, yellow, white, amber.

```
framework_tool --host-command 0x29 1 1 0 0 0 0 0 100 0   # white on
framework_tool --host-command 0x29 1 1 0 0 0 0 0 0 0     # off
framework_tool --host-command 0x29 1 1 2 0 0 0 0 0 0     # back to automatic
```

Each call takes about 40 ms.

## Licence

Apache License 2.0, the same as the original project. See [LICENSE](LICENSE).
