# Package the Web export PCK into the WeChat mini-game template.
# Run tools/export_clean.ps1 first to generate build/web/index.pck.
param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"
$pck = Join-Path $Root "build\web\index.pck"
$wechat = Join-Path $Root "build\wechat"
$engine = Join-Path $wechat "engine"
$target = Join-Path $engine "game-pck.bin"
if (-not (Test-Path $pck)) {
    throw "Missing build/web/index.pck. Run tools/export_clean.ps1 first."
}
if (-not (Test-Path $wechat)) {
    throw "Missing build/wechat template."
}
New-Item -ItemType Directory -Force -Path $engine | Out-Null
Copy-Item $pck $target -Force

$gameJs = Join-Path $wechat "game.js"
if (Test-Path $gameJs) {
    $text = [System.IO.File]::ReadAllText($gameJs, [System.Text.Encoding]::UTF8)
    $text = $text -replace 'GameGlobal\.__platformMaxDpr\s*=\s*[0-9.]+', 'GameGlobal.__platformMaxDpr = 1.5'
    # WeChat disallows eval, so the runtime marker is written before the engine starts.
    # PlatformConfig reads window.__cableCarPlatform to distinguish WeChat from itch.io.
    if ($text -notmatch '__cableCarPlatform') {
        $importLine = "import './godot-loader'"
        $marker = $importLine + "`r`n// WeChat runtime marker (written only by this WeChat template)`r`nif (typeof window !== 'undefined') { window.__cableCarPlatform = 'wechat' }"
        if ($text.Contains($importLine)) {
            $text = $text.Replace($importLine, $marker)
        } else {
            throw "Cannot find godot-loader import in build/wechat/game.js"
        }
    }
    [System.IO.File]::WriteAllText($gameJs, $text, (New-Object System.Text.UTF8Encoding($false)))
}

$zip = Join-Path $Root "build\standalone\CableCarAdventure-WeChat.zip"
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $wechat "*") -DestinationPath $zip -CompressionLevel Optimal
$bytes = (Get-Item $zip).Length
Write-Host "WeChat package: $zip"
Write-Host "  pck: $((Get-Item $target).Length) bytes"
Write-Host "  zip: $bytes bytes"
