import Foundation
import PhoenixValleyCore
import SwiftUI

struct FloatingToolPalette: View {
    @Bindable var document: RoadDocumentStore
    @Binding var isExpanded: Bool

    var body: some View {
        horizontalPalette
            .frame(maxWidth: isExpanded ? 1060 : nil)
            .padding(8)
            .modifier(PaletteGlassSurface())
            .animation(.snappy(duration: 0.22), value: isExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("floating-tool-palette")
    }

    private var horizontalPalette: some View {
        HStack(spacing: 8) {
            if isExpanded {
                ScrollView(.horizontal, showsIndicators: false) {
                    paletteContent.fixedSize(horizontal: true, vertical: false)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                paletteContent
            }
            Divider().frame(height: 34)
            historyAndCollapseControls
        }
    }

    @ViewBuilder
    private var paletteContent: some View {
        if isExpanded {
            ToolControls(document: document)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            CompactToolSummary(document: document)
                .transition(.opacity)
        }
    }

    private var historyAndCollapseControls: some View {
        HStack(spacing: 4) {
            PaletteActionButton(title: "撤销", symbol: "arrow.uturn.backward", identifier: "undo-button", iconOnly: true) { document.undo() }
                .frame(width: 44, height: 48).disabled(!document.canUndo)
            PaletteActionButton(title: "重做", symbol: "arrow.uturn.forward", identifier: "redo-button", iconOnly: true) { document.redo() }
                .frame(width: 44, height: 48).disabled(!document.canRedo)
            Divider().frame(height: 30)
            PaletteActionButton(title: isExpanded ? "折叠工具栏" : "展开工具栏",
                symbol: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical",
                identifier: "palette-collapse", iconOnly: true) { isExpanded.toggle() }
                .frame(width: 44, height: 48)
        }
    }
}

struct PaletteGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.primary.opacity(0.12))
                }
        }
    }
}

private struct CompactToolSummary: View {
    @Bindable var document: RoadDocumentStore

    var body: some View {
        HStack(spacing: 8) {
            if document.isEditingInterchange {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.tint)
                Text("立交")
            } else if document.isSelecting {
                Image(systemName: "selection.pin.in.out")
                    .foregroundStyle(.tint)
                Text("选择")
            } else if document.isErasing {
                Image(systemName: "eraser.line.dashed")
                    .foregroundStyle(.red)
                Text("擦除·\(document.eraserMode.displayName)")
            } else {
                RoadSwatch(kind: document.selectedKind)
                Text(document.selectedKind.displayName)
            }
        }
        .font(.caption.weight(.medium))
        .frame(width: 88)
    }
}

private struct ToolControls: View {
    @Bindable var document: RoadDocumentStore
    @AppStorage("fingerDrawingEnabled") private var fingerDrawingEnabled = true

    var body: some View { horizontalControls }

    private var horizontalControls: some View {
        HStack(spacing: 7) {
            ForEach(RoadKind.allCases) { kind in
                roadButton(kind)
            }
            PaletteActionButton(title: fingerDrawingEnabled ? "手绘" : "浏览",
                symbol: fingerDrawingEnabled ? "hand.draw" : "hand.point.up.left",
                selected: fingerDrawingEnabled, identifier: "finger-drawing-toggle") { fingerDrawingEnabled.toggle() }
                .frame(width: 62, height: 50)
            selectButton
            interchangeButton
            eraseButton

            Divider().frame(height: 36).padding(.horizontal, 4)
            if document.isSelecting {
                selectionSummary.frame(width: 220)
            } else if document.isEditingInterchange {
                interchangeSummary.frame(width: 220)

                Divider().frame(height: 36).padding(.horizontal, 4)
                correctionSlider.frame(width: 104)
            } else if document.isErasing {
                eraserModePicker.frame(width: 180)
            } else {
                levelPicker.frame(width: 220)

                if document.selectedKind == .railway {
                    Divider().frame(height: 36).padding(.horizontal, 4)
                    PaletteActionButton(
                        title: "设车站",
                        symbol: "building.2.crop.circle",
                        identifier: "add-station-button"
                    ) {
                        let railway = document.project.roads.filter { $0.kind == .railway }.last
                        let pt = railway?.points.isEmpty == false
                            ? railway!.points[railway!.points.count / 2]
                            : RoadPoint(x: 800, y: 600)
                        _ = document.addRailwayStation(at: pt)
                    }
                    .frame(width: 62, height: 50)
                }

                Divider().frame(height: 36).padding(.horizontal, 4)
                correctionSlider.frame(width: 104)
            }
        }
    }

