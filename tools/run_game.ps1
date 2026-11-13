param(
    [string]$Godot = "D:\Tools\GameTools\GODOT\Godot_v4.5.1-stable_win64_console.exe",
    [string]$Project = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $Godot)) {
    throw "Godot executable not found: $Godot"
}
if (-not (Test-Path (Join-Path $Project "project.godot"))) {
    throw "Godot project not found: $Project"
}

Write-Host "Launching CableCarAdventure..." -ForegroundColor Cyan
& $Godot --path $Project --resolution 1280x720
exit $LASTEXITCODE
