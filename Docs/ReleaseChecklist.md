# 凤凰山谷发布检查清单

## 1. 冻结发布范围

- [ ] 确定版本号和构建号。
- [ ] 确认 `TODO.md` 中标注为本版本范围的功能已经完成。
- [ ] 检查 `git status`，区分发布改动、测试产物和用户本地文件。
- [ ] 锁定依赖版本，重新审计新增 SDK 的隐私清单和签名。

## 2. 隐私与合规

- [ ] 对照 `Docs/AppStorePrivacyAnswers.md` 重新检查实际发布代码的数据流。
- [ ] 校验归档中的 `PrivacyInfo.xcprivacy` 和 Xcode Privacy Report。
- [ ] 将 `Docs/PrivacyPolicy.zh-Hans.md` 部署到公开 HTTPS 地址。
- [ ] 由账号持有人填写公开支持联系方式。
- [ ] 在 App Store Connect 填写并发布 App 隐私答案。
- [ ] 回答出口合规问题；若以后加入自有加密功能，重新评估。
- [ ] 完成年龄分级、内容权利和各销售地区要求。

## 3. 产品资料

- [x] AppIcon 已接入并通过模拟器主屏与 Dock 检查。
- [ ] 准备 iPad 截图和可选 App Preview。
- [ ] 填写名称、副标题、描述、关键词、支持 URL、隐私政策 URL和审核备注。
- [ ] 说明 Apple Pencil 是推荐输入方式，并提供无需 Pencil 的可审核操作路径。

## 4. 工程验证

- [ ] 在最终提交补丁上运行完整 SwiftPM 测试。
- [x] 在 iPad Simulator 的 Release 配置构建并消除警告。
- [ ] 在支持的最低 iPadOS 版本和当前最新版各检查一次。
- [ ] 在实体 iPad 上完成 Apple Pencil 绘制、缩放、擦除、撤销、导出和重启恢复。
- [ ] 验证旧项目迁移、损坏文件提示和未来格式拒绝。
- [ ] 验证 PNG、PDF、SVG、GeoJSON 的文件类型、坐标、比例尺和视觉结果。
- [ ] 检查 VoiceOver 名称、动态字体、横屏尺寸与触控目标。
- [ ] 用 Instruments 检查大型地图的启动、内存和长时间绘制。

## 5. 归档与分发

- [ ] 配置正式 Apple Developer Team、App ID 和分发签名。
- [ ] 将 Bundle ID 与 App Store Connect 记录核对为 `com.leyudame.PhoenixValley`，或在建档前确定最终标识。
- [ ] 使用 Generic iOS Device / Any iOS Device 生成 Release Archive；当前工程尚未配置 `DEVELOPMENT_TEAM`，且本次 XcodeBuildMCP 会话未开放 device/archive 工作流。
- [ ] 在 Organizer 中运行 Validate App。
- [ ] 导出并审查归档的隐私报告、entitlements、Info.plist 和符号文件。
- [ ] 先上传 TestFlight，完成内部测试和至少一轮外部或独立验收。
- [ ] 修复 TestFlight 反馈后递增构建号，重新归档、验证并提交审核。

## 6. 发布后

- [ ] 保存已提交的源码提交、归档版本、构建号和 App Store 元数据快照。
- [ ] 记录审核沟通和已知限制。
- [ ] 监控崩溃与用户反馈；若未来接入诊断服务，先更新隐私说明和披露。
- [ ] 准备可回滚的修复版本，不覆盖已发布标签。
