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

$logPath = Join-Path $Project "tests\last_run.log"
Write-Host "Running headless test suite..." -ForegroundColor Cyan
& $Godot --headless --path $Project res://tests/test_runner.tscn 2>&1 | Tee-Object -FilePath $logPath
$exitCode = $LASTEXITCODE
if ($exitCode -eq 0) {
    Write-Host "Tests passed." -ForegroundColor Green
} else {
    Write-Host "Tests failed. See $logPath" -ForegroundColor Red
}
exit $exitCode
