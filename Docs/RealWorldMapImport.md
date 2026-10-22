# 真实地图导入

## 目的与边界

将一个小范围的现实地理区域转换为可编辑的游戏道路，并保留简化地物与来源。可读 OSM XML、Google Earth 导出的 KML 路径/多边形，以及用户明确确认 WGS84 经纬度、米制高程的 ESRI ASCII 栅格。没有 DEM 的文件不生成随机地形。KMZ、卫星影像、GeoTIFF、投影坐标 ASC 和在线 Google Earth 内容不在本次范围内。

## 两种方案

1. 先把所有路径转换成 RoadSegment，再调用现有 RoadNetwork.rebuilding。接口短，但几何相交会创造源文件不存在的路口，且大区域的两两相交分析成本高。
2. 在导入边界保留源节点身份，在共享节点处分段后直接构造 RoadNetwork；地物、来源和真实高程放入可选 RealWorldMap。选用此方案。它保留道路源拓扑，避免额外网络重建，旧图只需按缺省 nil 解码。

## 调用

```swift
let bounds = try GeoBounds.around(latitude: 25, longitude: 121,
                                 widthMeters: 1600, heightMeters: 1200)
let result = try GeoMapImporter.importMap(data: data, format: .osmXML,
    options: .init(name: "我的真实地图", bounds: bounds, simplificationMeters: 8))
// result.project 是可保存的新地图；result.summary 是预览统计及具体限制。
```

ASC 需要 `.init(demCoordinateSystem: .wgs84)`。确认必须来自用户对文件坐标系和海拔单位的认知，不能根据数值像经纬度就猜测。

## 投影、裁剪和简化

在区域中心纬度进行局部等距平面近似，南北向每度取 111195 米，东西向再乘中心纬度余弦。按同一米/画布点比例映射到 1600 × 1200，居中留边，不拉伸；道路和地物裁剪到所选区域。用于不跨日期变更线、南北纬 80° 内的小范围游戏地图，不用于测绘。

道路共享节点作为不可删除的锚点。每对锚点之间先裁剪原折线，再用确定性 Douglas–Peucker 简化；多边形使用矩形裁剪及双半环简化。最多处理 8 MB、40000 个输入节点、160000 个节点引用、10000 条源路径；产物最多 1200 段道路、2000 个地物和 12000 个点。简化比较次数也受限；超限保留原几何，随后由输出预算拒绝，绝不默默丢弃道路。区域上限宽 16 千米、高 12 千米，与 MapScale 的 10 米/点上限一致。

OSM 道路按 highway/railway 映射到现有道路种类，保留 oneway（含 -1）、bridge 和 tunnel；同层共享源节点相连；跨层共享源节点作为桥/隧道接入端，使用显式 structureTransition 连接。KML 不提供 OSM 路口语义，独立路径保持独立。封闭 water/forest/park/building 面是地物。OSM multipolygon、转向限制和非支持标签不参与模拟，摘要有提示。KML 多边形内环不受支持，带孔面整体省略以免将湖中岛等孔洞填满；远程链接、样式、影像和外部 XML 实体不会加载。

## 高程与持久化

ASC 支持 xllcorner/yllcorner 或 xllcenter/yllcenter，按北行在前读入，NODATA 保留为空。最多一百万源格，统一按画布坐标最近邻采样为 129 × 97，保存真实海拔米值和有效范围。留边或裁剪外缺值保持空。KML 的坐标第三项受 altitudeMode 解释，不等于地面 DEM，故不转为地形高程。

RoadProject 格式升为 11，新增可选 realWorldMap。版本 10 及更旧项目仍可读取；新项目保留 bbox、格式、授权说明、简化统计、地物与真实高程。OSM 导入标注 © OpenStreetMap contributors、ODbL 1.0 和版权链接。导出必须继续携带归属。

既有道路工程计算使用约定的程序地形高度标度，尚未标定到现实 DEM。真实 DEM 当前服务底图显示，不能据此声称现实道路坡度/工程审查准确。后续编辑若调用通用几何重建，可能按本游戏的绘路规则重新建立相交连接；本次保证源文件初次导入与保存重载的拓扑，不声称完整模拟 OSM 交通规则。

## 验证

GeoMapImportTests 验证源共享节点保留、无共享交叉不虚构连接、方向/铁路/桥梁、bbox 裁剪且等比、缺节点/无效 XML/实体/输入与输出预算拒绝、KML 坐标顺序和非 DEM 语义、带孔面省略、真实高程/北向/缺值/显式 CRS、旧版本解码及新项目保存重载。

## 依据

- [OpenStreetMap API v0.6](https://wiki.openstreetmap.org/wiki/API_v0.6)：区域 map bbox、nodes、ways、relations 数据模型。
- [KML Reference](https://developers.google.com/kml/documentation/kmlreference)：coordinates 经纬度顺序、LineString、Polygon、altitudeMode。
- [ESRI ASCII raster format](https://desktop.arcgis.com/en/arcmap/latest/manage-data/raster-and-images/esri-ascii-raster-format.htm)：角点/中心、NODATA 和首行位于栅格顶部。

## 最终验证记录

- 完整 Core 测试 157 项通过，覆盖导入、裁剪、简化、共享节点与跨层接入、缺失数据和格式上限。
- `scripts/test-import-store.sh` 直接编译真实 Store 与持久化代码；保存失败保留旧图及历史、新图重载、无道路地图比例锁定和禁止随机地形替换全部通过。
- iPad Pro 13-inch (M5)、iPadOS 26.5 原生 UI 测试两项通过，覆盖无效经纬度与取消，以及真实 OSM 下载、预览、保存、可见署名和终止重启。运行共享 `PhoenixValleyImport` scheme。
- 台北默认 800 × 600 米样本为 232 段道路、299 个地物，5221 个输入点简化为 2903 个点。`RealWorldMap-Taipei.png` 由最终 PNG 导出器生成并检查，画布采用同一底图渲染。© OpenStreetMap contributors，ODbL 1.0。
- PNG 像素、SVG 图层与来源、GeoJSON 地理坐标往返和图层隐藏均有回归测试。KML 与 ASC 的解析及重载由 Core 测试覆盖，尚未在实体 iPad 上走完文件选择流程。模拟器测试截图存在窗口/朝向裁剪问题，不作为像素一致性依据。

查看记录见 `RealWorldMapDecisions.tsv`。本 PR 不依赖画布旋转 PR；两者都从 master 分出，原工作区的批量拆除改动未包含。

两个分支的合并树已检查为无冲突，并在临时源码副本中通过 iPad Simulator 构建与启动。此检查没有合并远程 PR；各功能的交互测试仍以上述各自分支测试为准。
