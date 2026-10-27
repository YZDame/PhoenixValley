import Foundation
import PhoenixValleyCore

final class TemporaryFileManager: FileManager, @unchecked Sendable {
    let root: URL
    var failResolution = false

    init(root: URL) { self.root = root; super.init() }
    override var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? { nil }
    override func url(
        for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
        appropriateFor url: URL?, create shouldCreate: Bool
    ) throws -> URL {
        guard directory == .applicationSupportDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }
        if failResolution { throw CocoaError(.fileWriteNoPermission) }
        return root
    }
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw NSError(domain: message, code: 1) }
}

@MainActor
func fixture(_ roads: [RoadSegment], interchanges: [RoadInterchange] = []) throws
    -> (RoadDocumentStore, ProjectFileStore, TemporaryFileManager) {
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: UUID().uuidString)
    let manager = TemporaryFileManager(root: root)
    let files = ProjectFileStore(fileManager: manager)
    let terrain = TerrainLayout(
        seed: 7, shoreline: [], gridWidth: 2, gridHeight: 2,
        elevations: [32768, 32768, 32768, 32768]
    )
    try files.save(RoadProject(name: "Store smoke", terrain: terrain, roads: roads, interchanges: interchanges))
    let store = RoadDocumentStore(fileStore: files)
    try check(store.terrainGenerationState == .idle, "fixture must not regenerate terrain")
    return (store, files, manager)
}

func road(_ source: UUID = UUID(), _ start: RoadPoint, _ end: RoadPoint) -> RoadSegment {
    RoadSegment(kind: .street, points: [start, end], sourceRoadID: source)
}

@MainActor
func verifyTransactions() throws {
    let horizontal = UUID(), vertical = UUID(), stable = UUID()
    let (store, files, manager) = try fixture([
        road(horizontal, .init(x: 0, y: 50), .init(x: 100, y: 50)),
        road(vertical, .init(x: 50, y: 0), .init(x: 50, y: 100)),
        road(stable, .init(x: 200, y: 0), .init(x: 300, y: 0)),
    ])
    try check(store.project.roads.filter { $0.sourceRoadID == horizontal }.count == 2, "crossing must create split siblings")
    let original = store.project
    let stableRoads = original.roads.filter { $0.sourceRoadID == stable }
    store.activateSelection()
    store.setSelectedSourceRoadIDs([horizontal, vertical])
    try check(store.deleteSelectedRoads(), "selected deletion succeeds")
    try check(store.project.roads == stableRoads, "all selected split siblings removed; unrelated road unchanged")
    try check(store.selectedSourceRoadIDs.isEmpty && store.canUndo && !store.canRedo, "deletion clears selection and creates one undo")
    try check(try files.loadAll().first?.roads == stableRoads, "deletion persisted")
    store.undo()
    try check(store.project == original && !store.canUndo && store.canRedo, "single undo restores entire edit")
    store.redo()
    try check(store.project.roads == stableRoads && store.canUndo && !store.canRedo, "single redo restores deletion")
    try check(RoadDocumentStore(fileStore: files).project.roads == stableRoads, "fresh store reload sees deletion")
    store.undo()
    let beforeNoOp = store.project
    try check(!store.deleteSelectedRoads(), "empty selection is a no-op")
    try check(store.project == beforeNoOp && !store.canUndo && store.canRedo, "no-op preserves redo and creates no undo")

    store.setSelectedSourceRoadIDs([horizontal])
    try check(store.deleteSelectedRoads(), "prepare first history edit")
    store.setSelectedSourceRoadIDs([vertical])
    try check(store.deleteSelectedRoads(), "prepare second history edit")
    store.undo()
    try check(store.canUndo && store.canRedo, "prepare both history directions")
    store.setSelectedSourceRoadIDs([vertical])
    let beforeFailure = store.project
    manager.failResolution = true
    try check(!store.deleteSelectedRoads(), "save failure rejects deletion")
    try check(store.project == beforeFailure && store.selectedSourceRoadIDs == [vertical], "failed save preserves document and selection")
    try check(store.canUndo && store.canRedo && store.saveErrorMessage != nil, "failed save preserves both histories and reports failure")
    manager.failResolution = false
    try check(try files.loadAll().first?.roads == beforeFailure.roads, "failed save preserves persisted geometry")
    store.redo()
    try check(store.project.roads == stableRoads, "failed deletion leaves redo entry intact")
    store.undo()
    store.undo()
    try check(store.project == original && !store.canUndo, "failed deletion leaves original undo history intact")
    print("PASS selected split sources, stable roads, single undo/redo, reload, no-op, failed-save atomicity")
}

