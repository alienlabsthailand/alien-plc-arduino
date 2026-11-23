param(
  [Parameter(Mandatory=$true)] [string]$Version,                        # e.g. 1.0.0
  [string]$Repo = 'alienlabsthailand/alien-plc-arduino'
)
# Builds dist/alien-plc-<ver>.zip and updates package_alienlabs_index.json (Boards Manager).
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$dist = Join-Path $root 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null
$name = "alien-plc-$Version"
$stage = Join-Path $env:TEMP $name
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null

# Archive content = platform folder (boards.txt, platform.txt, variants, tools, libraries, extras, README)
foreach ($item in 'boards.txt','platform.txt','README.md','LICENSE','variants','tools','libraries','extras') {
  $p = Join-Path $root $item
  if (Test-Path $p) { Copy-Item $p -Destination $stage -Recurse }
}
(Get-Content (Join-Path $stage 'platform.txt')) -replace '^version=.*', "version=$Version" |
  Set-Content (Join-Path $stage 'platform.txt') -Encoding ascii

$zip = Join-Path $dist "$name.zip"
if (Test-Path $zip) { Remove-Item $zip }
# bsdtar (Windows 10+) writes '/' separators; PS5 Compress-Archive writes '\' which breaks extraction
& "$env:SystemRoot\System32\tar.exe" -a -c -f $zip -C (Split-Path $stage -Parent) $name
if ($LASTEXITCODE) { throw "tar failed" }
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash.ToLower()
$size = (Get-Item $zip).Length

$index = [ordered]@{
  packages = @([ordered]@{
    name       = 'alienlabs'
    maintainer = 'Alien Labs Thailand'
    websiteURL = "https://github.com/$Repo"
    email      = ''
    help       = [ordered]@{ online = "https://github.com/$Repo" }
    platforms  = @([ordered]@{
      name            = 'Alien Labs Boards'
      architecture    = 'stm32'
      version         = $Version
      category        = 'Contributed'
      help            = [ordered]@{ online = "https://github.com/$Repo" }
      url             = "https://github.com/$Repo/releases/download/v$Version/$name.zip"
      archiveFileName = "$name.zip"
      checksum        = "SHA-256:$hash"
      size            = "$size"
      boards          = @([ordered]@{ name = 'Alien PLC 20MR (12 in / 8 relay)' })
      toolsDependencies = @()
    })
    tools = @()
  })
}
$json = $index | ConvertTo-Json -Depth 10
# UTF-8 without BOM (a BOM can break the Boards Manager JSON parser)
[IO.File]::WriteAllText((Join-Path $root 'package_alienlabs_index.json'), $json, (New-Object Text.UTF8Encoding($false)))
"zip:   $zip ($size bytes)"
"sha256: $hash"
"index: $(Join-Path $root 'package_alienlabs_index.json')"
