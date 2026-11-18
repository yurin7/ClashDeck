# 开发与发布

面向维护者。用户向说明见 [README](../README.md)。

## 环境与常用命令

需要 Flutter stable（当前 3.50 / Dart 3.14）。仓库根目录执行：

```powershell
flutter analyze                 # 任何 info 都会失败，CI 的 Analyze 步骤同样
flutter test                    # 单元 / widget 测试，Windows 上直接跑
dart format lib test tool       # 提交前格式化
dart run tool/check_ui_conventions.dart --check   # UI 约定 0 基线检查
flutter build apk --debug       # build\app\outputs\flutter-apk\app-debug.apk
```

只打 64 位包（体积约减 30 MB）：

```powershell
flutter clean   # 换 ABI 组合必须先 clean，否则会留旧 ABI 的 .so
flutter build apk --debug --target-platform android-arm64,android-x64
```

## 内核二进制不在仓库

`android/app/src/main/jniLibs/{arm64-v8a,x86_64}/libmihomo.so` 是预编译 mihomo，两个加起来 118 MB，
超过 GitHub 单文件上限，所以不入库。克隆后能构建，但运行时会提示找不到内核，先补：

```powershell
git clone --depth 1 -b Alpha https://github.com/MetaCubeX/mihomo D:\dev\_downloads\mihomo-src\mihomo-Alpha
.\tool\build_core.ps1        # 复制源码 → 打构建约束补丁 → 交叉编译两个 ABI
```

产物直接写入 `jniLibs/<abi>/libmihomo.so`。armeabi-v7a 没有内核，32 位设备无法启动。

## CI 与发布

- push `main`：自动构建开发版并覆盖 Release「开发版（跟随 main）」，资源名固定 `ClashDeck-dev-<abi>.apk`。
- push `v*` 标签：构建正式版，发到该标签的 Release。

每次构建：runner 上用 `tool/build_core.sh` 现编内核 → `flutter analyze` + `flutter test` → `flutter build apk --release --split-per-abi` → 上传 Release 与 Actions 产物（保留 14 天）。

```powershell
git tag -a v0.2.0 -m "ClashDeck v0.2.0"
git push origin v0.2.0
```

流水线：<https://github.com/yurin7/ClashDeck/actions>

## 签名与覆盖升级

安装包用同一把自签名 key 签名，因此新版本可直接覆盖安装，配置与节点不丢。

只有早期版本（0.1.0–0.1.2 与早期 nightly）是每次构建换一把 debug 签名，证书不同、无法覆盖；
这些用户需要卸载一次（先在 YAML 页备份），重装后导入回来。

验证签名：

```bash
apksigner verify --print-certs ClashDeck-*.apk
# Signer #1 certificate SHA-256 digest: a6db4e7e…c1433be1
```

当前证书指纹（`Show signer` 步骤每次构建也会打印）：

```
A6:DB:4E:7E:E0:28:85:9D:4F:D6:86:3E:61:94:C3:3F:8C:D7:2F:DD:C1:6A:9F:0D:1F:69:B2:16:C1:43:3B:E1
```

### 维护者：签名材料放在哪

key 只放在**本机仓库外目录**和 **CI Actions Secrets**，仓库里不保存。

| 位置 | 放什么 |
| --- | --- |
| 本机（仓库外） | `%USERPROFILE%\.clashdeck\` 的 keystore；`android/key.properties` 指过去（已被 git 忽略） |
| CI | Actions Secrets：`KEYSTORE_BASE64` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` |
| 仓库 | 不保存签名材料（`.gitignore` 已排除 `*.jks`、`*.keystore`、`key.properties`） |

- `tool\setup_signing.ps1` 只在换新 key 时用一次，输出到仓库外；已有可用 key 不要重跑。
- 换 key 等于换 App 身份：要更新 Secrets，且用户需卸载重装一次。

本地打 release（可选）：`flutter build apk --release --split-per-abi` 会读 `android/key.properties`；
手动构建时 `--build-number` 不要小于已安装版本，否则报 `INSTALL_FAILED_VERSION_DOWNGRADE`。

## 目录

```
lib/core/     纯 Dart：yaml / model / edit / schema / parse / validate（无 Flutter 依赖，可单测）
lib/data/     配置与偏好落盘（tmp+rename 原子写）
lib/state/    编辑器状态、设置状态
lib/ui/       概览 / 配置 / 设置三页 + 编辑页（代理·规则·YAML）+ 动态表单
lib/runtime/  mihomo REST 客户端、运行配置生成、子进程控制器、GEOIP/GEOSITE 落盘
android/app/src/main/kotlin/dev/clashdeck/   VpnService、内核进程、MethodChannel 桥
assets/geo/   随包携带的 GEOIP/GEOSITE 数据，首启铺到内核工作目录
tool/         构建内核、UI 约定自检、签名脚本
```

架构与内核启动细节见 [ARCHITECTURE.md](ARCHITECTURE.md)。
