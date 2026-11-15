# Desktop side of plan B, Windows flavour. Same job as prepare_assets.sh.
#
#   $env:HORIZON_REPO = "C:\src\horizon"
#   .\scripts\prepare_assets.ps1 -ServerJar "$HOME\Downloads\server.jar"
#
# Needs: Rust 1.90+, Python 3.11+, JDK 25, and the Horizon checkout.
[CmdletBinding()]
param(
    [string]$ServerJar = "$HOME\Downloads\server.jar",
    [string]$Out = ""
)

$ErrorActionPreference = "Stop"

if (-not $env:HORIZON_REPO) { throw "请先设置 `$env:HORIZON_REPO 指向 horizon 仓库根目录" }
$repo = $env:HORIZON_REPO
if (-not $Out) { $Out = Join-Path $repo "dist\horizon-assets.zip" }

if (-not (Test-Path $ServerJar)) { throw "找不到 server.jar：$ServerJar" }
if (-not (Get-Command java -ErrorAction SilentlyContinue)) { throw "缺 JDK 25（horizon-prepare 用它读 jar）" }
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) { throw "缺 cargo（https://win.rustup.rs/x86_64）" }

Push-Location $repo
try {
    Write-Host "`n==> horizon-prepare：抽 assets + data" -ForegroundColor Green
    cargo run --release -p horizon-prepare -- --prepare --server-jar $ServerJar
    if ($LASTEXITCODE -ne 0) { throw "horizon-prepare 失败（$LASTEXITCODE）" }

    Write-Host "`n==> horizon-prepare sounds：抽音频" -ForegroundColor Green
    cargo run --release -p horizon-prepare sounds
    if ($LASTEXITCODE -ne 0) { throw "sounds 失败（$LASTEXITCODE）" }

    Write-Host "`n==> 写清单" -ForegroundColor Green
    $null = New-Item -ItemType Directory -Force -Path (Split-Path $Out)
    $hash = (Get-FileHash $ServerJar -Algorithm SHA256).Hash.ToLower()
    @(
        "format = 1"
        "producer = horizon-ios/prepare_assets.ps1"
        "date = $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "server_jar = $(Split-Path $ServerJar -Leaf)"
        "server_jar_sha256 = $hash"
        "host = $([System.Environment]::OSVersion.VersionString)"
    ) | Set-Content -Encoding utf8 (Join-Path $repo ".local\MANIFEST.txt")

    Write-Host "`n==> 打包" -ForegroundColor Green
    if (Test-Path $Out) { Remove-Item $Out }
    $staging = Join-Path $repo ".local"
    Compress-Archive -Path "$staging\assets", "$staging\data", "$staging\MANIFEST.txt" `
                     -DestinationPath $Out -CompressionLevel Optimal
    $size = "{0:N1} MB" -f ((Get-Item $Out).Length / 1MB)
    Write-Host "    $size  $Out"
}
finally {
    Pop-Location
}

Write-Host @"

下一步（三选一）：
  * 数据线：iTunes/Finder 不适用于 Windows 侧 ipa 安装后... 用 iMazing 打开 App 文件共享，拖进 horizon-assets.zip
  * 传到 iCloud Drive「文件」App，手机上长按 → 共享 → Horizon
  * 越狱设备：scp 到 App 沙盒 Documents

然后打开 Horizon → 导入 zip → 开始游戏。
"@
