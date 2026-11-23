param(
  [Parameter(Mandatory=$true)] [string]$Port,
  [Parameter(Mandatory=$true)] [string]$Bin
)
# Alien PLC upload tool (called by Arduino IDE / arduino-cli).
# 1. If the board is already in the ROM bootloader (BOOT0 jumper), use it directly.
# 2. Otherwise send "!BOOT" at common baud rates; the Alien PLC core resets into the bootloader.
# 3. Flash, verify and start the program with stm32_uart_flash.ps1.
$ErrorActionPreference = 'Stop'
$Port = ($Port -replace '^\\\\\.\\', '').Trim()
$flash = Join-Path $PSScriptRoot 'stm32_uart_flash.ps1'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class AU {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadFile(IntPtr h, byte[] b, int n, out int r, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCommTimeouts(IntPtr h, int[] t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool PurgeComm(IntPtr h, uint f);
}
"@

function Set-PortMode([int]$baud, [string]$parity) {
  # CH340 quirk: re-applying the same baud can fail, so step through another rate first.
  $alt = if ($baud -eq 19200) { 38400 } else { 19200 }
  cmd /c "mode $Port BAUD=$alt PARITY=$parity DATA=8 STOP=1" | Out-Null
  cmd /c "mode $Port BAUD=$baud PARITY=$parity DATA=8 STOP=1" | Out-Null
}
function Open-Raw {
  $h = [AU]::CreateFile("\\.\$Port", [uint32]3221225472, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($h -eq [IntPtr]-1) {
    throw "Cannot open $Port (error $([Runtime.InteropServices.Marshal]::GetLastWin32Error())). Close Serial Monitor / web page / PuTTY and try again."
  }
  [void][AU]::SetCommTimeouts($h, [int[]](50,0,300,0,0)); [void][AU]::PurgeComm($h,0xF)
  return $h
}
function Write-Raw($h, [byte[]]$b) { $w = 0; [void][AU]::WriteFile($h,$b,$b.Length,[ref]$w,[IntPtr]::Zero) }
function Read-Raw($h) { $b = New-Object byte[] 64; $r = 0; [void][AU]::ReadFile($h,$b,64,[ref]$r,[IntPtr]::Zero); if ($r) { return ,$b[0..($r-1)] } else { return ,@() } }

function Test-Bootloader {
  Set-PortMode 9600 'E'
  $h = Open-Raw
  try {
    Write-Raw $h ([byte[]](0x7F)); $a = Read-Raw $h
    if ($a.Count -gt 0 -and ($a[0] -eq 0x79 -or $a[0] -eq 0x1F)) { return $true }
    return $false
  } finally { [void][AU]::CloseHandle($h) }
}

Write-Host "Alien PLC upload on $Port"
$inBoot = Test-Bootloader
if ($inBoot) {
  Write-Host "Board is in bootloader mode."
} else {
  foreach ($baud in 9600, 115200, 57600, 38400, 19200) {
    Write-Host "Sending !BOOT at $baud baud..."
    Set-PortMode $baud 'N'
    $h = Open-Raw
    Write-Raw $h ([Text.Encoding]::ASCII.GetBytes('!BOOT'))
    Start-Sleep -Milliseconds 100
    [void][AU]::CloseHandle($h)
    Start-Sleep -Milliseconds 400
    if (Test-Bootloader) { $inBoot = $true; Write-Host "Board entered the bootloader."; break }
  }
}
if (-not $inBoot) {
  throw "Board did not enter the bootloader. Check the cable/port, or put the BOOT0 jumper on, power-cycle and upload again."
}

& $flash -Port $Port -Baud 9600 -Erase -Bin $Bin -Go
if (-not $?) { throw "flash failed" }
Write-Host "Done. Program is running."
