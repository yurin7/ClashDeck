# 一次性生成固定的发布签名，让后续每个 APK 都能覆盖安装升级。
# 用法：在仓库根目录执行  pwsh -File tool\setup_signing.ps1
#
# 【绝不提交】keystore 与 key.properties 都只放在仓库外的用户目录
# （默认 $env:USERPROFILE\.clashdeck\），本仓库是公开的，任何 jks / key.properties
# 出现在仓库里都等于把发布私钥公开。CI 不从仓库读 key，而是从
# GitHub Actions Secrets（KEYSTORE_BASE64 / KEYSTORE_PASSWORD / KEY_ALIAS /
# KEY_PASSWORD）还原同一把 key。
# 已经有一把生产 key 时不要重跑本脚本，改用 key.properties 指向那把 key。

[CmdletBinding()]
param(
    # 已经有生产 key 时不要加这个参数：脚本默认只补 key.properties，不覆盖已有 keystore。
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $env:USERPROFILE '.clashdeck'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$keystore = Join-Path $outDir 'clashdeck-release.jks'
$propsFile = Join-Path $root 'android\key.properties'

$alias = 'clashdeck'
$storePass = 'clashdeck2026'
$keyPass = 'clashdeck2026'
$dname = 'CN=ClashDeck, OU=dev, O=ClashDeck, L=NA, ST=NA, C=CN'

if ((Test-Path $keystore) -and -not $Force) {
    Write-Host "keystore 已存在，保留原 key（要重新生成请加 -Force，但那会让已发布的包无法覆盖升级）：$keystore"
} else {
    if (Test-Path $keystore) { Write-Host "按 -Force 覆盖已有 keystore：$keystore" }
    $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source
    if (-not $keytool) {
        foreach ($cand in @(
                'C:\Program Files\Java\jdk-18.0.2.1\bin\keytool.exe',
                'C:\Program Files\Android\jdk\jdk-8.0.302.8-hotspot\bin\keytool.exe',
                'C:\Program Files\Java\jdk1.8.0_101\bin\keytool.exe')) {
            if (Test-Path $cand) { $keytool = $cand; break }
        }
    }
    if (-not $keytool) { throw '找不到 keytool，请装一个 JDK，或手动用 Android Studio 生成密钥库。' }

    & $keytool -genkeypair -v -keystore $keystore -alias $alias `
        -keyalg RSA -keysize 2048 -validity 10000 `
        -storepass $storePass -keypass $keyPass -dname $dname
    if ($LASTEXITCODE -ne 0) { throw "keytool 生成失败（exit $LASTEXITCODE）" }
    Write-Host "已生成：$keystore"
}

$props = @(
    "storePassword=$storePass",
    "keyPassword=$keyPass",
    "keyAlias=$alias",
    "storeFile=$($keystore -replace '\\','/')"
) -join "`r`n"
# key.properties 已在 .gitignore 里，只用于本地 release 构建。
[System.IO.File]::WriteAllText($propsFile, $props + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写入：$propsFile（本文件不进仓库）"

$secretsFile = Join-Path $outDir 'signing-secrets.txt'
$b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($keystore))
@(
    'KEYSTORE_BASE64 (一整行，别换行)='
    $b64
    ''
    "KEYSTORE_PASSWORD=$storePass"
    "KEY_ALIAS=$alias"
    "KEY_PASSWORD=$keyPass"
) -join "`r`n" | Set-Content -Path $secretsFile -Encoding ascii
Write-Host ''
Write-Host '本地构建现在就会用这把 key 签名，可以直接覆盖安装旧版本。'
Write-Host "base64 已写到仓库外：$secretsFile"
Write-Host '把它贴进仓库的 Secrets（Settings → Secrets and variables → Actions）：'
Write-Host '  KEYSTORE_BASE64    = 上面文件里的 base64 一整行'
Write-Host '  KEYSTORE_PASSWORD  = 见文件'
Write-Host '  KEY_ALIAS          = 见文件'
Write-Host '  KEY_PASSWORD       = 见文件'
Write-Host ''
Write-Host '记住：keystore 与 key.properties 都不要提交，也不要贴到 issue/聊天里。'