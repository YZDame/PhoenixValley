import PhoenixValleyCore
import SwiftUI

struct RoadSelectionInspector: View {
    @Bindable var document: RoadDocumentStore

    var body: some View {
        HStack(spacing: 10) {
            Label(
                "\(document.selectedSourceRoadIDs.count) 条",
                systemImage: "selection.pin.in.out"
            )
            .font(.subheadline.weight(.semibold))
            .accessibilityLabel("已选道路")
            .accessibilityValue("\(document.selectedSourceRoadIDs.count)")
            .accessibilityIdentifier("road-selection-summary")

            Divider()
                .frame(height: 24)

            Menu {
                ForEach(RoadKind.allCases) { kind in
                    Button {
                        document.changeSelectedRoadKind(to: kind)
                    } label: {
                        if document.selectedRoadKind == kind {
                            Label(kind.displayName, systemImage: "checkmark")
                        } else {
                            Text(kind.displayName)
                        }
                    }
                    .accessibilityIdentifier(
                        "selected-road-kind-\(kind.rawValue)"
                    )
                }
            } label: {
                Label(
                    document.selectedRoadKind?.displayName ?? "混合类型",
                    systemImage: "road.lanes"
                )
                .font(.subheadline)
            }
            .accessibilityLabel("修改已选道路类型")
            .accessibilityIdentifier("selected-road-kind-menu")

            Menu {
                ForEach([20, 30, 40, 50, 60, 80, 100, 120], id: \.self) {
                    speed in
                    Button {
                        document.changeSelectedRoadSpeedLimit(
                            to: Double(speed)
                        )
                    } label: {
                        if document.selectedRoadSpeedLimit == Double(speed) {
                            Label("\(speed) km/h", systemImage: "checkmark")
                        } else {
                            Text("\(speed) km/h")
                        }
                    }
                    .accessibilityIdentifier(
                        "selected-road-speed-\(speed)"
                    )
                }
            } label: {
                Label(
                    speedLabel,
                    systemImage: "gauge.with.dots.needle.50percent"
                )
                .font(.subheadline)
            }
            .accessibilityLabel("修改已选道路限速")
            .accessibilityIdentifier("selected-road-speed-menu")

            Menu {
                Button {
                    document.changeSelectedRoadTrafficAccess(to: .open)
                } label: {
                    if document.selectedRoadTrafficAccess == .open {
                        Label("开放", systemImage: "checkmark")
                    } else {
                        Text("开放")
                    }
                }
                .accessibilityIdentifier("selected-road-access-open")

                Button {
                    document.changeSelectedRoadTrafficAccess(to: .closed)
                } label: {
                    if document.selectedRoadTrafficAccess == .closed {
                        Label("封闭", systemImage: "checkmark")
                    } else {
                        Text("封闭")
                    }
                }
                .accessibilityIdentifier("selected-road-access-closed")
            } label: {
                Label(accessLabel, systemImage: accessSystemImage)
                    .font(.subheadline)
            }
            .accessibilityLabel("修改已选道路通行状态")
            .accessibilityIdentifier("selected-road-access-menu")

            Button(role: .destructive) {
                document.deleteSelectedRoads()
            } label: {
                Label("拆除", systemImage: "trash")
                    .font(.subheadline)
            }
            .accessibilityLabel("拆除已选道路")
            .accessibilityIdentifier("delete-selected-roads-button")

            Button {
                document.clearRoadSelection()
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清除道路选择")
            .accessibilityIdentifier("road-selection-clear")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .modifier(SelectionInspectorSurface())
    }

    private var speedLabel: String {
        guard let speed = document.selectedRoadSpeedLimit else {
            return "混合限速"
        }
        return "\(speed.formatted(.number.precision(.fractionLength(0)))) km/h"
    }

    private var accessLabel: String {
        switch document.selectedRoadTrafficAccess {
        case .open: "开放"
        case .closed: "封闭"
        case nil: "混合状态"
        }
    }

    private var accessSystemImage: String {
        document.selectedRoadTrafficAccess == .closed
            ? "nosign"
            : "checkmark.circle"
    }
}

private struct SelectionInspectorSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(
                    .regular.interactive(),
                    in: .rect(cornerRadius: 16)
                )
        } else {
            content
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: 16,
                        style: .continuous
                    )
                    .stroke(.primary.opacity(0.12))
                }
        }
    }
}
