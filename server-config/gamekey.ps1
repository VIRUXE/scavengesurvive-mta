# Live checks: real key presses for controls rcon cannot drive (server bindKey on game controls such as
# vehicle_fire). Scancodes: LAlt 0x38, LCtrl 0x1D, F 0x21, Enter 0x1C. Example: pwsh server-config/gamekey.ps1 -Scan 0x38 -GapsMs 0,100
param([int]$Scan = 0x38, [int[]]$GapsMs = @(0), [int]$HoldMs = 80)
# Presses a key (by scancode) in the MTA game window once per entry in GapsMs, waiting that many ms before each press.
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GK {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
$p = Get-Process gta_sa -ErrorAction Stop | Select-Object -First 1
[GK]::ShowWindow($p.MainWindowHandle, 9) | Out-Null
[GK]::SetForegroundWindow($p.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 400
foreach ($g in $GapsMs) {
    Start-Sleep -Milliseconds $g
    [GK]::keybd_event(0, [byte]$Scan, 0x0008, [UIntPtr]::Zero)          # KEYEVENTF_SCANCODE down
    Start-Sleep -Milliseconds $HoldMs
    [GK]::keybd_event(0, [byte]$Scan, 0x0008 -bor 0x0002, [UIntPtr]::Zero) # up
    Write-Output ("pressed 0x{0:X2} at {1:HH:mm:ss.fff}" -f $Scan, (Get-Date))
}
