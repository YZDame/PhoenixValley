# 凤凰山谷项目约定

## iOS 开发方式

- 这是一个 iPad 优先的 Swift/SwiftUI 项目。开始设计、实现、重构或调试 iOS 功能前，先检查并使用本机可用的 iOS 开发插件、XcodeBuildMCP 及其系列 skills。
- 根据任务选择对应的现成 skill；涉及 SwiftUI 时，优先采用 SwiftUI UI patterns、view refactor、performance audit、Liquid Glass 等适用 skill 中的规范和组件模式。构建、运行、测试和模拟器检查优先交给 XcodeBuildMCP。
- 实现 UI 前，依次检查：项目已有组件与样式、SwiftUI 原生控件和容器、Apple 平台标准交互、已安装 skills 提供的成熟模式。能组合或扩展现有实现时，不另造一套近似组件。
- 只有在现有组件、原生 API 和可用套件都无法满足明确需求时，才新增自定义组件；新增前说明缺口、适用范围和维护成本。
- 不凭印象猜测 SwiftUI API、平台行为或设计规范。优先从本机工具、已安装 skills、当前 SDK 和项目代码中核实。
- 功能完成后按风险进行验证：至少构建并运行相关测试；涉及界面或交互时，在目标 iPad 模拟器中检查实际状态、布局和操作链路。静态阅读不能代替运行验证。
