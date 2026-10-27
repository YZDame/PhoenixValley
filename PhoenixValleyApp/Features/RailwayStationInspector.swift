import PhoenixValleyCore
import SwiftUI

struct RailwayStationInspector: View {
    let station: RailwayStation
    @Bindable var document: RoadDocumentStore
    @State private var stationName: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.headline)
                .foregroundStyle(.orange)
                .accessibilityHidden(true)

            TextField("车站名称", text: $stationName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                .onSubmit {
                    commitRename()
                }
                .accessibilityLabel("车站名称")
                .accessibilityIdentifier("station-name-textfield")

            Button(role: .destructive) {
                document.removeRailwayStation(id: station.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除车站")
            .accessibilityIdentifier("delete-station-button")

            Button {
                commitRename()
                document.selectStation(id: nil)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("完成编辑")
            .accessibilityIdentifier("close-station-inspector")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .modifier(StationInspectorSurface())
        .onAppear {
            stationName = station.name
        }
        .onChange(of: station.id) { _, _ in
            stationName = station.name
        }
    }

    private func commitRename() {
        let trimmed = stationName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty && trimmed != station.name {
            document.renameRailwayStation(id: station.id, to: trimmed)
        }
    }
}

private struct StationInspectorSurface: ViewModifier {
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
