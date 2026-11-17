# 一次性生成固定的发布签名，让后续每个 APK 都能覆盖安装升级。
# 用法：在仓库根目录执行  pwsh -File tool\setup_signing.ps1
# 生成的 android/app/clashdeck-release.jks 与 android/key.properties 要一起提交进仓库，
# CI 才会用同一个 key 签名（否则每次都是新 key，装新包前必须先卸载旧包）。

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$keystore = Join-Path $root 'android\app\clashdeck-release.jks'
$propsFile = Join-Path $root 'android\key.properties'

$alias = 'clashdeck'
$storePass = 'clashdeck2026'
$keyPass = 'clashdeck2026'
$dname = 'CN=ClashDeck, OU=dev, O=ClashDeck, L=NA, ST=NA, C=CN'

if (Test-Path $keystore) {
    Write-Host "keystore 已存在，跳过生成：$keystore"
} else {
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
    "storeFile=clashdeck-release.jks"
) -join "`r`n"
[System.IO.File]::WriteAllText($propsFile, $props + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Host "已写入：$propsFile"
Write-Host ''
Write-Host '别忘了把这两个文件提交进仓库：'
Write-Host '  android/app/clashdeck-release.jks'
Write-Host '  android/key.properties'
