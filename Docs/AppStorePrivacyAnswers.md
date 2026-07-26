# App Store 隐私披露依据

审计日期：2026 年 7 月 25 日

## 当前建议答案

在 App Store Connect 的“App 隐私”中选择：

> 不，我们不会从此 App 收集数据。

这里的“收集”按 Apple 的口径指将数据传出设备，并使开发者或第三方能够在完成实时请求所需的时间之外访问数据。当前代码没有网络请求、开发者服务器、第三方 SDK、账号、广告、分析或崩溃上报。

## 已核对的行为

- 项目资料以 JSON 保存在应用的 Application Support 容器。
- 地图导出由用户主动发起，并通过系统文件面板保存到用户选择的位置。
- App Intents 只向应用传递操作类型和道路类型。
- 没有定位、相机、相册、麦克风、通讯录、健康、蓝牙或跟踪权限声明。
- Swift 依赖仅有工作区内的 `PhoenixValleyCore` 源码包，没有第三方二进制 SDK。
- 当前源码没有 `URLSession`、Network、CloudKit、`UserDefaults`、文件时间戳、系统启动时间或磁盘空间查询。

## Privacy Manifest

`PhoenixValleyApp/PrivacyInfo.xcprivacy` 声明：

- 不跟踪；
- 不收集数据；
- 不连接跟踪域名；
- 当前没有需申明的 required-reason API。

新增 API 或 SDK 后必须重新审计，不能只沿用这份结论。尤其需要复查：

- iCloud、CloudKit、真实地图或在线搜索；
- 分析、崩溃上报、广告、登录和推送 SDK；
- `UserDefaults`；
- 文件时间戳、可用磁盘空间、系统启动时间和活跃键盘信息；
- 任何把地图、导出文件或诊断信息传出设备的功能。

## 发布前仍需人工填写

- 隐私政策公开 HTTPS URL；
- 可公开的支持邮箱或支持网页；
- App Store Connect 中的隐私答案；
- 如果发布版本的代码与本次审计不同，重新执行数据流和依赖审计。
