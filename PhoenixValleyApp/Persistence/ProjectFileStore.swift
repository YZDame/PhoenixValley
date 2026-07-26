import Foundation
import PhoenixValleyCore

struct ProjectGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct ProjectLibraryLoadResult: Sendable {
    let projects: [RoadProject]
    let diagnostics: [ProjectFileLoadDiagnostic]
}

struct ProjectFileLoadDiagnostic: Identifiable, Error, Hashable, LocalizedError, Sendable {
    enum Reason: Hashable, Sendable {
        case unreadable
        case invalidProject
        case unsupportedFormatVersion(found: Int, supported: Int)
    }

    let fileURL: URL
    let reason: Reason
    let details: String?

    var id: URL { fileURL }
    var fileName: String { fileURL.lastPathComponent }

    var message: String {
        switch reason {
        case .unreadable:
            return formattedMessage(
                summary: "无法读取项目文件“\(fileName)”",
                details: details
            )
        case .invalidProject:
            return formattedMessage(
                summary: "项目文件“\(fileName)”已损坏或格式不完整",
                details: details
            )
        case let .unsupportedFormatVersion(found, supported):
            return "项目文件“\(fileName)”使用格式版本 \(found)，当前版本最多支持 \(supported)。请用更新版本的凤凰山谷打开；原文件未被修改。"
        }
    }

    var errorDescription: String? { message }

    private func formattedMessage(summary: String, details: String?) -> String {
        guard let details, !details.isEmpty else {
            return "\(summary)。原文件未被修改。"
        }
        return "\(summary)：\(details)。原文件未被修改。"
    }
}

struct ProjectFileStore {
    private let fileManager: FileManager
    private let legacyFileName = "current-road-project.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Loads every readable, supported project while retaining a diagnostic for
    /// each individual file that could not be loaded. Directory-level failures
    /// are still thrown to the caller.
    func loadLibrary() throws -> ProjectLibraryLoadResult {
        let directory = try projectsDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var projects: [RoadProject] = []
        var diagnostics: [ProjectFileLoadDiagnostic] = []

        for url in urls {
            appendLoadResult(
                loadProject(at: url),
                projects: &projects,
                diagnostics: &diagnostics
            )
        }

        if projects.isEmpty {
            let legacyURL = try baseDirectory().appending(path: legacyFileName)
            if fileManager.fileExists(atPath: legacyURL.path) {
                appendLoadResult(
                    loadProject(at: legacyURL),
                    projects: &projects,
                    diagnostics: &diagnostics
                )
            }
        }

        return ProjectLibraryLoadResult(
            projects: projects.sorted { $0.updatedAt > $1.updatedAt },
            diagnostics: diagnostics
        )
    }

    /// Compatibility entry point for callers that do not yet present
    /// per-file diagnostics.
    func loadAll() throws -> [RoadProject] {
        try loadLibrary().projects
    }

    func save(_ project: RoadProject) throws {
        let url = try projectsDirectory()
            .appending(path: "\(project.id.uuidString).phoenixvalley.json")
        let data = try JSONEncoder.phoenixValley.encode(project)
        try data.write(to: url, options: .atomic)
    }

    func loadGroups() throws -> [ProjectGroup] {
        let url = try baseDirectory().appending(path: "library-groups.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.phoenixValley.decode([ProjectGroup].self, from: data)
    }

    func saveGroups(_ groups: [ProjectGroup]) throws {
        let url = try baseDirectory().appending(path: "library-groups.json")
        let data = try JSONEncoder.phoenixValley.encode(groups)
        try data.write(to: url, options: .atomic)
    }

    func delete(_ project: RoadProject) throws {
        let url = try projectsDirectory()
            .appending(path: "\(project.id.uuidString).phoenixvalley.json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    private func projectsDirectory() throws -> URL {
        let projects = try baseDirectory().appending(path: "Projects", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: projects, withIntermediateDirectories: true)
        return projects
    }

    private func baseDirectory() throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "PhoenixValley", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func loadProject(
        at url: URL
    ) -> Result<RoadProject, ProjectFileLoadDiagnostic> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return .failure(
                ProjectFileLoadDiagnostic(
                    fileURL: url,
                    reason: .unreadable,
                    details: error.localizedDescription
                )
            )
        }

        let formatVersion: Int
        do {
            let envelope = try JSONDecoder.phoenixValley.decode(
                ProjectFormatEnvelope.self,
                from: data
            )
            formatVersion = envelope.formatVersion ?? 1
        } catch {
            return .failure(
                ProjectFileLoadDiagnostic(
                    fileURL: url,
                    reason: .invalidProject,
                    details: Self.decodingDetails(for: error)
                )
            )
        }

        guard formatVersion <= RoadProject.currentFormatVersion else {
            return .failure(
                ProjectFileLoadDiagnostic(
                    fileURL: url,
                    reason: .unsupportedFormatVersion(
                        found: formatVersion,
                        supported: RoadProject.currentFormatVersion
                    ),
                    details: nil
                )
            )
        }

        do {
            return .success(
                try JSONDecoder.phoenixValley.decode(RoadProject.self, from: data)
            )
        } catch {
            return .failure(
                ProjectFileLoadDiagnostic(
                    fileURL: url,
                    reason: .invalidProject,
                    details: Self.decodingDetails(for: error)
                )
            )
        }
    }

    private func appendLoadResult(
        _ result: Result<RoadProject, ProjectFileLoadDiagnostic>,
        projects: inout [RoadProject],
        diagnostics: inout [ProjectFileLoadDiagnostic]
    ) {
        switch result {
        case let .success(project):
            projects.append(project)
        case let .failure(diagnostic):
            diagnostics.append(diagnostic)
        }
    }

    private static func decodingDetails(for error: Error) -> String {
        switch error {
        case let DecodingError.keyNotFound(key, context):
            return "缺少字段 \(key.stringValue)\(codingPathDescription(context.codingPath))"
        case let DecodingError.typeMismatch(_, context):
            return "字段类型不正确\(codingPathDescription(context.codingPath))"
        case let DecodingError.valueNotFound(_, context):
            return "字段值缺失\(codingPathDescription(context.codingPath))"
        case let DecodingError.dataCorrupted(context):
            return "数据无法解析\(codingPathDescription(context.codingPath))：\(context.debugDescription)"
        default:
            return error.localizedDescription
        }
    }

    private static func codingPathDescription(_ codingPath: [any CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "" }
        let path = codingPath.map(\.stringValue).joined(separator: ".")
        return "（\(path)）"
    }
}

private struct ProjectFormatEnvelope: Decodable {
    let formatVersion: Int?
}

private extension JSONEncoder {
    static var phoenixValley: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var phoenixValley: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
