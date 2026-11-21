<p align="center"><img src="assets/icon/app_icon.png" width="88" alt="ClashDeck 图标"></p>
<h1 align="center">ClashDeck</h1>
<p align="center">Android 上的 mihomo 客户端。点按切换出口，拖拽编排策略组和分流规则，也可以直接编辑 YAML。</p>
<p align="center">
  <strong><a href="https://github.com/yurin7/ClashDeck/releases/latest">下载正式版 APK</a></strong>
  · <a href="#操作演示">操作演示</a>
  · <a href="CHANGELOG.md">更新记录</a>
</p>

## 界面预览

| 运行概览 | 节点与策略组 | 分流规则 |
| :---: | :---: | :---: |
| <a href="docs/screenshots/overview.webp"><img src="docs/screenshots/overview.webp" width="230" alt="内核运行中的概览页，显示流量、TUN 协议栈和分流模式"></a> | <a href="docs/screenshots/proxies.webp"><img src="docs/screenshots/proxies.webp" width="230" alt="代理页的节点列表、策略组、当前出口和延迟"></a> | <a href="docs/screenshots/rules.webp"><img src="docs/screenshots/rules.webp" width="230" alt="分流规则页的本地规则、在线规则集、GEO 和兜底分区"></a> |
| 启停内核，查看流量与诊断。 | 编辑节点，管理手动选择、自动测速和链式策略组。 | 按分类管理规则，拖动右侧手柄排序。 |

## 安装与上手

1. 在 [最新正式版](https://github.com/yurin7/ClashDeck/releases/latest) 下载 APK。大多数手机选 **arm64-v8a**，x86 模拟器选 **x86_64**。支持 Android 7.0 及以上，APK 已包含 mihomo 和 GEO 数据。
2. 打开「配置 → 导入」，从文件选择 YAML，或粘贴 YAML、节点分享链接及订阅地址。也可以新建配置后手动添加节点。
3. 回到「概览」选择运行配置，点「启动内核」并确认系统 VPN 授权。TUN 支持 `gvisor`、`system` 和 `mixed`，还可按应用分流。使用本地代理端口时选择「仅端口」。
4. 已安装 ClashDeck 后，从「设置 → 检查更新」下载匹配的正式版，再在 Android 安装界面确认。同签名正式版覆盖安装会保留配置。

## 操作演示

以下操作均录自 Android 模拟器。点图片可以查看原尺寸。

| 内核运行时切换出口 | 拖动成员到另一个策略组 |
| :---: | :---: |
| <a href="docs/screenshots/selector.gif"><img src="docs/screenshots/selector.gif" width="260" alt="内核运行时点按 selector 节点，当前出口在香港和东京之间切换"></a> | <a href="docs/screenshots/group-drag.gif"><img src="docs/screenshots/group-drag.gif" width="260" alt="长按东京节点，将它从 DEFAULT 拖到备用线路，目标组边框高亮"></a> |
| 在当前运行配置的手动选择组里点按已有成员，出口立即切换。 | 长按节点拖到目标组。嵌套策略组可以拖入手动选择组。 |
| **调整链式顺序** | **更改规则出口** |
| <a href="docs/screenshots/relay.gif"><img src="docs/screenshots/relay.gif" width="260" alt="拖动东京节点覆盖香港节点，链式节点让位，松手后顺序变为香港、东京、新加坡"></a> | <a href="docs/screenshots/rule-switch.gif"><img src="docs/screenshots/rule-switch.gif" width="260" alt="打开规则的改挂到组面板，将 example.org 的出口切换为备用线路"></a> |
| 拖动链节，观察节点让位和虚线占位，松手后按新顺序连接。 | 点规则行尾的换组按钮，选择策略组或系统策略。 |

改动策略组成员或规则后，保存当前运行配置即可让内核应用新内容。

## 更多界面

| 配置管理 | 从文件导入 | 手动添加节点 |
| :---: | :---: | :---: |
| <a href="docs/screenshots/profiles.webp"><img src="docs/screenshots/profiles.webp" width="230" alt="配置列表显示每份配置的节点、策略组和规则数量"></a> | <a href="docs/screenshots/import.webp"><img src="docs/screenshots/import.webp" width="230" alt="从 Android 文件选择器选中 YAML 后，导入弹窗显示配置名称和原文"></a> | <a href="docs/screenshots/node-form.webp"><img src="docs/screenshots/node-form.webp" width="230" alt="手动添加节点表单，按协议填写地址和传输选项"></a> |
| **YAML 原文** | **Pulse 测速** | **应用内更新** |
| <a href="docs/screenshots/yaml.webp"><img src="docs/screenshots/yaml.webp" width="230" alt="YAML 编辑页保留原配置结构与注释"></a> | <a href="docs/screenshots/pulse.webp"><img src="docs/screenshots/pulse.webp" width="230" alt="从概览向右滑打开 Pulse，显示测速和应用信息"></a> | <a href="docs/screenshots/update.webp"><img src="docs/screenshots/update.webp" width="230" alt="发现新版本弹窗，显示更新内容与下载并安装按钮"></a> |
| **运行设置** | **在线规则集** | **GEO 条目** |
| <a href="docs/screenshots/settings.webp"><img src="docs/screenshots/settings.webp" width="230" alt="设置页的分应用代理、TUN 协议栈、MTU 和分流选项"></a> | <a href="docs/screenshots/online-rules.webp"><img src="docs/screenshots/online-rules.webp" width="230" alt="在线规则集的 Loyalsoldier 预置选择面板"></a> | <a href="docs/screenshots/geo-rules.webp"><img src="docs/screenshots/geo-rules.webp" width="230" alt="按分类批量选择 GEO 条目"></a> |

- **保留配置原文**。界面编辑只修改 YAML 中对应的片段，保留其他位置的注释、键顺序与扩展字段。YAML 页可以查看、复制或替换整份配置。
- **订阅和规则集**。可定时刷新订阅，使用 Loyalsoldier、ACL4SSR 预置或自定义在线规则集。GEOIP 和 GEOSITE 可搜索后批量添加。
- **随手查看与启停**。概览页向右滑打开 Pulse 测速，点 Pulse 上的应用图标或名称可访问项目主页。常驻通知、快捷设置磁贴和桌面小组件提供内核启停入口。

项目使用 [GPL-3.0](LICENSE)。内置内核、数据与其他第三方组件见 [第三方声明](NOTICE.md)。
