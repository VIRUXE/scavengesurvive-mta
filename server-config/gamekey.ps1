# Live checks: real key presses for controls rcon cannot drive (server bindKey on game controls such as
# vehicle_fire, the walk key that shows the tweak cursor). Scancodes: LAlt 0x38, LCtrl 0x1D, F 0x21, Enter 0x1C.
# Example: pwsh server-config/gamekey.ps1 -Scan 0x38 -GapsMs 0,100
param([int]$Scan = 0x38, [int[]]$GapsMs = @(0), [int]$HoldMs = 80)
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class GK {
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, IntPtr pid);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
    [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
}
"@
$p = Get-Process gta_sa -ErrorAction Stop | Select-Object -First 1
$h = $p.MainWindowHandle
if ([GK]::GetForegroundWindow() -ne $h) {
    # Windows only lets the foreground thread hand focus over: borrow its input queue for the switch
    $fg = [GK]::GetWindowThreadProcessId([GK]::GetForegroundWindow(), [IntPtr]::Zero)
    $me = [GK]::GetCurrentThreadId()
    [GK]::AttachThreadInput($me, $fg, $true) | Out-Null
    [GK]::ShowWindow($h, 9) | Out-Null
    [GK]::BringWindowToTop($h) | Out-Null
    [GK]::SetForegroundWindow($h) | Out-Null
    [GK]::AttachThreadInput($me, $fg, $false) | Out-Null
    Start-Sleep -Milliseconds 500
}
if ([GK]::GetForegroundWindow() -ne $h) { throw "the game window did not take the focus" }
foreach ($g in $GapsMs) {
    Start-Sleep -Milliseconds $g
    [GK]::keybd_event(0, [byte]$Scan, 0x0008, [UIntPtr]::Zero)          # KEYEVENTF_SCANCODE, down
    Start-Sleep -Milliseconds $HoldMs
    [GK]::keybd_event(0, [byte]$Scan, 0x0008 -bor 0x0002, [UIntPtr]::Zero) # up
    Write-Output ("pressed 0x{0:X2} at {1:HH:mm:ss.fff}" -f $Scan, (Get-Date))
}
