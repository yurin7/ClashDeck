ClashDeck — 一个把 YAML 当数据库的 mihomo 图形前端
Copyright (C) 2026 ClashDeck contributors

本程序是自由软件：你可以依据自由软件基金会发布的 GNU 通用公共许可证第 3 版
（或你选择的任何更高版本）的条款再分发和/或修改它。完整条款见同目录下的
LICENSE 文件（GPL-3.0）。

本程序分发时希望对他人有用，但不提供任何担保，甚至不提供适销性或特定用途
适用性的默示担保。详见 GNU 通用公共许可证。

## 第三方组件

1. **mihomo**（https://github.com/MetaCubeX/mihomo），GPL-3.0。
   本仓库 `android/app/src/main/jniLibs/{arm64-v8a,x86_64}/libmihomo.so`
   是由 mihomo 源码（Alpha 分支，v1.19.34 时期）构建的静态二进制，构建方式见
   `tool/build_core.ps1`。相对上游有**一处构建约束补丁**：
   `component/iface/anet/{interface_android.go,netlink_android.go}` 的文件名
   从 `*_android.go` 改为 `*_anet.go` 并把构建约束改成 `android || linux`，
   `interface.go` 改成 `!android && !linux`。补丁只改编译期可见性，不改行为；
   目的见 `docs/ARCHITECTURE.md` §5.2。按 GPL-3.0 要求，本仓库同时提供该补丁的
   生成脚本与文档说明。

2. **GEOIP / GEOSITE 数据**：`assets/geo/geoip.metadb`、`assets/geo/geosite.dat`
   来自 https://github.com/MetaCubeX/meta-rules-dat （GPL-3.0），随包分发以避免
   首次运行联网下载。

3. Flutter / Dart 生态依赖（`yaml`、`yaml_edit`、`path_provider`、`material_ui` 等）
   各自遵循其原始许可证，见 `pubspec.lock`。
