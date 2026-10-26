import PhoenixValleyCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class MapViewportReference {
    var value: MapExportViewport?
}

struct MapExportSession: Identifiable {
    let id = UUID()
    let viewport: MapExportViewport?
}

struct MapExportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: RoadDocumentStore
    let viewport: MapExportViewport?
    @State private var format = MapExportFormat.png
    @State private var exportsEntireMap = true
    @State private var showsTitle = true
    @State private var showsScale = true
    @State private var showsInformation = false
    @State private var showsAttribution = true
    @State private var preview: UIImage?
    @State private var isRenderingPreview = false
    @State private var isPreparing = false
    @State private var prepared: PreparedMapExport?
    @State private var presentsFileExporter = false
    @State private var errorMessage: String?

    private var options: MapExportOptions {
        MapExportOptions(viewport: exportsEntireMap ? nil : viewport,
            showsTitle: showsTitle, showsScale: showsScale, showsInformation: showsInformation,
            showsAttribution: showsAttribution)
    }
    private var previewKey: PreviewKey { PreviewKey(theme: document.project.theme, options: options) }
    private var needsSource: Bool { document.project.realWorldMap?.source == .osmXML }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color(cgColor: document.project.theme.palette.plain.cgColor))
                            if let preview {
                                Image(uiImage: preview).resizable().scaledToFit()
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                            }
                            if isRenderingPreview { ProgressView().padding(12).background(.regularMaterial, in: Capsule()) }
                        }
                        .aspectRatio(previewAspectRatio, contentMode: .fit)
                        .frame(maxHeight: 340)
                        .accessibilityLabel("导出地图预览")
                        .accessibilityValue("\(document.project.theme.displayName)，\(exportsEntireMap ? "整张地图" : "当前视野")")
                        .accessibilityIdentifier("export-preview-card")
                        HStack {
                            Text(document.project.name).font(.headline)
                            Spacer()
                            Text(format.displayName).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Section("范围与格式") {
                    Picker("导出范围", selection: $exportsEntireMap) {
                        Text("整张地图").tag(true)
                        Text("当前视野").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .disabled(viewport == nil)
                    .accessibilityIdentifier("export-extent-picker")
                    Picker("文件格式", selection: $format) {
                        ForEach(MapExportFormat.allCases) { item in Text(item.displayName).tag(item) }
                    }
                    .accessibilityIdentifier("export-format-picker")
                    Text("当前视野保留地图的缩放与旋转，工具栏不会出现在导出文件中。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    ThemePicker(selection: Binding(get: { document.project.theme }, set: { document.setTheme($0) }))
                } header: { Text("地图主题") }
                  footer: { Text("主题会同步到画布，也可在地图外观中继续调整。") }
                Section {
                    Toggle("地图标题", isOn: $showsTitle).accessibilityIdentifier("export-title-toggle")
                    Toggle("比例尺", isOn: $showsScale).accessibilityIdentifier("export-scale-toggle")
                    Toggle("范围与道路数量", isOn: $showsInformation).accessibilityIdentifier("export-information-toggle")
                    if document.project.realWorldMap != nil {
                        Toggle("来源署名", isOn: $showsAttribution).disabled(needsSource)
                            .accessibilityIdentifier("export-attribution-toggle")
                    }
                } header: { Text("文字信息") }
                  footer: {
                    if format == .geoJSON { Text("GeoJSON 保存可编辑的地理数据，不包含文字排版与主题配色。") }
                    else if needsSource { Text("OpenStreetMap 数据导出保留来源署名。") }
                  }
                  .disabled(format == .geoJSON)
            }
            .disabled(isPreparing)
            .navigationTitle("导出设计")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { prepare() } label: {
                        if isPreparing { ProgressView() } else { Text("导出") }
                    }
                    .disabled(isPreparing || isRenderingPreview || preview == nil)
                    .accessibilityIdentifier("export-confirm")
                }
            }
            .task(id: previewKey) { await renderPreview() }
            .onChange(of: prepared?.id) {
                if prepared != nil { presentsFileExporter = true }
            }
            .fileExporter(isPresented: $presentsFileExporter, document: prepared?.document,
                contentType: prepared?.format.contentType ?? .data,
                defaultFilename: prepared?.filename ?? "PhoenixValley") { result in
                    if case let .failure(error) = result, (error as NSError).code != NSUserCancelledError { errorMessage = error.localizedDescription }
                    prepared = nil
                }
            .alert("导出未完成", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.large])
    }

    private var previewAspectRatio: CGFloat {
        if !exportsEntireMap, let viewport { return viewport.width/viewport.height }
        return 4/3
    }

    private func renderPreview() async {
        isRenderingPreview = true
        let project = document.project, options = options
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try MapExporter.data(for: project, format: .png, options: options)
            }.value
            guard !Task.isCancelled else { return }
            preview = UIImage(data: data)
            isRenderingPreview = false
        } catch {
            guard !Task.isCancelled else { return }
            isRenderingPreview = false; errorMessage = error.localizedDescription
        }
    }

    private func prepare() {
        isPreparing = true
        let project = document.project, options = options, selectedFormat = format
        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try MapExporter.data(for: project, format: selectedFormat, options: options)
                }.value
                prepared = PreparedMapExport(format: selectedFormat, document: MapExportDocument(data: data),
                    filename: "\(project.name.sanitizedExportFilename).\(selectedFormat.filenameExtension)")
                isPreparing = false
            } catch { isPreparing = false; errorMessage = error.localizedDescription }
        }
    }

    private struct PreviewKey: Equatable {
        var theme: MapTheme
        var options: MapExportOptions
    }
}