@MainActor
func verifyInterchangeAndEraser() throws {
    let upper = UUID(), lower = UUID(), ramp = UUID()
    let roads = [
        RoadSegment(id: upper, kind: .motorway, level: .elevated, points: [.init(x: 0, y: 0), .init(x: 100, y: 0)]),
        RoadSegment(id: lower, kind: .arterial, points: [.init(x: 50, y: -50), .init(x: 50, y: 50)]),
        RoadSegment(id: ramp, kind: .street, level: .elevated, points: [.init(x: 20, y: 0), .init(x: 30, y: 20), .init(x: 40, y: 0)]),
    ]
    let interchange = RoadInterchange(
        name: "Smoke interchange",
        anchor: .init(upperSourceRoadID: upper, lowerSourceRoadID: lower, lastKnownPoint: .init(x: 50, y: 0)),
        ramps: [.init(id: ramp,
            start: .init(hostSourceRoadID: upper, normalizedChainage: 0.2, lastKnownPoint: .init(x: 20, y: 0), level: .elevated),
            end: .init(hostSourceRoadID: upper, normalizedChainage: 0.4, lastKnownPoint: .init(x: 40, y: 0), level: .elevated))]
    )
    let (store, files, _) = try fixture(roads, interchanges: [interchange])
    let original = store.project
    try check(RoadInterchangeValidator.evaluate(interchanges: original.interchanges, in: original.roadNetwork).isEmpty, "interchange fixture must be valid")
    store.setSelectedSourceRoadIDs([upper])
    try check(!store.deleteSelectedRoads(), "host deletion is rejected")
    try check(store.project == original && store.selectedSourceRoadIDs == [upper] && !store.canUndo, "rejected host deletion is atomic")
    try check(try files.loadAll().first?.interchanges == original.interchanges, "rejected host keeps persisted interchange")
    store.setSelectedSourceRoadIDs([ramp])
    try check(store.deleteSelectedRoads(), "ramp deletion succeeds")
    try check(store.project.interchanges.isEmpty && !store.project.roads.contains { $0.sourceRoadID == ramp }, "ramp deletion clears declaration and geometry")
    store.undo()
    try check(store.project == original, "undo restores ramp and declaration")
    store.eraseRoads(.init(points: [.init(x: 30, y: 20)], radius: 2,
        eligibleRoadIDs: Set(store.project.roads.filter { $0.sourceRoadID == ramp }.map(\.id)), mode: .wholeRoad))
    try check(store.project.interchanges.isEmpty && !store.project.roads.contains { $0.sourceRoadID == ramp }, "shared eraser still removes ramp and declaration")
    store.undo()
    try check(store.project == original, "eraser remains undoable")

    let source = UUID()
    let (local, _, _) = try fixture([road(source, .init(x: 0, y: 0), .init(x: 100, y: 0))])
    local.eraseRoads(.init(points: [.init(x: 50, y: 0)], radius: 5,
        eligibleRoadIDs: Set(local.project.roads.map(\.id)), mode: .local))
    try check(local.project.roads.count == 2 && local.project.roads.allSatisfy { $0.sourceRoadID == source }, "local eraser keeps two surviving siblings")
    print("PASS valid interchange, rejected host deletion, ramp cleanup, whole-road and local eraser")
}

@MainActor
func verifyPlayableInterchange() throws {
    let (store, files, _) = try fixture([])
    let originalID = store.project.id
    store.createInterchangePracticeMap()
    try check(store.project.id != originalID && store.projects.contains { $0.id == originalID }, "practice preserves existing project")
    try check(store.project.realWorldMap == nil && store.isEditingInterchange, "practice uses generated terrain and interchange tool")
    try check(store.selectedInterchangeCrossing != nil, "practice has selected grade-separated crossing")
    try check(store.prepareQuickRamp(), "quick ramp preview succeeds: \(store.pendingRampError ?? "")")
    try check(!store.isPendingRampHandDrawn, "quick ramp is not hand drawn")
    let first = store.pendingRampPlan!.ramp
    try check(store.prepareQuickRamp(cycle: true), "can choose another connection side")
    try check(store.pendingRampPlan!.ramp.end.lastKnownPoint != first.end.lastKnownPoint, "cycling changes ramp terminal")
    try check(store.commitRampDraft(), "quick ramp commits: \(store.pendingRampError ?? "")")
    try check(store.project.interchanges.count == 1 && store.project.interchanges[0].ramps.count == 1, "ramp stored with declaration")
    try check(store.selectedRampID != nil && store.canUndo, "committed ramp is selected and undoable")
    let committed = store.project
    store.undo()
    try check(store.project.interchanges.isEmpty, "undo removes whole ramp")
    store.redo()
    try check(store.project == committed, "redo restores exact ramp")
    guard var reloaded = try files.loadAll().first(where: { $0.id == committed.id }) else {
        throw NSError(domain: "saved practice project missing", code: 1)
    }
    // ProjectFileStore's ISO 8601 dates have second precision.
    try check(abs(reloaded.updatedAt.timeIntervalSince(committed.updatedAt)) < 1, "saved timestamp remains within serialization precision")
    reloaded.createdAt = committed.createdAt
    reloaded.updatedAt = committed.updatedAt
    try check(reloaded == committed, "entire ramp project persists apart from timestamp precision")
    let reopened = RoadDocumentStore(fileStore: files)
    reopened.selectProject(id: committed.id)
    try check(reopened.terrainGenerationState == .idle && reopened.project.terrain == committed.terrain,
        "reopening practice keeps terrain attached instead of regenerating it")
    print("PASS practice, preview, side selection, commit, undo, redo and persistence")
}

@MainActor
func verifyDefaultScale() throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1]).appending(path: UUID().uuidString)
    let manager = TemporaryFileManager(root: root)
    let files = ProjectFileStore(fileManager: manager)
    let store = RoadDocumentStore(fileStore: files)
    try check(store.project.mapScale.metersPerPoint == 62.5, "first placeholder project uses 62.5 meters per point")
    store.deleteCurrentProject()
    try check(store.project.mapScale.metersPerPoint == 62.5, "recreated project uses 62.5 meters per point")
    print("PASS default map scale consistency")
}

do {
    try verifyDefaultScale()
    try verifyTransactions()
    try verifyInterchangeAndEraser()
    try verifyPlayableInterchange()
    print("PASS all RoadDocumentStore smoke checks")
} catch {
    FileHandle.standardError.write(Data("FAIL \(error)\n".utf8))
    exit(1)
}
