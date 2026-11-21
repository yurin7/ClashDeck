# ClashDeck 工作区说明

## 安卓验收

- 每轮完成应用改动后，自动构建本轮安装包。按 [开发与发布](docs/DEVELOPMENT.md) 使用原签名，并在 `pubspec.yaml` 递增版本名和构建号，便于覆盖安装和区分验收包。
- 启动或复用一台有可见窗口的 Android 模拟器，等待开机后用 `adb -s <模拟器序列号> install -r <本轮 x86_64 APK>` 覆盖安装并保留数据。
- 启动 `dev.clashdeck/.MainActivity` 并打开本轮修改涉及的页面。完成后保留模拟器窗口，供用户直接验收。

## GitHub 发布

- 每轮应用更新完成后，提交本轮改动并推送到 GitHub 的 `main`。
- 推送与 `pubspec.yaml` 版本名对应的 `v<版本名>` 标签，等待正式 Release 发布并确认 `arm64-v8a` 和 `x86_64` 的 APK 都可下载。
