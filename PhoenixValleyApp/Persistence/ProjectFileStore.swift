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
    private let iCloudContainerIdentifier = "iCloud.com.leyudame.PhoenixValley"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Loads every readable, supported project while retaining a diagnostic for
    /// each individual file that could not be loaded. Directory-level failures
    /// are still thrown to the caller.
    func loadLibrary() throws -> ProjectLibraryLoadResult {
        let directory = try projectsDirectory()
        let urls = try coordinatedDirectoryContents(at: directory)
        .filter { $0.pathExtension == "json" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var projects: [RoadProject] = []
        var fileModifiedAt: [UUID: Date] = [:]
        var diagnostics: [ProjectFileLoadDiagnostic] = []

        for url in urls {
            let result = loadProject(at: url)
            appendLoadResult(result, projects: &projects, diagnostics: &diagnostics)
            if case let .success(project) = result {
                fileModifiedAt[project.id] = modificationDate(of: url)
            }
        }

        if projects.isEmpty {
            let legacyURL = try baseDirectory().appending(path: legacyFileName)
            if fileManager.fileExists(atPath: legacyURL.path) {
                let result = loadProject(at: legacyURL)
                appendLoadResult(result, projects: &projects, diagnostics: &diagnostics)
                if case let .success(project) = result {
                    fileModifiedAt[project.id] = modificationDate(of: legacyURL)
                }
            }
        }

        return ProjectLibraryLoadResult(
            projects: projects.sorted {
                Self.libraryRecency($0, $1, fileModifiedAt: fileModifiedAt)
            },
            diagnostics: diagnostics
        )
    }

    /// Recency ordering with deterministic tiebreaks. Files written by older
    /// versions share whole-second `updatedAt` values, so the file's
    /// modification time — which keeps filesystem precision and reflects the
    /// real last write — breaks ties before falling back to the project id.
    private static func libraryRecency(
        _ lhs: RoadProject,
        _ rhs: RoadProject,
        fileModifiedAt: [UUID: Date]
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
        let lhsModified = fileModifiedAt[lhs.id] ?? .distantPast
        let rhsModified = fileModifiedAt[rhs.id] ?? .distantPast
        if lhsModified != rhsModified { return lhsModified > rhsModified }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))
            .flatMap(\.contentModificationDate)
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
        try coordinatedWrite(data, to: url)
    }

    func loadGroups() throws -> [ProjectGroup] {
        let url = try baseDirectory().appending(path: "library-groups.json")
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try coordinatedRead(at: url)
        return try JSONDecoder.phoenixValley.decode([ProjectGroup].self, from: data)
    }

    func saveGroups(_ groups: [ProjectGroup]) throws {
        let url = try baseDirectory().appending(path: "library-groups.json")
        let data = try JSONEncoder.phoenixValley.encode(groups)
        try coordinatedWrite(data, to: url)
    }

    func delete(_ project: RoadProject) throws {
        let url = try projectsDirectory()
            .appending(path: "\(project.id.uuidString).phoenixvalley.json")
        guard fileManager.fileExists(atPath: url.path) else { return }
        try coordinatedDelete(at: url)
    }

    private func projectsDirectory() throws -> URL {
        let projects = try baseDirectory().appending(path: "Projects", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: projects, withIntermediateDirectories: true)
        return projects
    }

    private func baseDirectory() throws -> URL {
        let localDirectory = try localBaseDirectory()
        guard fileManager.ubiquityIdentityToken != nil,
              let container = fileManager.url(
                forUbiquityContainerIdentifier: iCloudContainerIdentifier
              )
        else {
            return localDirectory
        }

        let directory = container
            .appending(path: "Documents", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try migrateLocalLibraryIfNeeded(from: localDirectory, to: directory)
        return directory
    }

    private func localBaseDirectory() throws -> URL {
        let directory = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appending(path: "PhoenixValley", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func migrateLocalLibraryIfNeeded(
        from localDirectory: URL,
        to cloudDirectory: URL
    ) throws {
        let localProjects = localDirectory
            .appending(path: "Projects", directoryHint: .isDirectory)
        let cloudProjects = cloudDirectory
            .appending(path: "Projects", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: localProjects.path) {
            try fileManager.createDirectory(
                at: cloudProjects,
                withIntermediateDirectories: true
            )
            for source in try fileManager.contentsOfDirectory(
                at: localProjects,
                includingPropertiesForKeys: nil
            ) where source.pathExtension == "json" {
                let destination = cloudProjects.appending(path: source.lastPathComponent)
                guard !fileManager.fileExists(atPath: destination.path) else { continue }
                try coordinatedWrite(Data(contentsOf: source), to: destination)
            }
        }

        for fileName in ["library-groups.json", legacyFileName] {
            let source = localDirectory.appending(path: fileName)
            let destination = cloudDirectory.appending(path: fileName)
            guard fileManager.fileExists(atPath: source.path),
                  !fileManager.fileExists(atPath: destination.path)
            else { continue }
            try coordinatedWrite(Data(contentsOf: source), to: destination)
        }
    }

    private func coordinatedDirectoryContents(at directory: URL) throws -> [URL] {
        var coordinationError: NSError?
        var result: Result<[URL], Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: directory,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result {
                try fileManager.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: nil
                )
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        return try result?.get() ?? []
    }

    private func coordinatedRead(at url: URL) throws -> Data {
        if fileManager.isUbiquitousItem(at: url) {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        }
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator().coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError {
            throw coordinationError
        }
        guard let result else {
            throw CocoaError(.fileReadUnknown)
        }
        return try result.get()
    }

    private func coordinatedWrite(_ data: Data, to url: URL) throws {
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try data.write(to: coordinatedURL, options: .atomic)
            } catch {
                writeError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let writeError {
            throw writeError
        }
    }

    private func coordinatedDelete(at url: URL) throws {
        var coordinationError: NSError?
        var deleteError: Error?
        NSFileCoordinator().coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                try fileManager.removeItem(at: coordinatedURL)
            } catch {
                deleteError = error
            }
        }
        if let coordinationError {
            throw coordinationError
        }
        if let deleteError {
            throw deleteError
        }
    }

    private func loadProject(
        at url: URL
    ) -> Result<RoadProject, ProjectFileLoadDiagnostic> {
        let data: Data
        do {
            data = try coordinatedRead(at: url)
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
        // Keep sub-second precision: whole-second ISO8601 made projects
        // written in the same second share identical `updatedAt` values.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(PhoenixValleyDateCoding.encode(date))
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var phoenixValley: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            // Files written before fractional seconds were introduced carry
            // whole-second timestamps; accept both forms.
            if let date = PhoenixValleyDateCoding.decode(string) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "无法解析的日期：\(string)"
            )
        }
        return decoder
    }
}

private enum PhoenixValleyDateCoding {
    static func encode(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func decode(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}
