$ErrorActionPreference = 'Stop'
$version = 'v1.19.34'
$asset = "mihomo-windows-amd64-compatible-$version.zip"
$sha256 = 'cd6738d4648cc1a5f48049a1343b697ab510889d648f045c5c780fc1ab443a79'
$output = Join-Path $PSScriptRoot '../build/mihomo-windows'
[void][IO.Directory]::CreateDirectory($output)
$zip = Join-Path $output $asset

if (!(Test-Path -LiteralPath $zip) -or (Get-FileHash -LiteralPath $zip).Hash -ne $sha256) {
  $cacheKey = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $api = "https://api.github.com/repos/MetaCubeX/mihomo/releases/assets/734504968?asset_cache=$cacheKey"
  & curl.exe -fsSL --max-time 90 -H 'Accept: application/octet-stream' -o $zip $api
  if ($LASTEXITCODE -ne 0 -or (Get-FileHash -LiteralPath $zip).Hash -ne $sha256) {
    & curl.exe -fsSL --max-time 90 -o $zip "https://github.com/MetaCubeX/mihomo/releases/download/$version/$asset"
    if ($LASTEXITCODE -ne 0) { throw '下载 Windows mihomo 失败' }
  }
}
if ((Get-FileHash -LiteralPath $zip).Hash -ne $sha256) {
  throw 'Windows mihomo 压缩包校验失败'
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
  $cores = @($archive.Entries | Where-Object Name -Like 'mihomo*.exe')
  if ($cores.Count -ne 1) { throw '压缩包里没有唯一的 mihomo 可执行文件' }
  $destination = Join-Path $output 'mihomo.exe'
  [IO.Compression.ZipFileExtensions]::ExtractToFile($cores[0], $destination, $true)
  Get-Item -LiteralPath $destination
} finally {
  $archive.Dispose()
}
