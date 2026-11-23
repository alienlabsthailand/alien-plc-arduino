param(
  [string]$Port = 'COM1',
  [int]$Baud = 57600,
  [string]$Bin = '',
  [switch]$Unprotect,      # Readout Unprotect (0x92): MASS-ERASES the chip, removes read protection
  [switch]$Erase,          # Extended mass erase (0x44)
  [switch]$Go,             # Jump to 0x08000000 after writing
  [switch]$InfoOnly,
  [switch]$VerifyOnly,     # with -Bin: compare flash to the file without writing
  [switch]$EnterBoot,      # send "!BOOT" (9600 8N1) to a running FX2NBoard program first -> no BOOT0 jumper needed
  [string]$Peek = ''       # hex address: read 16 bytes there and exit (e.g. 1FFFEC00)
)
if ($EnterBoot) {
  cmd /c "mode $Port BAUD=19200 PARITY=N DATA=8 STOP=1" | Out-Null
  cmd /c "mode $Port BAUD=9600 PARITY=N DATA=8 STOP=1" | Out-Null
  Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class EB {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadFile(IntPtr h, byte[] b, int n, out int r, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCommTimeouts(IntPtr h, int[] t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool PurgeComm(IntPtr h, uint f);
}
"@
  $eh = [EB]::CreateFile("\\.\$Port", [uint32]3221225472, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($eh -eq [IntPtr]-1) { throw "open $Port failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error()) (close the web page / PuTTY / Serial Monitor)" }
  [void][EB]::SetCommTimeouts($eh, [int[]](50,0,100,0,0)); [void][EB]::PurgeComm($eh,0xF)
  $kb = [Text.Encoding]::ASCII.GetBytes('!BOOT'); $w = 0; [void][EB]::WriteFile($eh,$kb,$kb.Length,[ref]$w,[IntPtr]::Zero)
  $seen = ''; $end = (Get-Date).AddSeconds(2)
  while ((Get-Date) -lt $end -and $seen -notmatch 'BOOTLOADER') {
    $b = New-Object byte[] 256; $r = 0; [void][EB]::ReadFile($eh,$b,256,[ref]$r,[IntPtr]::Zero)
    if ($r) { $seen += [Text.Encoding]::ASCII.GetString($b,0,$r) }
  }
  [void][EB]::CloseHandle($eh)
  if ($seen -match 'BOOTLOADER') { "board acknowledged !BOOT -> ROM bootloader" }
  else { "no !BOOT acknowledgement (program without FX2NBoard?) - trying bootloader anyway" }
  Start-Sleep -Milliseconds 300
  cmd /c "mode $Port BAUD=19200 PARITY=E DATA=8 STOP=1" | Out-Null
  cmd /c "mode $Port BAUD=$Baud PARITY=E DATA=8 STOP=1" | Out-Null
}
# STM32-compatible UART system bootloader flasher (8E1). Keep BOOT0 jumpered while using it.
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class Fl {
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
  public static extern IntPtr CreateFile(string n, uint a, uint s, IntPtr sa, uint c, uint f, IntPtr t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr h);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool WriteFile(IntPtr h, byte[] b, int n, out int w, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool ReadFile(IntPtr h, byte[] b, int n, out int r, IntPtr o);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool GetCommState(IntPtr h, byte[] dcb);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCommState(IntPtr h, byte[] dcb);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetCommTimeouts(IntPtr h, int[] t);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool PurgeComm(IntPtr h, uint f);
}
"@
$ErrorActionPreference = 'Stop'
function Open-Port {
  $h = [Fl]::CreateFile("\\.\$Port", [uint32]3221225472, 0, [IntPtr]::Zero, 3, 0, [IntPtr]::Zero)
  if ($h -eq [IntPtr]-1) { throw "open $Port failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  $dcb = New-Object byte[] 28; [BitConverter]::GetBytes([int]28).CopyTo($dcb,0); [void][Fl]::GetCommState($h,$dcb)
  [BitConverter]::GetBytes([uint16]2048).CopyTo($dcb,14); [BitConverter]::GetBytes([uint16]512).CopyTo($dcb,16)
  $dcb[18]=8; $dcb[19]=2; $dcb[20]=0
  # CH340 quirk: SetCommState can fail (err 31). Bootloader auto-detects baud, so accept the first rate that sticks.
  # Once the bootloader has auto-detected a baud rate it keeps it until reset, so always use the same $Baud.
  $cur = [BitConverter]::ToInt32($dcb,4); $curBits = $dcb[18]; $curPar = $dcb[19]
  # Clear software flow control / error-char / null-strip / abort flags: XON (0x11) and XOFF (0x13) are data here.
  $flags = [BitConverter]::ToUInt32($dcb,8)
  $clean = ($flags -band (-bnot [uint32]0x4F00)) -bor 0x1
  $flagsDirty = ($clean -ne $flags)
  [BitConverter]::GetBytes([uint32]$clean).CopyTo($dcb,8)
  if ($flagsDirty -or -not ($cur -eq $Baud -and $curBits -eq 8 -and $curPar -eq 2)) {
    $alt = if ($Baud -eq 19200) { 9600 } else { 19200 }
    $dcb[18]=8; $dcb[19]=2
    [BitConverter]::GetBytes([int]$alt).CopyTo($dcb,4); [void][Fl]::SetCommState($h,$dcb)
    [BitConverter]::GetBytes([int]$Baud).CopyTo($dcb,4)
    if (-not [Fl]::SetCommState($h,$dcb)) { throw "SetCommState $Baud 8E1 failed err=$([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
  }
  [void][Fl]::SetCommTimeouts($h, [int[]](50,10,1000,10,500)); [void][Fl]::PurgeComm($h,0xF)
  return $h
}
$script:h = Open-Port
function Tx([byte[]]$b) { $w=0; [void][Fl]::WriteFile($script:h,$b,$b.Length,[ref]$w,[IntPtr]::Zero) }
function Rx([int]$n, [int]$timeoutSec = 3) {
  $out = New-Object System.Collections.Generic.List[byte]; $end = (Get-Date).AddSeconds($timeoutSec)
  while ($out.Count -lt $n -and (Get-Date) -lt $end) {
    $b = New-Object byte[] $n; $r=0; [void][Fl]::ReadFile($script:h,$b,$n - $out.Count,[ref]$r,[IntPtr]::Zero)
    for ($i=0;$i -lt $r;$i++){ $out.Add($b[$i]) }
  }
  return ,$out.ToArray()
}
function Ack([string]$what, [int]$timeoutSec = 3) {
  $a = Rx 1 $timeoutSec
  if ($a.Count -eq 0) { throw "$what : no reply" }
  if ($a[0] -ne 0x79) { throw ("$what : NACK/unexpected 0x{0:X2}" -f $a[0]) }
}
function Cmd([byte]$c, [string]$what) { Tx ([byte[]]($c, ($c -bxor 0xFF))); Ack $what }
function Sync {
  # The FIRST byte after reset must be 0x7F (the bootloader measures the baud rate from it).
  [void][Fl]::PurgeComm($script:h,0xF); Tx ([byte[]](0x7F)); $a = Rx 1 1
  if ($a.Count -gt 0 -and ($a[0] -eq 0x79 -or $a[0] -eq 0x1F)) { return }
  # No answer: maybe already synced by an earlier session and now waiting for a complement byte -> send 0xFF,
  # then probe with GET.
  Tx ([byte[]](0x80)); [void](Rx 1 1)   # completes the 0x7F pair (0x7F ^ 0x80 != 0xFF => NACK expected)
  [void][Fl]::PurgeComm($script:h,0xF); Tx ([byte[]](0x00,0xFF)); $g = Rx 1 1
  if ($g.Count -gt 0 -and $g[0] -eq 0x79) { $n = Rx 1 1; if ($n.Count) { [void](Rx ($n[0] + 2) 1) }; return }
  Start-Sleep -Milliseconds 200; [void][Fl]::PurgeComm($script:h,0xF)
  for ($i=0; $i -lt 3; $i++) {
    [void][Fl]::PurgeComm($script:h,0xF); Tx ([byte[]](0x7F)); $a = Rx 1 1
    if ($a.Count -gt 0 -and ($a[0] -eq 0x79 -or $a[0] -eq 0x1F)) { return }
    Start-Sleep -Milliseconds 300
  }
  throw "bootloader did not answer sync (is BOOT0 jumpered and board power-cycled?)"
}
function AddrBytes([uint32]$a) {
  $b = [byte[]]@( (($a -shr 24) -band 0xFF), (($a -shr 16) -band 0xFF), (($a -shr 8) -band 0xFF), ($a -band 0xFF) )
  $x = 0; foreach ($v in $b) { $x = $x -bxor $v }
  return ,([byte[]]($b + [byte]$x))
}
function ReadMem([uint32]$addr, [int]$n) {
  Cmd 0x11 'READ'; Tx (AddrBytes $addr); Ack 'READ addr'
  Tx ([byte[]](($n-1), (($n-1) -bxor 0xFF))); Ack 'READ len'; return ,(Rx $n)
}

try {
  Sync; "bootloader: sync OK"
  Cmd 0x02 'GET_ID'; $id = Rx 3; [void](Rx 1); "chip id: 0x{0:X2}{1:X2}" -f $id[1], $id[2]
  if ($Peek) {
    $pa = [uint32]([Convert]::ToUInt32($Peek, 16))
    try { $d = ReadMem $pa 16; ("0x{0:X8}: " -f $pa) + (($d | % { '{0:X2}' -f $_ }) -join ' ') }
    catch { "read at 0x$Peek refused: $($_.Exception.Message)" }
    return
  }
  if ($InfoOnly) {
    try { $d = ReadMem ([uint32]0x08000000) 16; "flash readable (not protected). first bytes: " + (($d | % { '{0:X2}' -f $_ }) -join ' ') }
    catch { "flash read refused -> still read-protected ($($_.Exception.Message))" }
    return
  }

  if ($Unprotect) {
    "Readout Unprotect -> chip mass-erases and resets..."
    Cmd 0x92 'READOUT_UNPROTECT'; Ack 'READOUT_UNPROTECT done' 20
    [void][Fl]::CloseHandle($script:h); Start-Sleep -Seconds 2; $script:h = Open-Port; Sync; "re-synced after reset"
  }
  if ($Erase) {
    "mass erase..."
    Cmd 0x44 'EXT_ERASE'; Tx ([byte[]](0xFF,0xFF,0x00)); Ack 'EXT_ERASE done' 30; "erase OK"
  }
  if ($Bin) {
    $data = [IO.File]::ReadAllBytes($Bin); "writing $($data.Length) bytes from $Bin"
    $base = [uint32]0x08000000
    for ($off = 0; $off -lt $data.Length -and -not $VerifyOnly; $off += 256) {
      $chunk = $data[$off..([Math]::Min($off+255, $data.Length-1))]
      while ($chunk.Length % 4) { $chunk += [byte]0xFF }
      Cmd 0x31 'WRITE'; Tx (AddrBytes ($base + $off)); Ack 'WRITE addr'
      $x = [byte]($chunk.Length - 1); foreach ($v in $chunk) { $x = $x -bxor $v }
      Tx ([byte[]](([byte]($chunk.Length-1))) + $chunk + [byte[]]($x)); Ack ("WRITE data @0x{0:X8}" -f ($base+$off)) 5
    }
    "write done; verifying..."
    for ($off = 0; $off -lt $data.Length; $off += 256) {
      $n = [Math]::Min(256, $data.Length - $off); $back = ReadMem ($base + $off) $n
      for ($i=0;$i -lt $n;$i++){ if ($back[$i] -ne $data[$off+$i]) {
        $s = [Math]::Max(0, $i-4); $e = [Math]::Min($n-1, $i+8)
        "got $($back.Count)/$n bytes. expected: " + (($data[($off+$s)..($off+$e)] | % { '{0:X2}' -f $_ }) -join ' ')
        "                    actual:   " + (($back[$s..$e] | % { '{0:X2}' -f $_ }) -join ' ')
        throw ("VERIFY mismatch at 0x{0:X8}" -f ($base+$off+$i)) } }
    }
    "verify OK"
  }
  if ($Go) { Cmd 0x21 'GO'; Tx (AddrBytes 0x08000000); Ack 'GO addr'; "jumped to 0x08000000 (program running)" }
} finally { [void][Fl]::CloseHandle($script:h) }
