import Foundation
import PhoenixValleyCore
import SwiftUI
import UniformTypeIdentifiers

struct PreparedMapExport: Identifiable {
    let id = UUID()
    let format: MapExportFormat
    let document: MapExportDocument
    let filename: String
}

struct MapExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.png, .pdf, .svg, MapExportFormat.geoJSON.contentType]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension MapExportFormat {
    var displayName: String {
        switch self {
        case .png: "PNG 图像"
        case .pdf: "PDF 文档"
        case .svg: "SVG 矢量图"
        case .geoJSON: "GeoJSON 数据"
        }
    }

    var symbol: String {
        switch self {
        case .png: "photo"
        case .pdf: "doc.richtext"
        case .svg: "scribble.variable"
        case .geoJSON: "curlybraces.square"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .pdf: .pdf
        case .svg: .svg
        case .geoJSON: UTType(filenameExtension: "geojson") ?? .json
        }
    }
}

extension String {
    var sanitizedExportFilename: String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = components(separatedBy: forbidden)
            .filter { !$0.isEmpty }
        let value = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "PhoenixValley" : value
    }
}
