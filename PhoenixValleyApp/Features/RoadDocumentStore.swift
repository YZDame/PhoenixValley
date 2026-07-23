import Foundation
import Observation
import PhoenixValleyCore

@MainActor
@Observable
final class RoadDocumentStore {
    private(set) var project: RoadProject
    private(set) var projects: [RoadProject]
    private(set) var groups: [ProjectGroup]
    var selectedKind: RoadKind = .arterial
    var selectedLevel: RoadLevel = .ground
    var isErasing = false
    var correctionStrength = 0.6
    private(set) var saveErrorMessage: String?

    private var undoStack: [RoadProject] = []
    private var redoStack: [RoadProject] = []
    private let fileStore: ProjectFileStore

    init(fileStore: ProjectFileStore = ProjectFileStore()) {
        self.fileStore = fileStore
        groups = (try? fileStore.loadGroups()) ?? []
        let savedProjects = (try? fileStore.loadAll()) ?? []
        if let saved = savedProjects.first {
            projects = savedProjects.map(Self.upgraded)
            project = Self.upgraded(saved)
        } else {
            let initialProject = RoadProject(
                name: "我的第一座城市",
                terrain: TerrainGenerator.generate(seed: 20260722)
            )
            project = initialProject
            projects = [initialProject]
        }
        persist()
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func addStroke(_ rawPoints: [RoadPoint]) {
        let configuration = StrokeProcessingConfiguration(
            minimumSampleDistance: 1.2,
            smoothingPasses: correctionStrength < 0.35 ? 1 : 2,
            simplificationTolerance: 0.8 + correctionStrength * 3.2,
            endpointSnapRadius: 6 + correctionStrength * 18,
            angleSnapTolerance: correctionStrength < 0.7 ? 0 : .pi / 36
        )
        let points = StrokeProcessor.process(
            rawPoints,
            existingRoads: project.roads.filter { $0.level == selectedLevel },
            configuration: configuration
        )
        guard points.count >= 2 else { return }

        checkpointForUndo()
        project.roads.append(
            RoadSegment(kind: selectedKind, level: selectedLevel, points: points)
        )
        project.updatedAt = .now
        persist()
    }

    func eraseRoads(ids: Set<UUID>) {
        guard !ids.isEmpty, project.roads.contains(where: { ids.contains($0.id) }) else { return }
        checkpointForUndo()
        project.roads.removeAll { ids.contains($0.id) }
        project.updatedAt = .now
        persist()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(project)
        project = previous
        persist()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        project = next
        persist()
    }

    func createNewMap() {
        let seed = UInt64.random(in: 1...UInt64.max)
        let number = projects.count + 1
        project = RoadProject(
            name: "新地图 \(number)",
            terrain: TerrainGenerator.generate(seed: seed),
            groupID: project.groupID
        )
        projects.append(project)
        resetHistory()
        persist()
    }

    func selectProject(id: UUID) {
        guard id != project.id, let selected = projects.first(where: { $0.id == id }) else { return }
        project = selected
        resetHistory()
    }

    func renameCurrentProject(to name: String) {
        renameProject(id: project.id, to: name)
    }

    func renameProject(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = trimmed
        projects[index].updatedAt = .now
        let renamedProject = projects[index]
        if project.id == id { project = renamedProject }
        projects.sort { $0.updatedAt > $1.updatedAt }
        persistProject(renamedProject)
    }

    func duplicateCurrentProject() {
        let copy = RoadProject(
            name: "\(project.name) 副本",
            terrain: project.terrain,
            roads: project.roads,
            theme: project.theme,
            showsContours: project.showsContours,
            showsGrid: project.showsGrid,
            groupID: project.groupID
        )
        project = copy
        projects.append(copy)
        resetHistory()
        persist()
    }

    func deleteCurrentProject() {
        let deleted = project
        do {
            try fileStore.delete(deleted)
            projects.removeAll { $0.id == deleted.id }
            if let next = projects.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                project = next
            } else {
                project = RoadProject(
                    name: "新地图",
                    terrain: TerrainGenerator.generate(seed: UInt64.random(in: 1...UInt64.max))
                )
                projects = [project]
                try fileStore.save(project)
            }
            resetHistory()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    func setTheme(_ theme: MapTheme) {
        guard project.theme != theme else { return }
        project.theme = theme
        project.updatedAt = .now
        persist()
    }

    func setShowsContours(_ value: Bool) {
        guard project.showsContours != value else { return }
        project.showsContours = value
        project.updatedAt = .now
        persist()
    }

    func setShowsGrid(_ value: Bool) {
        guard project.showsGrid != value else { return }
        project.showsGrid = value
        project.updatedAt = .now
        persist()
    }

    @discardableResult
    func createGroup(named name: String = "新分组") -> UUID {
        let group = ProjectGroup(name: name)
        groups.append(group)
        persistGroups()
        return group.id
    }

    func renameGroup(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[index].name = trimmed
        persistGroups()
    }

    func deleteGroup(id: UUID) {
        groups.removeAll { $0.id == id }
        let affectedIndices = projects.indices.filter { projects[$0].groupID == id }
        for index in affectedIndices {
            projects[index].groupID = nil
            if project.id == projects[index].id { project = projects[index] }
            persistProject(projects[index])
        }
        persistGroups()
    }

    func moveProject(id: UUID, to groupID: UUID?) {
        guard groupID == nil || groups.contains(where: { $0.id == groupID }),
              let index = projects.firstIndex(where: { $0.id == id }),
              projects[index].groupID != groupID
        else { return }
        projects[index].groupID = groupID
        if project.id == id { project = projects[index] }
        persistProject(projects[index])
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }

    private func checkpointForUndo() {
        undoStack.append(project)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack.removeAll()
    }

    private func resetHistory() {
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func persist() {
        do {
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
            } else {
                projects.append(project)
            }
            projects.sort { $0.updatedAt > $1.updatedAt }
            try fileStore.save(project)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func persistProject(_ project: RoadProject) {
        do {
            try fileStore.save(project)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func persistGroups() {
        do {
            try fileStore.saveGroups(groups)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private static func upgraded(_ project: RoadProject) -> RoadProject {
        var copy = project
        copy.formatVersion = RoadProject.currentFormatVersion
        copy.terrain = TerrainGenerator.upgrading(project.terrain)
        return copy
    }
}
