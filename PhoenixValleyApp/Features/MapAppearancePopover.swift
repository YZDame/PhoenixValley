import Foundation
import PhoenixValleyCore
import SwiftUI

struct MapAppearanceButton: View {
    @Binding var isPresented: Bool
    let conflictCount: Int
    let engineeringIssueCount: Int
    let constructionIssueCount: Int

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "map.fill")
                .overlay(alignment: .topTrailing) {
                    if conflictCount > 0
                        || engineeringIssueCount > 0
                        || constructionIssueCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .accessibilityLabel("地图外观")
        .accessibilityValue(
            accessibilitySummary
        )
        .accessibilityIdentifier("map-appearance-button")
    }

    private var accessibilitySummary: String {
        let conflicts = conflictCount == 0
            ? "没有层级冲突"
            : "\(conflictCount) 处层级冲突"
        let engineering = engineeringIssueCount == 0
            ? "没有工程约束问题"
            : "\(engineeringIssueCount) 项工程约束问题"
        let construction = constructionIssueCount == 0
            ? "没有施工可行性问题"
            : "\(constructionIssueCount) 项施工可行性问题"
        return "\(conflicts)，\(engineering)，\(construction)"
    }
}

struct MapAppearancePopover: View {
    @Bindable var document: RoadDocumentStore
    @Binding var enablesAdvancedEngineeringAnalysis: Bool
    @Binding var showsConstructionIssueOverlay: Bool

    var body: some View {
        let constructionIssues = document.constructionIssues
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("地图外观")
                    .font(.headline)

                ThemePicker(selection: Binding(get: { document.project.theme }, set: { document.setTheme($0) }))

                Divider()

                VStack(spacing: 14) {
                    Toggle("地形", systemImage: "mountain.2", isOn: terrainSelection)
                    Toggle("水系", systemImage: "water.waves", isOn: hydrologySelection)
                        .disabled(!terrainSelection.wrappedValue)
                        .accessibilityIdentifier("hydrology-layer-toggle")
                    Toggle("流域边界", systemImage: "point.3.connected.trianglepath.dotted", isOn: watershedSelection)
                        .disabled(!terrainSelection.wrappedValue)
                        .accessibilityIdentifier("watershed-layer-toggle")
                    Toggle("等高线", systemImage: "lines.measurement.horizontal", isOn: contoursSelection)
                    Toggle("规划网格", systemImage: "grid", isOn: gridSelection)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "进阶工程分析",
                        systemImage: "ruler",
                        isOn: $enablesAdvancedEngineeringAnalysis
                    )
                    .accessibilityIdentifier("advanced-engineering-analysis-toggle")

                    Text("开启后，新绘道路会分析桥梁、隧道、坡度和施工区段；自由绘制默认不受这些建议打断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("地图范围") {
                        Picker("地图范围", selection: mapScaleSelection) {
                            ForEach(MapScalePreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(document.project.realWorldMap != nil || !document.project.roads.isEmpty)
                        .accessibilityIdentifier("map-scale-picker")
                    }

                    Text(
                        document.project.realWorldMap != nil
                            ? "真实地图保留原始地理比例。"
                            : document.project.roads.isEmpty
                            ? "绘路前选择；规划网格每格 \(gridCellDistanceDescription)。"
                            : "已有道路后锁定比例；规划网格每格 \(gridCellDistanceDescription)。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("道路图层")
                        .font(.subheadline.weight(.semibold))

                    ForEach(RoadKind.allCases) { kind in
                        Toggle(
                            kind.displayName,
                            systemImage: kind.layerSymbol,
                            isOn: roadLayerSelection(for: kind)
                        )
                    }
                }
                .font(.subheadline)

                if !document.layerConflicts.isEmpty {
                    Divider()

                    Label(
                        "\(document.layerConflicts.count) 处道路层级冲突",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("road-layer-conflict-summary")
                }

                if !document.project.engineeringStructures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("工程构件")
                            .font(.subheadline.weight(.semibold))
                        Label(
                            "\(bridgeCount) 座桥梁 · \(bridgePierCount) 座桥墩",
                            systemImage: "water.waves"
                        )
                        Label(
                            "\(tunnelCount) 条隧道 · \(tunnelPortalCount) 个洞口",
                            systemImage: "mountain.2"
                        )
                        if !document.engineeringIssues.isEmpty {
                            Label(
                                "\(document.engineeringIssues.count) 项工程约束问题",
                                systemImage: "exclamationmark.octagon.fill"
                            )
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("road-engineering-issue-summary")
                        }
                    }
                    .font(.caption)
                }

                if enablesAdvancedEngineeringAnalysis
                    && !document.project.roads.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("施工可行性")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle(
                                "显示红色标注",
                                isOn: $showsConstructionIssueOverlay
                            )
                            .labelsHidden()
                            .accessibilityLabel("显示施工问题标注")
                            .accessibilityIdentifier(
                                "construction-issue-overlay-toggle"
                            )
                        }
                        if constructionIssues.isEmpty {
                            Label(
                                "当前地面道路与高架未发现超限区间",
                                systemImage: "checkmark.circle"
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            Label(
                                "\(constructionIssues.count) 个区间需要处理",
                                systemImage: "exclamationmark.octagon.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(
                                "road-construction-issue-summary"
                            )

                            ForEach(constructionIssues.prefix(2)) { issue in
                                Text(issue.displayDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if constructionIssues.count > 2 {
                                Text("另有 \(constructionIssues.count - 2) 个区间")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("红色虚线只标出当前结构下的超限区间；隐藏标注不会改变施工判定。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider()

                Menu {
                    Button("空白地图 · 32 × 24 千米", systemImage: "play.fill") {
                        document.createNewMap()
                    }
                    Divider()
                    ForEach(TerrainScenario.allCases) { scenario in
                        Button(scenario.displayName, systemImage: scenario.symbol) {
                            document.createNewMap(scenario: scenario)
                        }
                    }
                } label: {
                    Label("创建场景地图", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .disabled(document.terrainGenerationState.isGenerating)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("create-random-map-button")
            }
            .padding(20)
        }
        .scrollIndicators(.visible)
        .frame(width: 390)
        .frame(maxHeight: 620)
    }

    private var terrainSelection: Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.showsTerrain },
            set: { document.setShowsTerrain($0) }
        )
    }

    private var contoursSelection: Binding<Bool> {
        Binding(
            get: { document.project.showsContours },
            set: { document.setShowsContours($0) }
        )
    }

    private var hydrologySelection: Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.showsHydrology },
            set: { document.setShowsHydrology($0) }
        )
    }

