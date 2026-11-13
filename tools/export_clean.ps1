# Clean release export for Windows + Web.
# Godot always embeds GDScript files; staging without tests/tools/docs keeps the PCK clean.
param(
    [string]$Godot = "D:\Tools\GameTools\GODOT\Godot_v4.5.1-stable_win64_console.exe"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root "build\stage"

# 先检查场景引用的纹理/资源是否存在，坏引用直接阻止导出。
# Godot 退出时的 RID 泄漏提示会写入 stderr；这里临时用 Continue，
# 只按进程退出码判断校验结果，避免把日志噪声误判为构建失败。
$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& $Godot --headless --path $root --script tools/validate_scene_resources.gd
$validationExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorAction
if ($validationExitCode -ne 0) { throw "scene resource validation failed: $validationExitCode" }

if (Test-Path $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
New-Item -ItemType Directory -Path $stage | Out-Null

$excludeDirs = @(".godot", ".screenshots", ".git", "tests", "tools", "docs", "analytics", "dashboard", "server", "build")
$copyArgs = @($root, $stage, "/E", "/NFL", "/NDL", "/NJH", "/NJS", "/NP", "/XD") + $excludeDirs
& robocopy @copyArgs | Out-Null
if ($LASTEXITCODE -gt 7) {
    throw "robocopy failed: $LASTEXITCODE"
}

New-Item -ItemType Directory -Force -Path (Join-Path $stage "build\windows") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $stage "build\web") | Out-Null

$ErrorActionPreference = "Continue"
& $Godot --headless --editor --path $stage --quit
$importExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($importExitCode -ne 0) { throw "import failed: $importExitCode" }

$ErrorActionPreference = "Continue"
& $Godot --headless --path $stage --export-release "Windows Desktop" "build/windows/CableCarAdventure.exe"
$windowsExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($windowsExitCode -ne 0) { throw "windows export failed: $windowsExitCode" }

$ErrorActionPreference = "Continue"
& $Godot --headless --path $stage --export-release "Web / WeChat" "build/web/index.html"
$webExitCode = $LASTEXITCODE
$ErrorActionPreference = "Stop"
if ($webExitCode -ne 0) { throw "web export failed: $webExitCode" }

New-Item -ItemType Directory -Force -Path (Join-Path $root "build\windows") | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $root "build\web") | Out-Null
Copy-Item (Join-Path $stage "build\windows\CableCarAdventure.exe") (Join-Path $root "build\windows\CableCarAdventure.exe") -Force
Copy-Item (Join-Path $stage "build\windows\CableCarAdventure.pck") (Join-Path $root "build\windows\CableCarAdventure.pck") -Force
Copy-Item (Join-Path $stage "build\web\*") (Join-Path $root "build\web") -Recurse -Force

Write-Host "Clean export complete."
Write-Host "  build/windows/CableCarAdventure.exe"
Write-Host "  build/web/index.html"
Write-Host "PCK bytes: $((Get-Item (Join-Path $root 'build\windows\CableCarAdventure.pck')).Length)"

if (Test-Path $stage) {
    Remove-Item -LiteralPath $stage -Recurse -Force
}
