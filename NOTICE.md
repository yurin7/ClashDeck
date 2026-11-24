ClashDeck — 一个把 YAML 当数据库的 mihomo 图形前端
Copyright (C) 2026 ClashDeck contributors

本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证第 3 版
（或你选择的任何更高版本）的条款再分发和/或修改它。完整条款见同目录下的
LICENSE 文件（GPL-3.0）。

本程序分发时希望对他人有用，但不提供任何担保，甚至不提供适销性或特定用途
适用性的默示担保。详见 GNU 通用公共许可证。

## 第三方组件

1. **mihomo**（https://github.com/MetaCubeX/mihomo），GPL-3.0。
   随 APK 分发的 `libmihomo.so` 由 mihomo Alpha 源码交叉编译。构建脚本将
   `component/iface/anet` 的 Android 网络接口查询实现用于 Linux 构建目标，
   以适配 Android 对网络接口查询的限制。`system` 与 `mixed` 模式通过仓库中的
   套接字保护入口调用 Android `VpnService.protect()`。
   [Windows 构建脚本](tool/build_core.ps1) · [CI 构建脚本](tool/build_core.sh) · [套接字保护源码](tool/mihomo/clashdeck_protect_linux.go)

   Windows x64 预览随包附带 [mihomo v1.19.34](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.34) 官方兼容版。下载脚本会校验发布包的 SHA-256。

2. **GEOIP / GEOSITE 数据**：`assets/geo/geoip.metadb`、`assets/geo/geosite.dat`
   来自 https://github.com/MetaCubeX/meta-rules-dat （GPL-3.0），随包分发以避免
   首次运行联网下载。

3. Flutter / Dart 生态依赖（`yaml`、`yaml_edit`、`path_provider`、`material_ui` 等）
   各自遵循其原始许可证，见 `pubspec.lock`。

4. Windows 中文界面字体 [资源圆体简体中文版 v0.990](https://github.com/CyanoHao/Resource-Han-Rounded/releases/tag/v0.990)，
   随桌面版分发 Regular 字重，许可证见 [SIL OFL 1.1](windows/resources/fonts/ResourceHanRounded-OFL.md)。
