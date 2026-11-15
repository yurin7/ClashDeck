# 构建 mihomo 内核（给 Android 用）。
#
# 为什么不直接用 GOOS=android：
#   Go 的 android 目标需要 cgo（要 NDK 里的 clang），而 mihomo 全静态、纯 Go
#   交叉编译更省事。GOOS=linux 编出来的二进制可以直接在 Android 上跑，但会
#   丢掉 mihomo 的 android 专用代码，其中最关键的是
#   component/iface/anet/{interface_android.go,netlink_android.go}——它正是
#   用来绕开 Android 上 "route ip+net: netlinkrib: permission denied" 的
#   （该文件自己的 doc.go 就写着这句话）。不编进去的话，QUIC/UDP 出站会
#   全部失败：
#     [UDP] dial ... error: route ip+net: netlinkrib: permission denied
#   所以这里先把这两个文件的构建约束从 "android" 放宽到 "android || linux"，
#   同时把非 android 的 interface.go 排除掉（否则函数重名），再编译。
#
# 用法：
#   . D:\dev\env.ps1
#   ./tool/build_core.ps1                       # 默认源在 D:\dev\_downloads
#   ./tool/build_core.ps1 -Source <mihomo 源码目录>
#
# 源目录获取（任选）：
#   curl -L -o mihomo.tar.gz https://codeload.github.com/MetaCubeX/mihomo/tar.gz/refs/heads/Alpha
#   tar -xzf mihomo.tar.gz     # 得到 mihomo-Alpha/

param(
  [string]$Source = 'D:\dev\_downloads\mihomo-src\mihomo-Alpha',
  [string]$Work = 'D:\dev\_downloads\mihomo-patched',
  [string]$Out = (Join-Path $PSScriptRoot '..\android\app\src\main\jniLibs'),
  [string[]]$Abis = @('arm64-v8a', 'x86_64'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path (Join-Path $Source 'go.mod'))) {
  throw "找不到 mihomo 源码：$Source（需要包含 go.mod 的源码根目录）"
}

if ($Force -and (Test-Path $Work)) { Remove-Item $Work -Recurse -Force }
if (-not (Test-Path $Work)) { New-Item -ItemType Directory -Path $Work | Out-Null }

$tree = Join-Path $Work 'mihomo-Alpha'
if (-not (Test-Path $tree)) {
  Write-Host "复制源码 -> $tree"
  Copy-Item $Source $tree -Recurse
}

# --- anet 构建约束补丁（幂等） -------------------------------------------------
$anet = Join-Path $tree 'component\iface\anet'
$tag = "//go:build android || linux`n`n"

$pairs = @(
  @{ from = 'interface_android.go'; to = 'interface_anet.go' },
  @{ from = 'netlink_android.go';   to = 'netlink_anet.go' }
)
foreach ($p in $pairs) {
  $from = Join-Path $anet $p.from
  $to = Join-Path $anet $p.to
  if (Test-Path $from) {
    $text = Get-Content $from -Raw
    if (-not $text.StartsWith('//go:build')) { $text = $tag + $text }
    Set-Content -Path $to -Value $text -NoNewline -Encoding utf8
    Remove-Item $from
    Write-Host "已补丁：$($p.from) -> $($p.to)（android || linux）"
  }
}

$ifaceGo = Join-Path $anet 'interface.go'
if (Test-Path $ifaceGo) {
  $text = Get-Content $ifaceGo -Raw
  $patched = $text.Replace('//go:build !android', '//go:build !android && !linux')
  if ($patched -ne $text) {
    Set-Content -Path $ifaceGo -Value $patched -NoNewline -Encoding utf8
    Write-Host '已补丁：interface.go（排除 linux，避免与 anet 实现重名）'
  }
}

# --- 编译 --------------------------------------------------------------------
$env:CGO_ENABLED = '0'
$env:GOOS = 'linux'
if (-not $env:GOPROXY) { $env:GOPROXY = 'https://goproxy.cn,direct' }
if (-not $env:GOSUMDB) { $env:GOSUMDB = 'off' }

$map = @{ 'arm64-v8a' = 'arm64'; 'x86_64' = 'amd64'; 'armeabi-v7a' = 'arm' }

Push-Location $tree
try {
  foreach ($abi in $Abis) {
    if (-not $map.ContainsKey($abi)) { throw "不支持的 ABI：$abi" }
    $arch = $map[$abi]
    $dest = Join-Path $Out "$abi\libmihomo.so"
    New-Item -ItemType Directory -Path (Split-Path $dest) -Force | Out-Null
    Write-Host "编译 $abi (GOARCH=$arch) -> $dest"
    $env:GOARCH = $arch
    & go build -tags with_gvisor -trimpath -ldflags '-s -w' -o $dest .
    if ($LASTEXITCODE -ne 0) { throw "go build 失败：$abi" }
    $size = (Get-Item $dest).Length
    Write-Host ("  完成：{0:N0} 字节" -f $size)
  }
} finally {
  Pop-Location
}

Write-Host '内核构建完成。改动内核后记得 flutter clean 再打包，否则 Gradle 可能复用旧的 .so。'