    private func roadButton(_ kind: RoadKind) -> some View {
        PaletteActionButton(title: kind.displayName, symbol: kind == .railway ? "tram.fill" : "road.lanes",
            selected: (document.activeTool == .draw || document.isEditingInterchange) && document.selectedKind == kind,
            identifier: "road-tool-\(kind.rawValue)") {
            guard !(document.isEditingInterchange && kind == .railway) else {
                return
            }
            if document.isEditingInterchange {
                if document.selectedRampID != nil {
                    document.changeSelectedRampKind(to: kind)
                } else if let plan = document.pendingRampPlan {
                    document.updatePendingRamp(
                        direction: plan.ramp.direction,
                        kind: kind
                    )
                } else {
                    document.selectedKind = kind
                }
            } else {
                document.activateDrawing(kind: kind)
            }
        }
        .frame(width: 62, height: 50)
        .disabled(document.isEditingInterchange && kind == .railway)
    }

    private var selectButton: some View {
        PaletteActionButton(title: "选择", symbol: "selection.pin.in.out", selected: document.isSelecting,
            identifier: "road-selection-tool") { document.activateSelection() }
            .frame(width: 62, height: 50)
    }

    private var interchangeButton: some View {
        PaletteActionButton(title: "立交", symbol: "point.3.connected.trianglepath.dotted", selected: document.isEditingInterchange,
            identifier: "road-interchange-tool") { document.activateInterchange() }
            .frame(width: 62, height: 50)
    }

    private var eraseButton: some View {
        PaletteActionButton(title: "擦除", symbol: "eraser.line.dashed", selected: document.isErasing,
            identifier: "erase-road-tool") { document.activateEraser() }
            .frame(width: 62, height: 50)
    }

    private var eraserModePicker: some View {
        PaletteSegments(titles: RoadEraseMode.allCases.map(\.displayName), values: Array(RoadEraseMode.allCases),
            selection: $document.eraserMode, label: "擦除方式", identifier: "eraser-mode-picker")
            .frame(height: 36)
    }

    private var selectionSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .foregroundStyle(.tint)
            Text(
                document.selectedSourceRoadIDs.isEmpty
                    ? "轻点或框选道路"
                    : "已选 \(document.selectedSourceRoadIDs.count) 条道路"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 0)
            if !document.selectedSourceRoadIDs.isEmpty {
                PaletteActionButton(title: "清除道路选择", symbol: "xmark.circle.fill",
                    identifier: "clear-road-selection", iconOnly: true) { document.clearRoadSelection() }
                    .frame(width: 44, height: 44)
            }
        }
    }

    private var interchangeSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: interchangeSummarySymbol)
                .foregroundStyle(.tint)
            Text(interchangeSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var interchangeSummarySymbol: String {
        if document.pendingRampPlan != nil {
            return "checkmark.circle"
        }
        if document.isAwaitingRampDrawing {
            return "pencil.tip"
        }
        if document.selectedRampID != nil {
            return "arrow.triangle.merge"
        }
        return "diamond"
    }

    private var interchangeSummaryText: String {
        if document.pendingRampPlan != nil {
            return "检查草稿后添加"
        }
        if document.isAwaitingRampDrawing {
            return "从一条主线画向另一条"
        }
        if document.selectedRampID != nil {
            return "已选匝道"
        }
        if document.selectedInterchangeCrossingID != nil {
            return "已选异层交叉"
        }
        return "轻点菱形异层交叉"
    }

    private var levelPicker: some View {
        PaletteSegments(titles: ["隧道", "地面", "高架"], values: [RoadLevel.tunnel, .ground, .elevated],
            selection: $document.selectedLevel, label: "道路层级", identifier: "road-level-picker")
            .frame(height: 36)
            .disabled(document.isErasing || document.isSelecting)
    }

    private var correctionSlider: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("修正 \(Int(document.correctionStrength * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            PaletteSlider(value: $document.correctionStrength).frame(height: 32)
        }
    }
}

struct RoadSwatch: View {
    let kind: RoadKind

    var body: some View {
        Capsule()
            .fill(kind == .railway ? .clear : kind.color)
            .stroke(kind.color, style: StrokeStyle(lineWidth: kind == .railway ? 2 : 0, dash: kind == .railway ? [4, 3] : []))
            .frame(width: 34, height: kind.previewWidth)
    }
}

extension RoadKind {
    var layerSymbol: String {
        switch self {
        case .motorway: "road.lanes"
        case .arterial: "arrow.triangle.branch"
        case .street: "point.topleft.down.to.point.bottomright.curvepath"
        case .railway: "tram"
        }
    }

    var color: Color {
        switch self {
        case .motorway: Color(red: 0.18, green: 0.21, blue: 0.22)
        case .arterial: Color(red: 0.28, green: 0.32, blue: 0.33)
        case .street: Color(red: 0.48, green: 0.52, blue: 0.52)
        case .railway: Color(red: 0.36, green: 0.28, blue: 0.23)
        }
    }

    var previewWidth: CGFloat {
        switch self {
        case .motorway: 8
        case .arterial: 6
        case .street: 3
        case .railway: 5
        }
    }
}