    private var watershedSelection: Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.showsWatersheds },
            set: { document.setShowsWatersheds($0) }
        )
    }

    private var gridSelection: Binding<Bool> {
        Binding(
            get: { document.project.showsGrid },
            set: { document.setShowsGrid($0) }
        )
    }

    private func roadLayerSelection(for kind: RoadKind) -> Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.isVisible(kind) },
            set: { document.setRoadKind(kind, isVisible: $0) }
        )
    }

    private var mapScaleSelection: Binding<MapScalePreset> {
        Binding(
            get: {
                MapScalePreset.allCases.min {
                    abs($0.rawValue - document.project.mapScale.metersPerPoint)
                        < abs($1.rawValue - document.project.mapScale.metersPerPoint)
                } ?? .standard
            },
            set: {
                document.setMapScale(
                    MapScale(metersPerPoint: $0.rawValue)
                )
            }
        )
    }

    private var gridCellDistanceDescription: String {
        MapScalePreset.distanceDescription(
            document.project.mapScale.meters(forCanvasDistance: 80)
        )
    }

    private var bridgeCount: Int {
        document.project.engineeringStructures.count { $0.structure == .bridge }
    }

    private var bridgePierCount: Int {
        document.project.engineeringStructures.reduce(0) {
            $0 + $1.bridgePiers.count
        }
    }

    private var tunnelCount: Int {
        document.project.engineeringStructures.count { $0.structure == .tunnel }
    }

    private var tunnelPortalCount: Int {
        document.project.engineeringStructures.reduce(0) {
            $0 + $1.tunnelPortals.count
        }
    }
}

private enum MapScalePreset: Double, CaseIterable, Identifiable {
    case compact = 0.5
    case standard = 1
    case regional = 2
    case wide = 5
    case world = 20
    case largeWorld = 40
    case megaWorld = 62.5
    case grandWorld = 100

    var id: Double { rawValue }

    var displayName: String {
        let scale = MapScale(metersPerPoint: rawValue)
        return "\(Self.distanceDescription(scale.widthMeters)) × "
            + Self.distanceDescription(scale.heightMeters)
    }

    static func distanceDescription(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            return kilometers.formatted(
                .number.precision(.fractionLength(kilometers.rounded() == kilometers ? 0 : 1))
            ) + " km"
        }
        return "\(Int(meters.rounded())) m"
    }
}
