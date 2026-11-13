# Package the current Windows build as a small standalone distribution.
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$exe = Join-Path $Root "build\windows\CableCarAdventure.exe"
$pck = Join-Path $Root "build\windows\CableCarAdventure.pck"
if (-not (Test-Path $exe) -or -not (Test-Path $pck)) {
    throw "Windows build is missing. Run tools/export_clean.ps1 first."
}

$stage = Join-Path $Root "build\standalone"
$folder = Join-Path $stage "CableCarAdventure-Windows"
if (Test-Path $folder) { Remove-Item -LiteralPath $folder -Recurse -Force }
New-Item -ItemType Directory -Force -Path $folder | Out-Null
Copy-Item $exe $folder -Force
Copy-Item $pck $folder -Force
Copy-Item (Join-Path $Root "README.md") $folder -Force
Copy-Item (Join-Path $Root "THIRD_PARTY_NOTICES.md") $folder -Force

$zip = Join-Path $stage "CableCarAdventure-Windows.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $folder "*") -DestinationPath $zip -CompressionLevel Optimal
Write-Host "Standalone package: $zip"
