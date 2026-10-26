<p align="center">
  <img src="PhoenixValleyApp/Assets.xcassets/AppIcon.appiconset/PhoenixValley-AppIcon-1024.png" width="128" height="128" alt="凤凰山谷 App 图标">
</p>

<h1 align="center">凤凰山谷</h1>

<p align="center">
  一款面向 iPad 的路网规划沙盒，用 Apple Pencil 在地形上绘制、审查和整理交通地图。
</p>

<p align="center">
  <a href="README.md">English README</a>
</p>

## 概览

凤凰山谷是一个原生 iPadOS 规划游戏原型，核心体验是在随机生成的山地、水域、谷地和海岸地形上绘制道路，并根据地形与既有路网判断桥梁、隧道、坡度和交叉关系。

当前项目仍是本地原型，尚不是 App Store 正式发布版本。应用目标平台为 iPadOS 17 或更高版本，核心几何、地形和路网规划逻辑以 Swift Package 形式组织，可独立测试。

![IMG_0916](https://pauline.oss-cn-shenzhen.aliyuncs.com/img/IMG_0916.PNG)

## 纯粹设计沙盒

默认新地图是一个没有预建路网的 32 × 24 千米空白世界，用于从零开始设计路网。地形、道路、桥梁、隧道与匝道保存在同一套世界坐标中；缩放、旋转、回正以及重新打开存档都不会改变道路与底图的相对位置。

画布使用 MapKit 的原生相机、缩放旋转手势、指北针和比例尺，并以覆盖层替换现实地图内容，因此生成世界不会出现现成道路。手指和 Apple Pencil 都能操作工具栏；开启“手绘”后可用手指画线，关闭后单指浏览地图，Apple Pencil 仍可绘制。

导出面板提供整张地图或当前视野、四种文件格式、主题选择，以及标题、比例尺、范围/道路数量和来源署名的显示选项。预览卡片使用实际导出渲染器，所见即为最终文件内容。

## 核心体验

- 用 Apple Pencil 或手指绘制高速、主干道、街道和铁路。
- 工具栏按钮、分段控制和滑块均支持手指与 Apple Pencil 操作。
- 支持地面、高架、隧道、桥梁、匝道和显式立交结构。
- 绘路后审查桥梁、隧道、坡度、水域和道路交叉建议，再决定是否应用。
- 支持道路选择、框选、移动、类型修改、撤销、重做和局部擦除。
- 用分组管理多张地图，支持预览、重命名、复制、移动和删除。
- 提供雾岚地形、绢纸规划、石墨线稿、浅湾海岸、深蓝夜色、鼠尾草林野六套主题。
- 可通过预览卡片导出 PNG、PDF、SVG 或 GeoJSON，并选择整张地图或当前视野。

## iPadOS 设计

凤凰山谷采用 Apple 平台原生交互，而不是把桌面界面搬到 iPad 上：

- 使用 `NavigationSplitView` 组织地图库和画布。
- 可拖动的 Pencil 笔盒支持停靠在底部、左侧或右侧。
- 外观、导出、编辑和项目管理使用系统工具栏与 Popover。
- App Shortcuts 支持直接进入画布并选择道路工具，或创建随机地图。
- 项目以本地优先方式保存，App target 中已接入可选 iCloud 文档容器。

## 工程模型

项目不会把笔迹当成简单线条处理。核心模型会维护道路源、拓扑节点与边、有向交通规则、结构转换、桥梁与隧道工程资产，以及施工可行性诊断。地形生成使用可复现的随机种子，便于保存、测试和回放。

Swift Package 中已有针对笔迹处理、拓扑、地形生成、桥隧规划、匝道规划、交通规则、地图导出、图层可见性和旧项目兼容性的测试。

## 仓库结构

```text
PhoenixValleyApp/              原生 iPadOS App target
Sources/PhoenixValleyCore/     道路、地形、拓扑、导出和规划逻辑
Tests/PhoenixValleyCoreTests/  核心单元测试
Docs/                          发布、隐私和 App Store 资料
```

## 环境要求

- 安装完整 Xcode 的 macOS
- iPadOS 17 或更高版本目标设备/模拟器
- Xcode 提供的 Swift 6 工具链
- 在实体 iPad 安装时需要 Apple Developer 签名配置

## 运行

1. 用 Xcode 打开 `PhoenixValley.xcodeproj`。
2. 选择 `PhoenixValley` scheme。
3. 选择 iPad Simulator 或已连接的 iPad。
4. 如需安装到实体设备，在 Signing & Capabilities 中设置 Development Team。
5. 构建并运行。

## 测试

使用匹配的 Xcode Swift 工具链运行核心测试：

```bash
swift test
```

## 状态

凤凰山谷仍在开发中。当前原型已具备可用画布、随机地形、河流与流域系统、拓扑感知道路编辑、桥隧建议、立交编辑、交通规则、项目持久化、地图导出和隐私文档。后续仍需完成实体 iPad 与 Apple Pencil 测试、断层与多陆块地形、Apple Pencil 高级手势、自定义样式、更完善的路网设计工具和正式 App Store 发布流程。
