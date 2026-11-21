# ClashDeck 工作区说明

## 安卓验收

- 每轮完成应用改动后，在 `pubspec.yaml` 递增版本名和构建号，并用原签名构建本轮安装包。签名配置由本机 `android/key.properties` 和 GitHub Actions Secrets 提供。
- 启动或复用一台有可见窗口的 Android 模拟器，等待开机后用 `adb -s <模拟器序列号> install -r <本轮 x86_64 APK>` 覆盖安装并保留数据。
- 启动 `dev.clashdeck/.MainActivity` 并打开本轮修改涉及的页面。完成后保留模拟器窗口，供用户直接验收。

## GitHub 发布

- 每轮应用更新完成后，提交本轮改动并推送到 GitHub 的 `main`。
- 推送与 `pubspec.yaml` 版本名对应的 `v<版本名>` 标签，等待正式 Release 发布并确认 `arm64-v8a` 和 `x86_64` 的 APK 都可下载。

## 构建与检查

- 构建环境以 [.github/workflows/release.yml](.github/workflows/release.yml) 为准。缺少 `libmihomo.so` 时，运行 `tool/build_core.ps1`（Windows）或 `tool/build_core.sh`，为两个架构生成内核。
- 提交前执行 `dart format lib test tool`、`flutter analyze --no-pub`、`dart run tool/check_ui_conventions.dart --check` 和 `flutter test --no-pub`。
