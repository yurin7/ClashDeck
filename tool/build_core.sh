#!/usr/bin/env bash
# 构建 mihomo 内核（给 Android 用），Linux/macOS 版；Windows 用 tool/build_core.ps1。
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
#   ./tool/build_core.sh                     # 下载 mihomo Alpha 源码后构建
#   MIHOMO_SRC=/path/to/mihomo-alpha ./tool/build_core.sh   # 用本地源码
#   OUT=/tmp/jni ./tool/build_core.sh        # 自定义输出目录
#
# 环境变量：
#   MIHOMO_REF  默认 Alpha
#   MIHOMO_SRC  本地 mihomo 源码目录（可选；给了就不再下载）
#   WORK        工作目录，默认 build/mihomo-patched
#   OUT         输出目录，默认 android/app/src/main/jniLibs
#   ABIS        默认 "arm64-v8a x86_64"（armeabi-v7a 需要 GOARM=7，默认不打）

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MIHOMO_REF="${MIHOMO_REF:-Alpha}"
WORK="${WORK:-build/mihomo-patched}"
OUT="${OUT:-android/app/src/main/jniLibs}"
ABIS="${ABIS:-arm64-v8a x86_64}"

echo "==> 准备源码（$MIHOMO_REF）"
rm -rf "$WORK"
mkdir -p "$WORK"

if [[ -n "${MIHOMO_SRC:-}" && -f "${MIHOMO_SRC}/go.mod" ]]; then
  echo "    使用本地源码：$MIHOMO_SRC"
  cp -a "$MIHOMO_SRC/." "$WORK/"
else
  archive="$WORK/mihomo.tar.gz"
  curl -fsSL -o "$archive" \
    "https://codeload.github.com/MetaCubeX/mihomo/tar.gz/refs/heads/${MIHOMO_REF}"
  tar -xzf "$archive" -C "$WORK" --strip-components=1
  rm -f "$archive"
fi

echo "==> 打 anet 构建约束补丁（幂等）"
anet="$WORK/component/iface/anet"

patch_tag() {
  local from="$1" to="$2"
  [[ -f "$anet/$from" ]] || return 0
  if head -c 20 "$anet/$from" | grep -q '^//go:build'; then
    mv "$anet/$from" "$anet/$to"
  else
    { echo '//go:build android || linux'; echo; cat "$anet/$from"; } > "$anet/$to"
    rm -f "$anet/$from"
  fi
  echo "    已补丁：$from -> $to（android || linux）"
}

patch_tag interface_android.go interface_anet.go
patch_tag netlink_android.go netlink_anet.go

if [[ -f "$anet/interface.go" ]] && grep -q '^//go:build !android$' "$anet/interface.go"; then
  sed -i 's|^//go:build !android$|//go:build !android \&\& !linux|' "$anet/interface.go"
  echo "    已补丁：interface.go（排除 linux，避免与 anet 实现重名）"
fi

echo "==> 编译内核"
cp "$ROOT/tool/mihomo/clashdeck_protect_linux.go" "$WORK/"
export CGO_ENABLED=0
export GOOS=linux
export GOPROXY="${GOPROXY:-https://proxy.golang.org,direct}"
export GOSUMDB="${GOSUMDB:-off}"

cd "$WORK"
for abi in $ABIS; do
  case "$abi" in
    arm64-v8a) arch=arm64 ;;
    x86_64) arch=amd64 ;;
    armeabi-v7a) arch=arm ;;
    *) echo "不支持的 ABI：$abi" >&2; exit 1 ;;
  esac
  case "$OUT" in
    /*) dest="$OUT/$abi/libmihomo.so" ;;
    *) dest="$ROOT/$OUT/$abi/libmihomo.so" ;;
  esac
  mkdir -p "$(dirname "$dest")"
  echo "    $abi (GOARCH=$arch) -> $dest"
  GOARCH="$arch" go build -tags with_gvisor -trimpath -ldflags '-s -w' -o "$dest" .
done

cd "$ROOT"
echo "==> 完成"
ls -lh "$OUT"/*/libmihomo.so 2>/dev/null || ls -lh "$ROOT/$OUT"/*/libmihomo.so 2>/dev/null || true
echo "改动内核后记得 flutter clean 再打包，否则 Gradle 可能复用旧的 .so。"
