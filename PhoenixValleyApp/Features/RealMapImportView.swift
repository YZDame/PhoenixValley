import Foundation
import PhoenixValleyCore
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct RealMapImportView: View {
    @Environment(\.dismiss) private var dismiss
    let document: RoadDocumentStore
    @State private var name = "真实地图"
    @State private var latitude = "25.0340"
    @State private var longitude = "121.5645"
    @State private var widthMeters = 800.0
    @State private var simplificationMeters = 8.0
    @State private var phase: ImportPhase = .idle
    @State private var operation: Task<Void, Never>?
    @State private var showsFileImporter = false
    @State private var confirmsWGS84Elevation = false
    @FocusState private var focusedField: ImportField?

    private enum ImportField { case name, latitude, longitude }
    private var statusKey: Int {
        switch phase {
        case .idle: 0
        case .loading: 1
        case .ready: 2
        case .failed: 3
        }
    }

    private enum ImportPhase {
        case idle
        case loading(String)
        case ready(GeoImportResult)
        case failed(String)
    }

    private var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            Form {
                Section("地图名称") {
                    TextField("名称", text: $name)
                        .focused($focusedField, equals: .name)
                        .accessibilityIdentifier("real-map-name")
                }
                Section {
                    TextField("中心纬度", text: $latitude)
                        .focused($focusedField, equals: .latitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("real-map-latitude")
                    TextField("中心经度", text: $longitude)
                        .focused($focusedField, equals: .longitude)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("real-map-longitude")
                    Picker("区域范围", selection: $widthMeters) {
                        Text("800 × 600 米").tag(800.0)
                        Text("1.6 × 1.2 千米").tag(1600.0)
                        Text("3.2 × 2.4 千米").tag(3200.0)
                    }
                    .accessibilityIdentifier("real-map-area")
                    Button("使用 Apple 地图", systemImage: "map") {
                        focusedField = nil
                        guard let lat = Double(latitude), let lon = Double(longitude) else {
                            phase = .failed("请输入有效的十进制经纬度。")
                            return
                        }
                        do {
                            let bounds = try GeoBounds.around(latitude: lat, longitude: lon,
                                widthMeters: widthMeters, heightMeters: widthMeters * 0.75)
                            if document.importRealWorldProject(.appleMap(name: name, bounds: bounds)) { dismiss() }
                        } catch { phase = .failed(error.localizedDescription) }
                    }
                    .accessibilityIdentifier("real-map-apple")
                } header: {
                    Text("真实世界地图")
                } footer: {
                    Text("Apple 地图提供原生底图和地图手势；底图上的道路不参与游戏编辑。OpenStreetMap 可导入可编辑道路。按中心位置截取所选范围。道路、水域、绿地与建筑会简化成可编辑地图；不包含卫星影像或真实高程。默认位置在台北信义区。")
                }
                Section {
                    Picker("简化程度", selection: $simplificationMeters) {
                        Text("精细 · 2 米").tag(2.0)
                        Text("均衡 · 8 米").tag(8.0)
                        Text("简洁 · 20 米").tag(20.0)
                    }
                    Toggle("高程文件采用 WGS84 经纬度", isOn: $confirmsWGS84Elevation)
                        .accessibilityIdentifier("real-map-dem-wgs84")
                    Button("选择地图文件", systemImage: "doc.badge.arrow.up") {
                        focusedField = nil
                        showsFileImporter = true
                    }
                    .accessibilityIdentifier("real-map-file")
                } header: {
                    Text("从文件导入")
                } footer: {
                    Text("支持 OpenStreetMap XML（.osm）、Google Earth KML（.kml）及 WGS84 经纬度的高程网格（.asc）。KML 只读取几何，不下载外部图像或链接；KMZ 请先解压取得 KML。")
                }
                statusSection.id("import-status")
            }
            .scrollDismissesKeyboard(.interactively)
            .disabled(isLoading)
            .onChange(of: statusKey) {
                if statusKey >= 2 {
                    withAnimation { proxy.scrollTo("import-status", anchor: .top) }
                }
            }
            }

            .navigationTitle("导入真实地图")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        operation?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if case let .ready(result) = phase {
                        Button("保存为新地图") {
                            var project = result.project
                            project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            if project.name.isEmpty { project.name = "真实地图" }
                            if document.importRealWorldProject(project) { dismiss() }
                            else { phase = .failed(document.saveErrorMessage ?? "地图未能保存。") }
                        }
                        .accessibilityIdentifier("real-map-save")
                    }
                }
            }
            .fileImporter(
                isPresented: $showsFileImporter,
                allowedContentTypes: [.xml, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case let .success(urls):
                    if let url = urls.first { loadFile(url) }
                case let .failure(error):
                    if (error as NSError).code != NSUserCancelledError {
                        phase = .failed(error.localizedDescription)
                    }
                }
            }
            .onDisappear { operation?.cancel() }
            .onChange(of: latitude) { invalidatePreview() }
            .onChange(of: longitude) { invalidatePreview() }
            .onChange(of: widthMeters) { invalidatePreview() }
            .onChange(of: simplificationMeters) { invalidatePreview() }
            .onChange(of: confirmsWGS84Elevation) { invalidatePreview() }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var statusSection: some View {
        switch phase {
        case .idle:
            EmptyView()
        case let .loading(message):
            Section { ProgressView(message) }
        case let .failed(message):
            Section("未能导入") {
                Text(message).foregroundStyle(.red)
                    .accessibilityIdentifier("real-map-error")
            }
        case let .ready(result):
            Section("导入预览") {
                RealMapImportPreview(project: result.project)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                LabeledContent("道路", value: "\(Set(result.project.roads.map(\.sourceRoadID)).count) 条")
                LabeledContent("底图要素", value: "\(result.project.realWorldMap?.features.count ?? 0) 个")
                LabeledContent("地图范围", value: "\(Int(result.project.mapScale.widthMeters.rounded())) × \(Int(result.project.mapScale.heightMeters.rounded())) 米")
                Text(result.summary.description).font(.footnote)
                ForEach(result.summary.warnings, id: \.self) { warning in
                    Text(warning).font(.footnote).foregroundStyle(.secondary)
                }
                Text("预览通过后再保存，现有地图不会被覆盖。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let map = result.project.realWorldMap {
                    Text(map.attribution).font(.footnote)
                    if map.elevation == nil {
                        Text("此地图没有真实地表高程，不以程序生成的山地代替。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Link("OpenStreetMap 数据来源与许可", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
            }
            .accessibilityIdentifier("real-map-preview")
        }
    }

    private func loadOpenStreetMap() {
        guard let lat = Double(latitude), let lon = Double(longitude) else {
            phase = .failed("请输入有效的十进制经纬度。")
            return
        }
        do {
            let bounds = try GeoBounds.around(latitude: lat, longitude: lon,
                widthMeters: widthMeters, heightMeters: widthMeters * 0.75)
            let options = GeoImportOptions(name: name, bounds: bounds,
                simplificationMeters: simplificationMeters)
            start(message: "正在下载并简化地图…") {
                let data = try await RealMapImportLoader.download(bounds: bounds)
                return try await Task.detached(priority: .userInitiated) {
                    try GeoMapImporter.importMap(data: data, format: .osmXML, options: options)
                }.value
            }
        } catch { phase = .failed(error.localizedDescription) }
    }

    private func loadFile(_ url: URL) {
        let options = GeoImportOptions(name: name, simplificationMeters: simplificationMeters,
            demCoordinateSystem: confirmsWGS84Elevation ? .wgs84 : nil)
        start(message: "正在读取并简化地图…") {
            try await Task.detached(priority: .userInitiated) {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= RealMapImportLoader.maximumBytes else {
                    throw RealMapImportLoader.Failure.tooLarge
                }
                let format: GeoImportFormat
                switch url.pathExtension.lowercased() {
                case "osm", "xml": format = .osmXML
                case "kml": format = .kml
                case "asc": format = .esriASCII
                default: throw RealMapImportLoader.Failure.unsupportedFile
                }
                let data = try Data(contentsOf: url, options: .mappedIfSafe)
                guard data.count <= RealMapImportLoader.maximumBytes else {
                    throw RealMapImportLoader.Failure.tooLarge
                }
                try Task.checkCancellation()
                return try GeoMapImporter.importMap(data: data, format: format, options: options)
            }.value
        }
    }

    private func invalidatePreview() {
        operation?.cancel()
        phase = .idle
    }

    private func start(message: String, action: @escaping @Sendable () async throws -> GeoImportResult) {
        operation?.cancel()
        phase = .loading(message)
        operation = Task { @MainActor in
            do {
                let result = try await action()
                try Task.checkCancellation()
                phase = .ready(result)
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { phase = .failed(error.localizedDescription) }
            }
        }
    }
}

private enum RealMapImportLoader {
    static let maximumBytes = 8 * 1024 * 1024

    enum Failure: LocalizedError {
        case tooLarge, unsupportedFile, server(Int)
        var errorDescription: String? {
            switch self {
            case .tooLarge: "地图数据超过 8 MB，请缩小区域或先在地理软件中裁剪。"
            case .unsupportedFile: "请选择 .osm、.kml 或 .asc 文件。"
            case let .server(code): "地图服务暂时不可用（\(code)），请稍后重试或导入本地文件。"
            }
        }
    }

    static func download(bounds: GeoBounds) async throws -> Data {
        var components = URLComponents(string: "https://api.openstreetmap.org/api/0.6/map")!
        components.queryItems = [URLQueryItem(name: "bbox", value: bounds.bboxQuery)]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 45
        request.setValue("PhoenixValley/1.0 (iPad map import)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw Failure.server(0) }
        guard response.statusCode == 200 else { throw Failure.server(response.statusCode) }
        guard response.expectedContentLength <= maximumBytes else { throw Failure.tooLarge }
        var data = Data()
        for try await byte in bytes {
            if data.count >= maximumBytes { throw Failure.tooLarge }
            data.append(byte)
            if data.count.isMultiple(of: 16_384) { try Task.checkCancellation() }
        }
        return data
    }
}

private struct RealMapImportPreview: View {
    let project: RoadProject
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                ProgressView("正在绘制预览…")
            }
        }
        .accessibilityLabel("导入地图预览")
        .task(id: project.id) {
            let data = try? await Task.detached(priority: .userInitiated) {
                try MapExporter.data(for: project, format: .png)
            }.value
            if !Task.isCancelled, let data { image = UIImage(data: data) }
        }
    }
}
