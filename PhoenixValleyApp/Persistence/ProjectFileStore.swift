import Foundation
import PhoenixValleyCore

struct ProjectGroup: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date

    init(id: UUID = UUID(), name: String, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }
}

struct ProjectFileStore {
    private let fileManager: FileManager
    private let legacyFileName = "current-road-project.json"

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func loadAll() throws -> [RoadProject] {
        let directory = try projectsDirectory()
        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }

        var projects = try urls.map { url in
            let data = try Data(contentsOf: url)
            return try JSONDecoder.phoenixValley.decode(RoadProject.self, from: data)
        }

        if projects.isEmpty, let legacy = try loadLegacyProject() {
            projects = [legacy]
        }

        return projects.sorted { $0.updatedAt > $1.updatedAt }
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

    private func loadLegacyProject() throws -> RoadProject? {
        let url = try baseDirectory().appending(path: legacyFileName)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.phoenixValley.decode(RoadProject.self, from: data)
    }
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
