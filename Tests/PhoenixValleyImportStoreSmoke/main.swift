import Foundation
import PhoenixValleyCore

final class ImportTestFileManager: FileManager, @unchecked Sendable {
    let root: URL
    var rejectsSave = false
    init(root: URL) { self.root = root; super.init() }
    override var ubiquityIdentityToken: (any NSCoding & NSCopying & NSObjectProtocol)? { nil }
    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        guard directory == .applicationSupportDirectory, !rejectsSave else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return root
    }
}

func check(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    if try !condition() { throw NSError(domain: message, code: 1) }
}

@MainActor
func verifyImportTransaction() throws {
    let manager = ImportTestFileManager(root: URL(fileURLWithPath: CommandLine.arguments[1]))
    let files = ProjectFileStore(fileManager: manager)
    let original = RoadProject(name: "Existing map", terrain: .init(seed: 1, shoreline: [],
        gridWidth: 2, gridHeight: 2, elevations: [32768,32768,32768,32768], scenario: .continent),
        roads: [.init(kind: .street, points: [.init(x: 100,y: 100), .init(x: 200,y: 100)])])
    try files.save(original)
    let store = RoadDocumentStore(fileStore: files)
    let loadedOriginal = store.project
    store.setSelectedSourceRoadIDs(Set(store.project.roads.map(\.sourceRoadID)))
    try check(store.changeSelectedRoadSpeedLimit(to: 30), "prepare undoable edit")
    let before = store.project
    let selected = store.selectedSourceRoadIDs
    let data = Data("""
    <kml><Placemark><Polygon><outerBoundaryIs><LinearRing>
    <coordinates>121,25 121.001,25 121.001,25.001 121,25.001 121,25</coordinates>
    </LinearRing></outerBoundaryIs></Polygon></Placemark></kml>
    """.utf8)
    let imported = try GeoMapImporter.importMap(data: data, format: .kml,
        options: .init(name: "Imported region")).project
    manager.rejectsSave = true
    try check(!store.importRealWorldProject(imported), "failed write rejects import")
    try check(store.project == before && store.selectedSourceRoadIDs == selected,
        "failed import preserves current project and selection")
    try check(store.canUndo && !store.canRedo, "failed import preserves edit history")
    manager.rejectsSave = false
    try check(try files.loadAll().count == 1, "failed import creates no project file")
    store.undo()
    try check(store.project == loadedOriginal, "prior undo remains usable after rejected import")
    try check(store.importRealWorldProject(imported), "successful import is committed")
    try check(store.project.realWorldMap == imported.realWorldMap && store.project.roads.isEmpty,
        "polygon-only map remains real-world data")
    let scale = store.project.mapScale
    store.setMapScale(.init(metersPerPoint: 5))
    try check(store.project.mapScale == scale, "georeferenced polygon-only scale is locked")
    try check(store.terrainGenerationState == .idle, "import never generates fictional terrain")
    let reloaded = RoadDocumentStore(fileStore: files)
    try check(reloaded.project.id == imported.id && reloaded.terrainGenerationState == .idle,
        "process reload retains imported map without generating terrain")
    try check(reloaded.project.realWorldMap == imported.realWorldMap,
        "reload retains source geometry and provenance")
    reloaded.selectProject(id: original.id)
    reloaded.selectProject(id: imported.id)
    try check(reloaded.terrainGenerationState == .idle, "switching back does not regenerate imported terrain")
    print("PASS import save failure, history, new-map persistence, scale lock, reload and no terrain replacement")
}

do { try verifyImportTransaction() }
catch {
    FileHandle.standardError.write(Data("FAIL \(error)\n".utf8))
    exit(1)
}
