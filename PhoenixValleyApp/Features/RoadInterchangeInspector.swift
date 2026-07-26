import PhoenixValleyCore
import SwiftUI

struct RoadInterchangeInspector: View {
    @Bindable var document: RoadDocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
        }
        .frame(width: 300, alignment: .leading)
        .padding(14)
        .modifier(InterchangeInspectorSurface())
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(.tint)
            Text("立交编辑")
                .font(.headline)
            Spacer()
            Button {
                document.activateInterchange()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除立交选择")
        }
    }

    @ViewBuilder
    private var content: some View {
        if let plan = document.pendingRampPlan {
            rampDraft(plan)
        } else if document.isAwaitingRampDrawing {
            drawingInstructions
        } else if let ramp = selectedRamp {
            rampEditor(ramp)
        } else if let crossing = document.selectedInterchangeCrossing {
            crossingEditor(crossing)
        } else if selectableCrossings.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "当前没有可编辑的异层交叉",
                    systemImage: "diamond"
                )
                .font(.subheadline.weight(.semibold))
                Text("先让两条公路在不同层级相交，例如地面道路与高架道路；再回到“立交”，轻点交叉处的青色菱形。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "轻点画布上的青色菱形",
                    systemImage: "diamond"
                )
                .font(.subheadline.weight(.semibold))
                Text("选中异层交叉后，点“添加匝道”，再从一条高亮主线画到另一条。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        if let message = document.pendingRampError {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("interchange-validity-summary")
        }
    }

    private func crossingEditor(_ crossing: RoadRelation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                "\(levelName(crossing.firstLevel)) / \(levelName(crossing.secondLevel))",
                systemImage: "arrow.up.and.down.and.arrow.left.and.right"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                existingInterchange(for: crossing).map {
                    "\($0.name) · \($0.ramps.count) 条匝道"
                } ?? "尚未添加匝道"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            directionPicker

            Button {
                document.beginRampDrawing()
            } label: {
                Label("添加匝道", systemImage: "pencil.and.scribble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("interchange-add-ramp")
        }
    }

    private var drawingInstructions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("从一条主线画向另一条主线", systemImage: "pencil.tip")
                .font(.subheadline.weight(.semibold))
            Text("首尾需要落在两条高亮主线上；绘制方向就是默认行驶方向。双指仍可平移和缩放。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            directionPicker
            Button("取消绘制") {
                document.cancelRampDraft()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("interchange-cancel-ramp")
        }
    }

    private func rampDraft(_ plan: RoadRampPlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("匝道草稿", systemImage: "checkmark.circle")
                .font(.subheadline.weight(.semibold))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("连接").foregroundStyle(.secondary)
                    Text(
                        "\(levelName(plan.ramp.start.level)) → \(levelName(plan.ramp.end.level))"
                    )
                }
                GridRow {
                    Text("类型").foregroundStyle(.secondary)
                    Text(plan.roadSegments.first?.kind.displayName ?? "道路")
                }
                GridRow {
                    Text("方向").foregroundStyle(.secondary)
                    Text(directionName(plan.ramp.direction))
                }
            }
            .font(.caption)

            directionPicker

            HStack {
                Button("重画") {
                    document.beginRampDrawing()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("取消") {
                    document.cancelRampDraft()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("interchange-cancel-ramp")

                Button("添加") {
                    document.commitRampDraft()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("interchange-commit-ramp")
            }
        }
    }

    private func rampEditor(_ ramp: RoadRamp) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                selectedRampKind?.displayName.appending("匝道") ?? "匝道",
                systemImage: "arrow.triangle.merge"
            )
            .font(.subheadline.weight(.semibold))

            Text(
                "\(levelName(ramp.start.level)) ↔ \(levelName(ramp.end.level))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            Menu {
                ForEach([RoadKind.motorway, .arterial, .street]) { kind in
                    Button(kind.displayName) {
                        document.changeSelectedRampKind(to: kind)
                    }
                }
            } label: {
                Label(
                    selectedRampKind?.displayName ?? "道路类型",
                    systemImage: "road.lanes"
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("interchange-ramp-kind-menu")

            directionPicker

            Button(role: .destructive) {
                document.deleteSelectedRamp()
            } label: {
                Label("删除匝道", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("interchange-delete-ramp")
        }
    }

    private var directionPicker: some View {
        Picker(
            "通行方向",
            selection: Binding(
                get: { document.rampDirection },
                set: { direction in
                    if document.selectedRampID != nil {
                        document.changeSelectedRampDirection(to: direction)
                    } else if let plan = document.pendingRampPlan {
                        document.updatePendingRamp(
                            direction: direction,
                            kind: plan.roadSegments.first?.kind
                                ?? document.selectedKind
                        )
                    } else {
                        document.rampDirection = direction
                    }
                }
            )
        ) {
            Text("正向").tag(RoadDirection.forward)
            Text("反向").tag(RoadDirection.reverse)
            Text("双向").tag(RoadDirection.bidirectional)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("interchange-ramp-direction-picker")
    }

    private var selectedRamp: RoadRamp? {
        guard let selectedRampID = document.selectedRampID else { return nil }
        return document.project.interchanges
            .lazy
            .flatMap(\.ramps)
            .first { $0.id == selectedRampID }
    }

    private var selectableCrossings: [RoadRelation] {
        document.project.roadNetwork.relations.filter {
            $0.kind == .gradeSeparatedCrossing && $0.secondaryPoint == nil
        }
    }

    private var selectedRampKind: RoadKind? {
        guard let selectedRampID = document.selectedRampID else { return nil }
        return document.project.roads.first {
            $0.sourceRoadID == selectedRampID
        }?.kind
    }

    private func existingInterchange(
        for crossing: RoadRelation
    ) -> RoadInterchange? {
        let crossingRoadIDs = Set([
            crossing.firstRoadID,
            crossing.secondRoadID,
        ])
        return document.project.interchanges.first {
            Set([
                $0.anchor.upperSourceRoadID,
                $0.anchor.lowerSourceRoadID,
            ]) == crossingRoadIDs
                && $0.anchor.lastKnownPoint.distance(to: crossing.point)
                    <= document.project.mapScale.canvasDistance(forMeters: 30)
        }
    }

    private func directionName(_ direction: RoadDirection) -> String {
        switch direction {
        case .forward: "正向"
        case .reverse: "反向"
        case .bidirectional: "双向"
        }
    }

    private func levelName(_ level: RoadLevel) -> String {
        switch level {
        case .tunnel: "隧道"
        case .ground: "地面"
        case .elevated: "高架"
        }
    }
}

private struct InterchangeInspectorSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: 18)
                )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 18,
                        style: .continuous
                    )
                    .stroke(.black.opacity(0.1))
                }
        }
    }
}
