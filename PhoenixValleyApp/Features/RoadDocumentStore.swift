import Foundation
import Observation
import PhoenixValleyCore

enum TerrainGenerationState: Equatable {
    case idle
    case generating(
        targetName: String,
        progress: TerrainGenerationProgress,
        usedCache: Bool
    )
    case failed(message: String)

    var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}

enum RoadEditorTool: Equatable {
    case draw
    case erase
    case select
    case interchange
}

@MainActor
@Observable
final class RoadDocumentStore {
    private(set) var project: RoadProject
    private(set) var projects: [RoadProject]
    private(set) var groups: [ProjectGroup]
    var selectedKind: RoadKind = .arterial
    var selectedLevel: RoadLevel = .ground
    var eraserMode: RoadEraseMode = .wholeRoad
    private(set) var activeTool: RoadEditorTool = .draw
    private(set) var selectedSourceRoadIDs: Set<UUID> = []
    private(set) var selectedInterchangeCrossingID: UUID?
    private(set) var selectedRampID: UUID?
    private(set) var isAwaitingRampDrawing = false
    private(set) var pendingRampPlan: RoadRampPlan?
    private(set) var pendingRampError: String?
    var rampDirection: RoadDirection = .forward
    private var quickRampVariant = 0
    var correctionStrength = 0.6
    private(set) var saveErrorMessage: String?
    private(set) var terrainGenerationState: TerrainGenerationState = .idle

    private var undoStack: [RoadProject] = []
    private var redoStack: [RoadProject] = []
    private let fileStore: ProjectFileStore
    private let terrainCache: TerrainGenerationCache
    @ObservationIgnored private var terrainGenerationTask: Task<Void, Never>?
    @ObservationIgnored private var terrainGenerationRequestID: UUID?

    init(
        fileStore: ProjectFileStore = ProjectFileStore(),
        terrainCache: TerrainGenerationCache = .shared
    ) {
        self.fileStore = fileStore
        self.terrainCache = terrainCache
        do {
            groups = try fileStore.loadGroups()
        } catch {
            groups = []
            saveErrorMessage = "分组信息未能载入：\(error.localizedDescription)"
        }

        let loadResult: ProjectLibraryLoadResult
        let libraryLoadSucceeded: Bool
        do {
            loadResult = try fileStore.loadLibrary()
            libraryLoadSucceeded = true
        } catch {
            loadResult = ProjectLibraryLoadResult(projects: [], diagnostics: [])
            libraryLoadSucceeded = false
            saveErrorMessage = "项目库未能载入：\(error.localizedDescription)"
        }

        let upgradedProjects = loadResult.projects.map(Self.upgraded)
        let createdPlaceholder: Bool
        if let saved = upgradedProjects.first {
            projects = upgradedProjects
            project = saved
            createdPlaceholder = false
        } else {
            let terrain = Self.placeholderTerrain(seed: 20260722)
            let initialProject = RoadProject(name: "我的设计地图", terrain: terrain,
                mapScale: MapScale(metersPerPoint: 20))
            project = initialProject
            projects = [initialProject]
            createdPlaceholder = true
        }

        do {
            for (original, upgraded) in zip(loadResult.projects, upgradedProjects)
            where original.formatVersion != upgraded.formatVersion {
                try fileStore.save(upgraded)
            }
            if libraryLoadSucceeded,
               loadResult.projects.isEmpty,
               loadResult.diagnostics.isEmpty {
                try fileStore.save(project)
            }
        } catch {
            saveErrorMessage = "项目升级结果未能保存：\(error.localizedDescription)"
        }

        if !loadResult.diagnostics.isEmpty {
            let details = loadResult.diagnostics
                .compactMap(\.errorDescription)
                .joined(separator: "\n")
            saveErrorMessage = [saveErrorMessage, details]
                .compactMap { $0 }
                .joined(separator: "\n")
        }

        let shouldMaterializePlaceholder = createdPlaceholder
            && project.realWorldMap == nil
            && libraryLoadSucceeded
            && loadResult.diagnostics.isEmpty
        let shouldRegenerateLoadedTerrain = !createdPlaceholder
            && project.realWorldMap == nil
            && Self.needsTerrainRegeneration(project.terrain)
        if shouldMaterializePlaceholder || shouldRegenerateLoadedTerrain {
            scheduleTerrainGeneration(
                seed: project.terrain.seed,
                scenario: createdPlaceholder ? .continent : project.terrain.scenario,
                purpose: .replaceExisting(projectID: project.id, targetName: project.name)
            )
        }
    }

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var isErasing: Bool { activeTool == .erase }
    var isSelecting: Bool { activeTool == .select }
    var isEditingInterchange: Bool { activeTool == .interchange }
    var selectedInterchangeCrossing: RoadRelation? {
        guard let selectedInterchangeCrossingID else { return nil }
        return project.roadNetwork.relations.first {
            $0.id == selectedInterchangeCrossingID
                && $0.kind == .gradeSeparatedCrossing
        }
    }
    var selectedRoadKind: RoadKind? {
        let kinds = Set(
            project.roads
                .filter { selectedSourceRoadIDs.contains($0.sourceRoadID) }
                .map(\.kind)
        )
        return kinds.count == 1 ? kinds.first : nil
    }
    var selectedRoadSpeedLimit: Double? {
        let rules = selectedRoadTrafficRules
        guard !rules.isEmpty else { return nil }
        let values = Set(rules.map(\.speedLimitKilometersPerHour))
        return values.count == 1 ? values.first : nil
    }
    var selectedRoadTrafficAccess: RoadTrafficAccess? {
        let rules = selectedRoadTrafficRules
        guard !rules.isEmpty else { return nil }
        let values = Set(rules.map(\.access))
        return values.count == 1 ? values.first : nil
    }
    var pendingStructureReview: RoadStructureReviewRecord? {
        project.structureReviews.first { $0.status == .pending }
    }
    var layerConflicts: [RoadLayerConflict] {
        project.roadNetwork.layerConflicts
    }
    var engineeringIssues: [RoadEngineeringConstraintIssue] {
        project.engineeringStructures.flatMap(\.report.issues)
    }
    var constructionFeasibility: RoadConstructionFeasibilityReport {
        RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: project.roads,
            terrain: project.terrain,
            mapScale: project.mapScale
        )
    }
    var constructionIssues: [RoadConstructionIssue] {
        constructionFeasibility.issues
    }
    var alertTitle: String {
        if saveErrorMessage?.contains("道路交通规则") == true {
            return "道路交通规则"
        }
        if saveErrorMessage?.contains("匝道") == true
            || saveErrorMessage?.contains("立交连接") == true
            || saveErrorMessage?.contains("现有立交") == true {
            return "立交与匝道"
        }
        if saveErrorMessage?.hasPrefix("无法应用结构方案") == true
            || saveErrorMessage?.hasPrefix("无法添加道路：工程约束") == true
            || saveErrorMessage?.hasPrefix("无法编辑道路：工程约束") == true {
            return "道路工程约束"
        }
        if saveErrorMessage?.hasPrefix("无法添加道路") == true
            || saveErrorMessage?.hasPrefix("无法编辑道路：层级冲突") == true {
            return "道路层级冲突"
        }
        return "项目文件需要处理"
    }

    func activateDrawing(kind: RoadKind? = nil) {
        if let kind {
            selectedKind = kind
        }
        activeTool = .draw
        selectedSourceRoadIDs.removeAll()
        resetInterchangeEditingState()
    }

    func activateEraser() {
        activeTool = .erase
        selectedSourceRoadIDs.removeAll()
        resetInterchangeEditingState()
    }

    func activateSelection() {
        activeTool = .select
        resetInterchangeEditingState()
    }

    func activateInterchange() {
        activeTool = .interchange
        selectedSourceRoadIDs.removeAll()
        resetInterchangeEditingState()
    }

    func setSelectedSourceRoadIDs(_ sourceRoadIDs: Set<UUID>) {
        let availableSourceRoadIDs = Set(project.roads.map(\.sourceRoadID))
        selectedSourceRoadIDs = sourceRoadIDs.intersection(availableSourceRoadIDs)
    }

    func clearRoadSelection() {
        selectedSourceRoadIDs.removeAll()
    }

    func selectInterchangeCrossing(id: UUID?) {
        cancelRampDraft()
        selectedRampID = nil
        guard let id else {
            selectedInterchangeCrossingID = nil
            return
        }
        guard project.roadNetwork.relations.contains(where: {
            $0.id == id
                && $0.kind == .gradeSeparatedCrossing
                && $0.secondaryPoint == nil
        }) else {
            pendingRampError = "请选择一个单点上下分离交叉口。"
            selectedInterchangeCrossingID = nil
            return
        }
        selectedInterchangeCrossingID = id
        pendingRampError = nil
    }

    func selectInterchangeCrossing(_ relation: RoadRelation?) {
        selectInterchangeCrossing(id: relation?.id)
    }

    func createInterchangePracticeMap() {
        var practice = RoadProject(name: "立交练习场", terrain: TerrainLayout(seed: 0, shoreline: [],
            gridWidth: 2, gridHeight: 2, elevations: [32768, 32768, 32768, 32768], scenario: .continent))
        practice.roads = [
            RoadSegment(kind: .motorway, level: .elevated, structure: .elevated,
                points: [.init(x: 200, y: 600), .init(x: 1400, y: 600)]),
            RoadSegment(kind: .arterial, points: [.init(x: 800, y: 100), .init(x: 800, y: 1100)]),
        ]
        guard importProject(practice) else { return }
        activateInterchange()
        selectInterchangeCrossing(id: project.roadNetwork.relations.first {
            $0.kind == .gradeSeparatedCrossing && $0.secondaryPoint == nil
        }?.id)
    }

    /// Builds a tangent quarter-turn from the selected hosts, using the same
    /// planner and commit validation as a hand-drawn ramp.
    @discardableResult
    func prepareQuickRamp(cycle: Bool = false) -> Bool {
        guard let crossing = selectedInterchangeCrossing else { return false }
        if cycle { quickRampVariant = (quickRampVariant + 1) % 4 }
        else { quickRampVariant = 0 }
        let center = crossing.point
        func terminal(sourceID: UUID, sign: Double) -> RoadPoint? {
            let hosts = project.roads.filter { $0.sourceRoadID == sourceID }
            let segments = hosts.flatMap { road in Array(zip(road.points, road.points.dropFirst())) }
            guard let segment = segments.min(by: { a, b in
                func distance(_ edge: (RoadPoint, RoadPoint)) -> Double {
                    let dx = edge.1.x-edge.0.x, dy = edge.1.y-edge.0.y
                    let lengthSquared = dx*dx+dy*dy
                    let t = lengthSquared > 0 ? min(1, max(0,
                        ((center.x-edge.0.x)*dx+(center.y-edge.0.y)*dy)/lengthSquared)) : 0
                    return center.distance(to: .init(x: edge.0.x+t*dx, y: edge.0.y+t*dy))
                }
                return distance(a) < distance(b)
            }) else { return nil }
            let dx = segment.1.x-segment.0.x, dy = segment.1.y-segment.0.y
            let length = hypot(dx, dy)
            guard length > 0 else { return nil }
            let reach = project.mapScale.canvasDistance(forMeters: 180)
            return RoadSourceGeometry.nearestSource(toCanvasPoint:
                .init(x: center.x+sign*reach*dx/length, y: center.y+sign*reach*dy/length),
                maximumDistanceMeters: 200, mapScale: project.mapScale, in: hosts)?.nearestCanvasPoint
        }
        guard let start = terminal(sourceID: crossing.firstRoadID, sign: quickRampVariant < 2 ? -1 : 1),
              let end = terminal(sourceID: crossing.secondRoadID, sign: quickRampVariant % 2 == 0 ? -1 : 1)
        else {
            pendingRampError = "主线长度不足，请手绘匝道或延长主线。"
            return false
        }
        let points = (0...32).map { index -> RoadPoint in
            let t = Double(index)/32, u = 1-t
            return .init(x: u*u*start.x+2*u*t*center.x+t*t*end.x,
                         y: u*u*start.y+2*u*t*center.y+t*t*end.y)
        }
        if selectedKind == .railway { selectedKind = .arterial }
        beginRampDrawing()
        return prepareRampDraft(points)
    }

    func beginRampDrawing() {
        pendingRampPlan = nil
        pendingRampError = nil
        guard selectedInterchangeCrossing != nil else {
            isAwaitingRampDrawing = false
            pendingRampError = "请先选择一个上下分离交叉口。"
            return
        }
        guard selectedKind != .railway else {
            isAwaitingRampDrawing = false
            pendingRampError = "匝道不能使用铁路类型。"
            return
        }
        selectedRampID = nil
        isAwaitingRampDrawing = true
    }

    @discardableResult
    func prepareRampDraft(_ rawPoints: [RoadPoint]) -> Bool {
        pendingRampPlan = nil
        pendingRampError = nil
        guard isAwaitingRampDrawing,
              let crossing = selectedInterchangeCrossing
        else {
            pendingRampError = "当前没有待绘制的匝道。"
            return false
        }
        guard selectedKind != .railway else {
            pendingRampError = "匝道不能使用铁路类型。"
            return false
        }

        let configuration = StrokeProcessingConfiguration(
            minimumSampleDistance: 1.2,
            smoothingPasses: correctionStrength < 0.35 ? 1 : 2,
            simplificationTolerance: 0.8 + correctionStrength * 3.2,
            endpointSnapRadius: 0,
            angleSnapTolerance: 0
        )
        let points = StrokeProcessor.process(
            rawPoints,
            existingRoads: [],
            configuration: configuration
        )
        do {
            pendingRampPlan = try RoadRampPlanner.plan(
                points: points,
                crossing: crossing,
                roads: project.roads,
                existingInterchanges: project.interchanges,
                kind: selectedKind,
                direction: rampDirection,
                mapScale: project.mapScale
            )
            return true
        } catch let error as RoadRampPlannerError {
            pendingRampError = error.localizedDescription
            return false
        } catch {
            pendingRampError = error.localizedDescription
            return false
        }
    }

    func cancelRampDraft() {
        isAwaitingRampDrawing = false
        pendingRampPlan = nil
        pendingRampError = nil
    }

    @discardableResult
    func updatePendingRamp(
        direction: RoadDirection,
        kind: RoadKind
    ) -> Bool {
        guard kind != .railway else {
            pendingRampError = "匝道不能使用铁路类型。"
            return false
        }
        rampDirection = direction
        selectedKind = kind
        guard var plan = pendingRampPlan else { return false }

        let hostPriorities = project.roads.compactMap { road -> RoadPriority? in
            let hostIDs: Set<UUID> = [
                plan.ramp.start.hostSourceRoadID,
                plan.ramp.end.hostSourceRoadID,
            ]
            return hostIDs.contains(road.sourceRoadID) ? road.priority : nil
        }
        let priority = hostPriorities.reduce(kind.defaultPriority, min)
        plan.ramp.direction = direction
        for rampIndex in plan.interchange.ramps.indices
        where plan.interchange.ramps[rampIndex].id == plan.ramp.id {
            plan.interchange.ramps[rampIndex].direction = direction
        }
        for segmentIndex in plan.roadSegments.indices {
            plan.roadSegments[segmentIndex].direction = direction
            plan.roadSegments[segmentIndex].kind = kind
            plan.roadSegments[segmentIndex].priority = priority
        }
        pendingRampPlan = plan
        pendingRampError = nil
        return true
    }

    @discardableResult
    func commitRampDraft() -> Bool {
        guard let plan = pendingRampPlan else {
            pendingRampError = "请先完成一条有效的匝道草图。"
            return false
        }
        guard plan.roadSegments.allSatisfy({ $0.kind != .railway }) else {
            pendingRampError = "匝道不能使用铁路类型。"
            return false
        }

        var candidate = project
        if let index = candidate.interchanges.firstIndex(where: {
            $0.id == plan.interchange.id
        }) {
            candidate.interchanges[index] = plan.interchange
        } else {
            candidate.interchanges.append(plan.interchange)
        }
        candidate.roadNetwork = RoadNetwork.rebuilding(
            from: candidate.roads + plan.roadSegments,
            interchanges: candidate.interchanges
        ).network

        let affectedSourceRoadIDs = Set(
            plan.roadSegments.map(\.sourceRoadID)
                + [
                    plan.ramp.start.hostSourceRoadID,
                    plan.ramp.end.hostSourceRoadID,
                ]
        )
        guard validateInterchanges(
            in: candidate,
            prefix: "无法添加匝道"
        ) else {
            pendingRampError = saveErrorMessage
            return false
        }
        guard validateIntroducedLayerConflicts(
            in: candidate.roadNetwork,
            affecting: affectedSourceRoadIDs,
            prefix: "无法添加匝道"
        ) else {
            pendingRampError = saveErrorMessage
            return false
        }

        let engineering = RoadEngineeringPlanner.evaluate(
            roads: plan.roadSegments,
            terrain: candidate.terrain,
            mapScale: candidate.mapScale
        )
        guard !engineering.hasErrors else {
            saveErrorMessage = engineeringErrorMessage(
                prefix: "无法添加匝道：工程约束不满足",
                issues: engineering.issues
            )
            pendingRampError = saveErrorMessage
            return false
        }
        let construction = RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: plan.roadSegments,
            terrain: candidate.terrain,
            mapScale: candidate.mapScale
        )
        guard construction.isFeasible else {
            saveErrorMessage = constructionErrorMessage(
                prefix: "无法添加匝道：道路不可施工",
                issues: construction.issues
            )
            pendingRampError = saveErrorMessage
            return false
        }

        let rampSourceRoadID = plan.ramp.sourceRoadID
        candidate.engineeringStructures.removeAll {
            $0.sourceRoadID == rampSourceRoadID
        }
        candidate.engineeringStructures.append(contentsOf: engineering.structures)
        for kind in Set(plan.roadSegments.map(\.kind)) {
            candidate.layerVisibility.setVisible(true, for: kind)
        }
        candidate.updatedAt = .now

        guard commitPersistedCandidate(candidate) else {
            pendingRampError = saveErrorMessage
            return false
        }
        selectedRampID = rampSourceRoadID
        rampDirection = plan.ramp.direction
        isAwaitingRampDrawing = false
        pendingRampPlan = nil
        pendingRampError = nil
        return true
    }

    func selectRamp(id: UUID?) {
        cancelRampDraft()
        guard let id,
              let selected = project.interchanges
                .lazy
                .flatMap(\.ramps)
                .first(where: { $0.id == id })
        else {
            selectedRampID = nil
            return
        }
        selectedRampID = id
        rampDirection = selected.direction
        if let interchange = project.interchanges.first(where: {
            $0.ramps.contains { $0.id == id }
        }), let relation = project.roadNetwork.relations.first(where: {
            $0.kind == .gradeSeparatedCrossing
                && $0.upperRoadID == interchange.anchor.upperSourceRoadID
                && $0.lowerRoadID == interchange.anchor.lowerSourceRoadID
        }) {
            selectedInterchangeCrossingID = relation.id
        }
    }

    func selectRamp(_ id: UUID?) {
        selectRamp(id: id)
    }

    @discardableResult
    func changeSelectedRampDirection(to direction: RoadDirection) -> Bool {
        guard let selectedRampID,
              let interchangeIndex = project.interchanges.firstIndex(where: {
                  $0.ramps.contains { $0.id == selectedRampID }
              }),
              let rampIndex = project.interchanges[interchangeIndex].ramps.firstIndex(
                  where: { $0.id == selectedRampID }
              ),
              project.interchanges[interchangeIndex].ramps[rampIndex].direction != direction
        else {
            rampDirection = direction
            return false
        }

        var candidate = project
        candidate.interchanges[interchangeIndex].ramps[rampIndex].direction = direction
        var roads = candidate.roads
        for index in roads.indices where roads[index].sourceRoadID == selectedRampID {
            roads[index].direction = direction
        }
        candidate.roadNetwork = RoadNetwork.rebuilding(
            from: roads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法修改匝道方向"
        ) else { return false }
        candidate.updatedAt = .now
        guard commitPersistedCandidate(candidate) else { return false }
        rampDirection = direction
        return true
    }

    @discardableResult
    func changeSelectedRampKind(to kind: RoadKind) -> Bool {
        guard kind != .railway else {
            saveErrorMessage = "无法修改匝道类型：匝道不能使用铁路类型。"
            return false
        }
        guard let selectedRampID,
              let ramp = project.interchanges
                .lazy
                .flatMap(\.ramps)
                .first(where: { $0.id == selectedRampID })
        else { return false }
        let currentRoads = project.roads.filter {
            $0.sourceRoadID == selectedRampID
        }
        guard !currentRoads.isEmpty,
              currentRoads.contains(where: { $0.kind != kind })
        else { return false }

        let hostPriorities = project.roads.compactMap { road -> RoadPriority? in
            let hostIDs: Set<UUID> = [
                ramp.start.hostSourceRoadID,
                ramp.end.hostSourceRoadID,
            ]
            return hostIDs.contains(road.sourceRoadID) ? road.priority : nil
        }
        let priority = hostPriorities.reduce(kind.defaultPriority, min)
        var roads = project.roads
        for index in roads.indices where roads[index].sourceRoadID == selectedRampID {
            roads[index].kind = kind
            roads[index].priority = priority
        }

        var candidate = project
        candidate.roadNetwork = RoadNetwork.rebuilding(
            from: roads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法修改匝道类型"
        ) else { return false }
        guard validateIntroducedLayerConflicts(
            in: candidate.roadNetwork,
            affecting: [selectedRampID],
            prefix: "无法修改匝道类型"
        ) else { return false }

        let editedRoads = candidate.roads.filter {
            $0.sourceRoadID == selectedRampID
        }
        let engineering = RoadEngineeringPlanner.evaluate(
            roads: editedRoads,
            terrain: candidate.terrain,
            mapScale: candidate.mapScale
        )
        guard !engineering.hasErrors else {
            saveErrorMessage = engineeringErrorMessage(
                prefix: "无法修改匝道类型：工程约束不满足",
                issues: engineering.issues
            )
            return false
        }
        let construction = RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: editedRoads,
            terrain: candidate.terrain,
            mapScale: candidate.mapScale
        )
        guard construction.isFeasible else {
            saveErrorMessage = constructionErrorMessage(
                prefix: "无法修改匝道类型：道路不可施工",
                issues: construction.issues
            )
            return false
        }
        candidate.engineeringStructures.removeAll {
            $0.sourceRoadID == selectedRampID
        }
        candidate.engineeringStructures.append(contentsOf: engineering.structures)
        candidate.layerVisibility.setVisible(true, for: kind)
        candidate.updatedAt = .now
        return commitPersistedCandidate(candidate)
    }

    @discardableResult
    func deleteSelectedRamp() -> Bool {
        guard let selectedRampID,
              let interchangeIndex = project.interchanges.firstIndex(where: {
                  $0.ramps.contains { $0.id == selectedRampID }
              })
        else { return false }

        var candidate = project
        candidate.interchanges[interchangeIndex].ramps.removeAll {
            $0.id == selectedRampID
        }
        if candidate.interchanges[interchangeIndex].ramps.isEmpty {
            candidate.interchanges.remove(at: interchangeIndex)
        }
        candidate.roadNetwork = RoadNetwork.removing(
            sourceRoadIDs: [selectedRampID],
            from: candidate.roads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法删除匝道"
        ) else { return false }
        candidate.structureReviews.removeAll {
            Self.review($0, dependsOnAny: [selectedRampID])
        }
        candidate.engineeringStructures.removeAll {
            $0.sourceRoadID == selectedRampID
        }
        candidate.updatedAt = .now
        guard commitPersistedCandidate(candidate) else { return false }
        self.selectedRampID = nil
        cancelRampDraft()
        return true
    }

    func addStroke(
        _ rawPoints: [RoadPoint],
        requestsStructureReview: Bool = false
    ) {
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

        let newRoad = RoadSegment(
            kind: selectedKind,
            level: selectedLevel,
            points: points
        )
        let manualEngineering = selectedLevel == .ground
            ? RoadEngineeringEvaluation(structures: [])
            : RoadEngineeringPlanner.evaluate(
                road: newRoad,
                terrain: project.terrain,
                mapScale: project.mapScale
            )
        guard !manualEngineering.hasErrors else {
            saveErrorMessage = engineeringErrorMessage(
                prefix: "无法添加道路：工程约束不满足",
                issues: manualEngineering.issues
            )
            return
        }
        let topologyResult = RoadNetwork.integrating(
            existingRoads: project.roads,
            newRoad: newRoad,
            interchanges: project.interchanges
        )
        let introducedConflicts = topologyResult.network.layerConflicts.filter {
            $0.roadIDs.contains(newRoad.sourceRoadID)
        }
        guard introducedConflicts.isEmpty else {
            let conflictKinds = Set(introducedConflicts.map(\.kind))
                .map(\.displayName)
                .sorted()
                .joined(separator: "、")
            saveErrorMessage = "无法添加道路：\(conflictKinds)。请调整层级、结构或交汇位置。"
            return
        }
        let interchangeIssues = RoadInterchangeValidator.evaluate(
            interchanges: project.interchanges,
            in: topologyResult.network
        )
        guard interchangeIssues.isEmpty else {
            saveErrorMessage = interchangeErrorMessage(
                prefix: "无法添加道路：会破坏现有立交",
                issues: interchangeIssues
            )
            return
        }

        let structurePlan: AutoStructurePlan? = if selectedLevel == .ground
            && requestsStructureReview {
            AutoStructurePlanner.plan(
                for: newRoad,
                terrain: project.terrain,
                existingRoads: project.roads,
                configuration: .standard.scaledForCanvas(
                    metersPerPoint: project.mapScale.metersPerPoint
                )
            )
        } else {
            nil
        }

        applyProjectEdit { project in
            project.layerVisibility.setVisible(true, for: selectedKind)
            project.roadNetwork = topologyResult.network
            project.engineeringStructures.removeAll {
                $0.sourceRoadID == newRoad.sourceRoadID
            }
            project.engineeringStructures.append(
                contentsOf: manualEngineering.structures
            )
            if let structurePlan,
               !structurePlan.candidates.isEmpty
                    || !structurePlan.crossingSuggestions.isEmpty {
                project.structureReviews.removeAll { $0.id == structurePlan.sourceRoadID }
                project.structureReviews.append(
                    RoadStructureReviewRecord(plan: structurePlan)
                )
            }
        }
    }

    func eraseRoads(_ request: RoadEraseRequest) {
        let result = RoadNetwork.erasing(
            request,
            from: project.roads,
            interchanges: project.interchanges
        )
        guard !result.affectedSourceRoadIDs.isEmpty else { return }
        commitRoadRemoval(
            result.network,
            affectedSourceRoadIDs: result.affectedSourceRoadIDs,
            errorPrefix: "无法擦除道路：会破坏立交连接"
        )
    }

    @discardableResult
    func deleteSelectedRoads() -> Bool {
        let sourceRoadIDs = selectedSourceRoadIDs.intersection(
            Set(project.roads.map(\.sourceRoadID))
        )
        guard !sourceRoadIDs.isEmpty else { return false }
        let result = RoadNetwork.removing(
            sourceRoadIDs: sourceRoadIDs,
            from: project.roads,
            interchanges: project.interchanges
        )
        return commitRoadRemoval(
            result.network,
            affectedSourceRoadIDs: sourceRoadIDs,
            errorPrefix: "无法拆除所选道路：会破坏立交连接"
        )
    }

    @discardableResult
    private func commitRoadRemoval(
        _ network: RoadNetwork,
        affectedSourceRoadIDs: Set<UUID>,
        errorPrefix: String
    ) -> Bool {
        let existingRampSourceRoadIDs = Set(
            project.interchanges.flatMap(\.ramps).map(\.sourceRoadID)
        )
        let erasedRampSourceRoadIDs = affectedSourceRoadIDs
            .intersection(existingRampSourceRoadIDs)

        var candidate = project
        if !erasedRampSourceRoadIDs.isEmpty {
            for interchangeIndex in candidate.interchanges.indices {
                candidate.interchanges[interchangeIndex].ramps.removeAll {
                    erasedRampSourceRoadIDs.contains($0.sourceRoadID)
                }
            }
            candidate.interchanges.removeAll { $0.ramps.isEmpty }
        }
        let finalRoads = network.roadSegments.filter {
            !erasedRampSourceRoadIDs.contains($0.sourceRoadID)
        }
        candidate.roadNetwork = RoadNetwork.rebuilding(
            from: finalRoads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: errorPrefix
        ) else { return false }

        let rebuiltStructures = Self.engineeringStructures(
            for: candidate.roads.filter {
                affectedSourceRoadIDs.contains($0.sourceRoadID)
            },
            terrain: project.terrain,
            mapScale: project.mapScale
        )
        candidate.structureReviews.removeAll {
            Self.review(
                $0,
                dependsOnAny: affectedSourceRoadIDs
            )
        }
        candidate.engineeringStructures.removeAll {
            affectedSourceRoadIDs.contains($0.sourceRoadID)
        }
        candidate.engineeringStructures.append(contentsOf: rebuiltStructures)
        candidate.updatedAt = .now
        guard commitPersistedCandidate(candidate) else { return false }
        if let selectedRampID,
           erasedRampSourceRoadIDs.contains(selectedRampID) {
            self.selectedRampID = nil
        }
        sanitizeRoadSelection()
        return true
    }

    @discardableResult
    func moveSelectedRoads(by canvasOffset: RoadPoint) -> Bool {
        moveRoadSources(selectedSourceRoadIDs, by: canvasOffset)
    }

    @discardableResult
    func moveRoadSources(
        _ sourceRoadIDs: Set<UUID>,
        by canvasOffset: RoadPoint
    ) -> Bool {
        editRoadSources(
            .translate(
                RoadSourceTranslation(
                    sourceRoadIDs: sourceRoadIDs,
                    canvasOffset: canvasOffset
                )
            )
        )
    }

    @discardableResult
    func moveRoadControlPoint(
        sourceRoadID: UUID,
        probeCanvasPoint: RoadPoint,
        destinationCanvasPoint: RoadPoint,
        maximumDistanceMeters: Double
    ) -> Bool {
        editRoadSources(
            .moveControlPoint(
                RoadSourceControlPointMove(
                    sourceRoadID: sourceRoadID,
                    probeCanvasPoint: probeCanvasPoint,
                    destinationCanvasPoint: destinationCanvasPoint,
                    maximumDistanceMeters: maximumDistanceMeters,
                    mapScale: project.mapScale
                )
            )
        )
    }

    @discardableResult
    func changeSelectedRoadKind(to kind: RoadKind) -> Bool {
        editRoadSources(
            .changeKind(
                RoadSourceKindChange(
                    sourceRoadIDs: selectedSourceRoadIDs,
                    kind: kind
                )
            )
        )
    }

    @discardableResult
    func changeSelectedRoadSpeedLimit(to kilometersPerHour: Double) -> Bool {
        updateSelectedRoadTrafficRules { rule in
            rule.speedLimitKilometersPerHour = kilometersPerHour
        }
    }

    @discardableResult
    func changeSelectedRoadTrafficAccess(
        to access: RoadTrafficAccess
    ) -> Bool {
        updateSelectedRoadTrafficRules { rule in
            rule.access = access
        }
    }

    @discardableResult
    private func editRoadSources(_ operation: RoadSourceEditOperation) -> Bool {
        let rampSourceRoadIDs = Set(
            project.interchanges.flatMap(\.ramps).map(\.sourceRoadID)
        )
        if case let .changeKind(request) = operation,
           request.kind == .railway,
           !request.sourceRoadIDs.isDisjoint(with: rampSourceRoadIDs) {
            saveErrorMessage = "无法编辑道路：匝道不能改为铁路类型。"
            return false
        }
        let editedInterchanges = interchanges(
            project.interchanges,
            adjustedFor: operation
        )
        let result = RoadNetwork.editingSources(
            RoadSourceEditTransaction(operations: [operation]),
            in: project.roads,
            interchanges: editedInterchanges
        )
        guard !result.affectedSourceRoadIDs.isEmpty else { return false }

        let existingConflicts = Set(project.roadNetwork.layerConflicts)
        let introducedConflicts = result.network.layerConflicts.filter {
            !$0.roadIDs.isDisjoint(with: result.affectedSourceRoadIDs)
                && !existingConflicts.contains($0)
        }
        guard introducedConflicts.isEmpty else {
            let conflictKinds = Set(introducedConflicts.map(\.kind))
                .map(\.displayName)
                .sorted()
                .joined(separator: "、")
            saveErrorMessage = "无法编辑道路：层级冲突（\(conflictKinds)）。请缩小移动范围或调整控制点。"
            return false
        }

        let editedRoads = result.network.roadSegments.filter {
            result.affectedSourceRoadIDs.contains($0.sourceRoadID)
        }
        let engineering = RoadEngineeringPlanner.evaluate(
            roads: editedRoads,
            terrain: project.terrain,
            mapScale: project.mapScale
        )
        guard !engineering.hasErrors else {
            saveErrorMessage = engineeringErrorMessage(
                prefix: "无法编辑道路：工程约束不满足",
                issues: engineering.issues
            )
            return false
        }

        var candidate = project
        candidate.interchanges = editedInterchanges
        candidate.roadNetwork = result.network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法编辑道路：会破坏立交连接"
        ) else { return false }
        candidate.structureReviews.removeAll {
            Self.review(
                $0,
                dependsOnAny: result.affectedSourceRoadIDs
            )
        }
        candidate.engineeringStructures.removeAll {
            result.affectedSourceRoadIDs.contains($0.sourceRoadID)
        }
        candidate.engineeringStructures.append(contentsOf: engineering.structures)
        for kind in Set(editedRoads.map(\.kind)) {
            candidate.layerVisibility.setVisible(true, for: kind)
        }
        candidate.updatedAt = .now

        guard commitPersistedCandidate(candidate) else { return false }
        setSelectedSourceRoadIDs(selectedSourceRoadIDs)
        return true
    }

    @discardableResult
    func applyStructureReview(
        id: UUID,
        decisions: [AutoStructureDecision]
    ) -> Bool {
        guard let reviewIndex = project.structureReviews.firstIndex(where: {
            $0.id == id && $0.status == .pending
        }) else { return false }

        let review = project.structureReviews[reviewIndex]
        let resolvedSpans = review.plan.resolving(decisions)
        guard !resolvedSpans.isEmpty else { return false }
        let engineering = RoadEngineeringPlanner.evaluate(
            plan: review.plan,
            decisions: decisions,
            terrain: project.terrain,
            mapScale: project.mapScale
        )
        guard !engineering.hasErrors else {
            saveErrorMessage = engineeringErrorMessage(
                prefix: "无法应用结构方案",
                issues: engineering.issues
            )
            return false
        }

        let sourceSegments = project.roads.filter { $0.sourceRoadID == id }
        guard let source = sourceSegments.first else { return false }
        let retainedRoads = project.roads.filter { $0.sourceRoadID != id }
        let replacementRoads: [RoadSegment] = resolvedSpans.enumerated().compactMap {
            index, span in
            guard span.points.count >= 2 else { return nil }
            return RoadSegment(
                id: index == 0 ? id : UUID(),
                kind: span.roadKind,
                level: span.structure.renderLevel,
                structure: span.structure,
                points: span.points,
                direction: source.direction,
                priority: source.priority,
                sourceRoadID: id
            )
        }
        guard !replacementRoads.isEmpty else { return false }
        let construction = RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: replacementRoads,
            terrain: project.terrain,
            mapScale: project.mapScale
        )
        guard construction.isFeasible else {
            saveErrorMessage = constructionErrorMessage(
                prefix: "无法应用结构方案：仍有地面道路或高架不可施工",
                issues: construction.issues
            )
            return false
        }

        var candidate = project
        candidate.roadNetwork = RoadNetwork.rebuilding(
            from: retainedRoads + replacementRoads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法应用结构方案：会破坏立交连接"
        ) else { return false }
        guard validateIntroducedLayerConflicts(
            in: candidate.roadNetwork,
            affecting: [id],
            prefix: "无法应用结构方案"
        ) else { return false }
        candidate.engineeringStructures.removeAll {
            $0.sourceRoadID == id
        }
        candidate.engineeringStructures.append(
            contentsOf: engineering.structures
        )
        guard let index = candidate.structureReviews.firstIndex(where: {
            $0.id == id
        }) else {
            return false
        }
        candidate.structureReviews[index].decisions = decisions
        candidate.structureReviews[index].status = .applied
        candidate.structureReviews[index].reviewedAt = .now
        candidate.updatedAt = .now
        return commitPersistedCandidate(candidate)
    }

    func rejectStructureReview(id: UUID) {
        guard project.structureReviews.contains(where: {
            $0.id == id && $0.status == .pending
        }) else { return }

        applyProjectEdit { project in
            guard let index = project.structureReviews.firstIndex(where: { $0.id == id }) else {
                return
            }
            project.structureReviews[index].decisions = project.structureReviews[index]
                .plan.candidates.map {
                    AutoStructureDecision(candidateID: $0.id, resolution: .reject)
                }
            project.structureReviews[index].status = .rejected
            project.structureReviews[index].reviewedAt = .now
        }
    }

    func discardPendingRoad(id: UUID) {
        guard project.structureReviews.contains(where: {
            $0.id == id && $0.status == .pending
        }) else { return }

        var candidate = project
        candidate.roadNetwork = RoadNetwork.removing(
            sourceRoadIDs: [id],
            from: candidate.roads,
            interchanges: candidate.interchanges
        ).network
        guard validateInterchanges(
            in: candidate,
            prefix: "无法移除待审道路：会破坏立交连接"
        ) else { return }
        candidate.structureReviews.removeAll { $0.id == id }
        candidate.engineeringStructures.removeAll { $0.sourceRoadID == id }
        candidate.updatedAt = .now
        guard commitPersistedCandidate(candidate) else { return }
        sanitizeRoadSelection()
    }

    func undo() {
        guard let previous = undoStack.last else { return }
        do {
            try fileStore.save(previous)
            _ = undoStack.popLast()
            redoStack.append(project)
            publishPersistedProject(previous)
            sanitizeRoadSelection()
            resetInterchangeEditingState()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    func redo() {
        guard let next = redoStack.last else { return }
        do {
            try fileStore.save(next)
            _ = redoStack.popLast()
            undoStack.append(project)
            publishPersistedProject(next)
            sanitizeRoadSelection()
            resetInterchangeEditingState()
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func importRealWorldProject(_ importedProject: RoadProject) -> Bool {
        guard importedProject.realWorldMap != nil else { return false }
        return importProject(importedProject)
    }

    @discardableResult
    private func importProject(_ importedProject: RoadProject) -> Bool {
        var candidate = importedProject
        candidate.groupID = project.groupID
        candidate.updatedAt = .now
        do {
            try fileStore.save(candidate)
            cancelTerrainGeneration()
            publishPersistedProject(candidate)
            clearRoadSelection()
            resetInterchangeEditingState()
            resetHistory()
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    func createNewMap(scenario: TerrainScenario? = nil) {
        let seed = UInt64.random(in: 1...UInt64.max)
        let number = projects.count + 1
        let selectedScenario = scenario ?? .continent
        scheduleTerrainGeneration(
            seed: seed,
            scenario: selectedScenario,
            purpose: .createNew(
                name: "\(selectedScenario.displayName) \(number)",
                groupID: project.groupID
            )
        )
    }

    func cancelTerrainGeneration() {
        terrainGenerationRequestID = nil
        terrainGenerationTask?.cancel()
        terrainGenerationTask = nil
        terrainGenerationState = .idle
    }

    func selectProject(id: UUID) {
        guard id != project.id, let selected = projects.first(where: { $0.id == id }) else { return }
        cancelTerrainGeneration()
        project = selected
        clearRoadSelection()
        resetInterchangeEditingState()
        resetHistory()
        if selected.realWorldMap == nil, Self.needsTerrainRegeneration(selected.terrain) {
            scheduleTerrainGeneration(
                seed: selected.terrain.seed,
                scenario: selected.terrain.scenario,
                purpose: .replaceExisting(projectID: selected.id, targetName: selected.name)
            )
        }
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
            roadNetwork: project.roadNetwork,
            interchanges: project.interchanges,
            trafficRules: project.trafficRules,
            structureReviews: project.structureReviews,
            engineeringStructures: project.engineeringStructures,
            theme: project.theme,
            showsContours: project.showsContours,
            showsGrid: project.showsGrid,
            layerVisibility: project.layerVisibility,
            mapScale: project.mapScale,
            groupID: project.groupID,
            realWorldMap: project.realWorldMap
        )
        project = copy
        projects.append(copy)
        clearRoadSelection()
        resetInterchangeEditingState()
        resetHistory()
        persist()
    }

    func deleteCurrentProject() {
        cancelTerrainGeneration()
        let deleted = project
        do {
            try fileStore.delete(deleted)
            projects.removeAll { $0.id == deleted.id }
            if let next = projects.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
                project = next
            } else {
                let seed = UInt64.random(in: 1...UInt64.max)
                project = RoadProject(
                    name: "新地图",
                    terrain: Self.placeholderTerrain(seed: seed),
                    mapScale: MapScale(metersPerPoint: 20)
                )
                projects = [project]
                scheduleTerrainGeneration(
                    seed: seed,
                    scenario: .continent,
                    purpose: .replaceExisting(projectID: project.id, targetName: project.name)
                )
            }
            clearRoadSelection()
            resetInterchangeEditingState()
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

    func setShowsTerrain(_ value: Bool) {
        guard project.layerVisibility.showsTerrain != value else { return }
        project.layerVisibility.showsTerrain = value
        project.updatedAt = .now
        persist()
    }

    func setShowsHydrology(_ value: Bool) {
        guard project.layerVisibility.showsHydrology != value else { return }
        project.layerVisibility.showsHydrology = value
        project.updatedAt = .now
        persist()
    }

    func setShowsWatersheds(_ value: Bool) {
        guard project.layerVisibility.showsWatersheds != value else { return }
        project.layerVisibility.showsWatersheds = value
        project.updatedAt = .now
        persist()
    }

    func setRoadKind(_ kind: RoadKind, isVisible: Bool) {
        guard project.layerVisibility.isVisible(kind) != isVisible else { return }
        project.layerVisibility.setVisible(isVisible, for: kind)
        project.updatedAt = .now
        persist()
        sanitizeRoadSelection(visibleOnly: true)
    }

    func setMapScale(_ mapScale: MapScale) {
        guard project.realWorldMap == nil, project.roads.isEmpty, project.mapScale != mapScale else { return }
        project.mapScale = mapScale
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
        if case .failed = terrainGenerationState {
            terrainGenerationState = .idle
        }
    }

    private func checkpointForUndo() {
        undoStack.append(project)
        if undoStack.count > 100 {
            undoStack.removeFirst(undoStack.count - 100)
        }
        redoStack.removeAll()
    }

    @discardableResult
    private func commitPersistedCandidate(_ candidate: RoadProject) -> Bool {
        var candidate = candidate
        candidate.trafficRules = candidate.trafficRules.removingStaleReferences(
            in: candidate.roadNetwork
        )
        let trafficIssues = RoadTrafficRuleValidator.evaluate(
            candidate.trafficRules,
            in: candidate.roadNetwork
        )
        guard trafficIssues.isEmpty else {
            saveErrorMessage = [
                "无法保存道路交通规则",
                trafficIssues.prefix(3).map(\.message).joined(separator: "；"),
            ].joined(separator: "：")
            return false
        }
        do {
            try fileStore.save(candidate)
            checkpointForUndo()
            publishPersistedProject(candidate)
            saveErrorMessage = nil
            return true
        } catch {
            saveErrorMessage = error.localizedDescription
            return false
        }
    }

    private func publishPersistedProject(_ persistedProject: RoadProject) {
        project = persistedProject
        if let index = projects.firstIndex(where: { $0.id == persistedProject.id }) {
            projects[index] = persistedProject
        } else {
            projects.append(persistedProject)
        }
        projects.sort { $0.updatedAt > $1.updatedAt }
    }

    private func sanitizeRoadSelection(visibleOnly: Bool = false) {
        let availableSourceRoadIDs = Set(
            project.roads
                .filter {
                    !visibleOnly || project.layerVisibility.isVisible($0.kind)
                }
                .map(\.sourceRoadID)
        )
        selectedSourceRoadIDs.formIntersection(availableSourceRoadIDs)
    }

    private var selectedRoadTrafficRules: [RoadSourceTrafficRule] {
        let selectedRoads = Dictionary(
            project.roads
                .filter { selectedSourceRoadIDs.contains($0.sourceRoadID) }
                .map { ($0.sourceRoadID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return selectedRoads.values.map {
            project.trafficRules.effectiveRule(
                for: $0.sourceRoadID,
                kind: $0.kind
            )
        }
    }

    @discardableResult
    private func updateSelectedRoadTrafficRules(
        _ update: (inout RoadSourceTrafficRule) -> Void
    ) -> Bool {
        let selectedRoads = Dictionary(
            project.roads
                .filter { selectedSourceRoadIDs.contains($0.sourceRoadID) }
                .map { ($0.sourceRoadID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !selectedRoads.isEmpty else { return false }

        var candidate = project
        for road in selectedRoads.values {
            var rule = candidate.trafficRules.effectiveRule(
                for: road.sourceRoadID,
                kind: road.kind
            )
            update(&rule)
            candidate.trafficRules.sourceRules.removeAll {
                $0.sourceRoadID == road.sourceRoadID
            }
            let defaultRule = RoadSourceTrafficRule.defaultRule(
                sourceRoadID: road.sourceRoadID,
                kind: road.kind
            )
            if rule != defaultRule {
                candidate.trafficRules.sourceRules.append(rule)
            }
        }
        candidate.updatedAt = .now
        return commitPersistedCandidate(candidate)
    }

    private func resetInterchangeEditingState() {
        selectedInterchangeCrossingID = nil
        selectedRampID = nil
        isAwaitingRampDrawing = false
        pendingRampPlan = nil
        pendingRampError = nil
        rampDirection = .forward
    }

    private func interchanges(
        _ interchanges: [RoadInterchange],
        adjustedFor operation: RoadSourceEditOperation
    ) -> [RoadInterchange] {
        guard case let .translate(request) = operation else {
            return interchanges
        }
        var adjusted = interchanges
        let sourceRoadIDs = request.sourceRoadIDs
        let offset = request.canvasOffset
        func translated(_ point: RoadPoint) -> RoadPoint {
            RoadPoint(x: point.x + offset.x, y: point.y + offset.y)
        }

        for interchangeIndex in adjusted.indices {
            let anchor = adjusted[interchangeIndex].anchor
            if sourceRoadIDs.contains(anchor.upperSourceRoadID),
               sourceRoadIDs.contains(anchor.lowerSourceRoadID) {
                adjusted[interchangeIndex].anchor.lastKnownPoint = translated(
                    anchor.lastKnownPoint
                )
            }
            for rampIndex in adjusted[interchangeIndex].ramps.indices {
                let ramp = adjusted[interchangeIndex].ramps[rampIndex]
                guard sourceRoadIDs.contains(ramp.sourceRoadID) else { continue }
                if sourceRoadIDs.contains(ramp.start.hostSourceRoadID) {
                    adjusted[interchangeIndex].ramps[rampIndex]
                        .start.lastKnownPoint = translated(ramp.start.lastKnownPoint)
                }
                if sourceRoadIDs.contains(ramp.end.hostSourceRoadID) {
                    adjusted[interchangeIndex].ramps[rampIndex]
                        .end.lastKnownPoint = translated(ramp.end.lastKnownPoint)
                }
            }
        }
        return adjusted
    }

    @discardableResult
    private func validateInterchanges(
        in candidate: RoadProject,
        prefix: String
    ) -> Bool {
        let issues = RoadInterchangeValidator.evaluate(
            interchanges: candidate.interchanges,
            in: candidate.roadNetwork
        )
        guard issues.isEmpty else {
            saveErrorMessage = interchangeErrorMessage(
                prefix: prefix,
                issues: issues
            )
            return false
        }
        return true
    }

    @discardableResult
    private func validateIntroducedLayerConflicts(
        in candidateNetwork: RoadNetwork,
        affecting sourceRoadIDs: Set<UUID>,
        prefix: String
    ) -> Bool {
        let existingConflicts = Set(project.roadNetwork.layerConflicts)
        let introduced = candidateNetwork.layerConflicts.filter {
            !$0.roadIDs.isDisjoint(with: sourceRoadIDs)
                && !existingConflicts.contains($0)
        }
        guard introduced.isEmpty else {
            let kinds = Set(introduced.map(\.kind))
                .map(\.displayName)
                .sorted()
                .joined(separator: "、")
            saveErrorMessage = "\(prefix)：层级冲突（\(kinds)）。"
            return false
        }
        return true
    }

    private func applyProjectEdit(_ edit: (inout RoadProject) -> Void) {
        var candidate = project
        edit(&candidate)
        candidate.updatedAt = .now
        _ = commitPersistedCandidate(candidate)
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
        while copy.formatVersion < RoadProject.currentFormatVersion {
            switch copy.formatVersion {
            case 1:
                copy.formatVersion = 2
            case 2:
                copy.formatVersion = 3
            case 3:
                copy.roadNetwork = RoadNetwork.rebuilding(
                    from: copy.roads,
                    interchanges: copy.interchanges
                ).network
                copy.formatVersion = 4
            case 4:
                copy.formatVersion = 5
            case 5:
                copy.formatVersion = 6
            case 6:
                copy.formatVersion = 7
            case 7:
                copy.engineeringStructures = engineeringStructures(
                    for: copy.roads,
                    terrain: copy.terrain,
                    mapScale: copy.mapScale
                )
                copy.formatVersion = 8
            case 8:
                copy.interchanges = []
                copy.roadNetwork = RoadNetwork.rebuilding(
                    from: copy.roads,
                    interchanges: copy.interchanges
                ).network
                copy.formatVersion = 9
            case 9:
                copy.trafficRules = .init()
                copy.formatVersion = 10
            case 10, 11, 12:
                copy.formatVersion = RoadProject.currentFormatVersion
            default:
                return copy
            }
        }
        return copy
    }

    private func scheduleTerrainGeneration(
        seed: UInt64,
        scenario: TerrainScenario = .island,
        purpose: TerrainGenerationPurpose
    ) {
        terrainGenerationTask?.cancel()

        let requestID = UUID()
        let request = TerrainGenerationRequest(seed: seed, scenario: scenario)
        terrainGenerationRequestID = requestID
        terrainGenerationState = .generating(
            targetName: purpose.targetName,
            progress: TerrainGenerationProgress(
                phase: .shoreline,
                fractionCompleted: 0
            ),
            usedCache: false
        )

        terrainGenerationTask = Task { [weak self, terrainCache] in
            guard let self else { return }

            do {
                let terrain: TerrainLayout
                if let cached = await terrainCache.value(for: request) {
                    try Task.checkCancellation()
                    markTerrainGenerationCacheHit(requestID: requestID)
                    terrain = cached
                } else {
                    terrain = try await TerrainGenerator.generate(
                        request: request
                    ) { [weak self] progress in
                        Task { @MainActor [weak self] in
                            self?.updateTerrainGenerationProgress(
                                progress,
                                requestID: requestID
                            )
                        }
                    }
                    try Task.checkCancellation()
                    await terrainCache.insert(terrain, for: request)
                }

                try Task.checkCancellation()
                completeTerrainGeneration(
                    terrain,
                    purpose: purpose,
                    requestID: requestID
                )
            } catch is CancellationError {
                finishCancelledTerrainGeneration(requestID: requestID)
            } catch {
                failTerrainGeneration(error, requestID: requestID)
            }
        }
    }

    private func updateTerrainGenerationProgress(
        _ progress: TerrainGenerationProgress,
        requestID: UUID
    ) {
        guard terrainGenerationRequestID == requestID,
              case let .generating(targetName, _, usedCache) = terrainGenerationState
        else { return }
        terrainGenerationState = .generating(
            targetName: targetName,
            progress: progress,
            usedCache: usedCache
        )
    }

    private func markTerrainGenerationCacheHit(requestID: UUID) {
        guard terrainGenerationRequestID == requestID,
              case let .generating(targetName, _, _) = terrainGenerationState
        else { return }
        terrainGenerationState = .generating(
            targetName: targetName,
            progress: TerrainGenerationProgress(
                phase: .finished,
                fractionCompleted: 1
            ),
            usedCache: true
        )
    }

    private func completeTerrainGeneration(
        _ terrain: TerrainLayout,
        purpose: TerrainGenerationPurpose,
        requestID: UUID
    ) {
        guard terrainGenerationRequestID == requestID else { return }

        switch purpose {
        case let .createNew(name, groupID):
            project = RoadProject(
                name: name,
                terrain: terrain,
                mapScale: MapScale(metersPerPoint: 20),
                groupID: groupID
            )
            projects.append(project)
            clearRoadSelection()
            resetInterchangeEditingState()
            resetHistory()
            persist()

        case let .replaceExisting(projectID, _):
            guard let index = projects.firstIndex(where: { $0.id == projectID }) else {
                finishCancelledTerrainGeneration(requestID: requestID)
                return
            }
            projects[index].terrain = terrain
            projects[index].engineeringStructures = Self.engineeringStructures(
                for: projects[index].roads,
                terrain: terrain,
                mapScale: projects[index].mapScale
            )
            projects[index].updatedAt = .now
            if project.id == projectID {
                project = projects[index]
            }
            persistProject(projects[index])
        }

        terrainGenerationRequestID = nil
        terrainGenerationTask = nil
        terrainGenerationState = .idle
    }

    private func finishCancelledTerrainGeneration(requestID: UUID) {
        guard terrainGenerationRequestID == requestID else { return }
        terrainGenerationRequestID = nil
        terrainGenerationTask = nil
        terrainGenerationState = .idle
    }

    private static func engineeringStructures(
        for roads: [RoadSegment],
        terrain: TerrainLayout,
        mapScale: MapScale
    ) -> [RoadEngineeringStructure] {
        RoadEngineeringPlanner.evaluate(
            roads: roads,
            terrain: terrain,
            mapScale: mapScale
        ).structures
    }

    private static func review(
        _ review: RoadStructureReviewRecord,
        dependsOnAny sourceRoadIDs: Set<UUID>
    ) -> Bool {
        if sourceRoadIDs.contains(review.plan.sourceRoadID) {
            return true
        }
        if review.plan.crossingSuggestions.contains(where: {
            sourceRoadIDs.contains($0.existingRoadID)
        }) {
            return true
        }
        return review.plan.candidates.contains { candidate in
            !sourceRoadIDs.isDisjoint(
                with: Set(candidate.evidence.relatedRoadIDs)
            )
        }
    }

    private func failTerrainGeneration(_ error: Error, requestID: UUID) {
        guard terrainGenerationRequestID == requestID else { return }
        let message = "地形生成失败：\(error.localizedDescription)"
        terrainGenerationRequestID = nil
        terrainGenerationTask = nil
        terrainGenerationState = .failed(message: message)
        saveErrorMessage = message
    }

    private static func placeholderTerrain(seed: UInt64) -> TerrainLayout {
        TerrainLayout(
            seed: seed,
            shoreline: [
                RoadPoint(x: 360, y: 600),
                RoadPoint(x: 520, y: 300),
                RoadPoint(x: 800, y: 190),
                RoadPoint(x: 1_080, y: 300),
                RoadPoint(x: 1_240, y: 600),
                RoadPoint(x: 1_080, y: 900),
                RoadPoint(x: 800, y: 1_010),
                RoadPoint(x: 520, y: 900),
            ],
            generationVersion: 0
        )
    }

    private static func needsTerrainRegeneration(_ terrain: TerrainLayout) -> Bool {
        !terrain.hasElevationData
            || terrain.generationVersion < TerrainLayout.currentGenerationVersion
    }

    private func engineeringErrorMessage(
        prefix: String,
        issues: [RoadEngineeringConstraintIssue]
    ) -> String {
        let details = Array(Set(issues.map(\.shortDescription))).sorted()
        guard !details.isEmpty else { return prefix }
        return "\(prefix)：\(details.joined(separator: "、"))。"
    }

    private func constructionErrorMessage(
        prefix: String,
        issues: [RoadConstructionIssue]
    ) -> String {
        let details = Array(Set(issues.map(\.shortDescription))).sorted()
        guard !details.isEmpty else { return prefix }
        return "\(prefix)：\(details.joined(separator: "、"))。"
    }

    private func interchangeErrorMessage(
        prefix: String,
        issues: [RoadInterchangeIssue]
    ) -> String {
        let trailingPunctuation = CharacterSet(
            charactersIn: "。.!！?？ "
        )
        let details = Array(
            Set(
                issues.map {
                    $0.message.trimmingCharacters(
                        in: trailingPunctuation
                    )
                }
            )
        ).sorted()
        guard !details.isEmpty else { return prefix }
        return "\(prefix)：\(details.joined(separator: "；"))。"
    }
}

private enum TerrainGenerationPurpose: Sendable {
    case createNew(name: String, groupID: UUID?)
    case replaceExisting(projectID: UUID, targetName: String)

    var targetName: String {
        switch self {
        case let .createNew(name, _): name
        case let .replaceExisting(_, targetName): targetName
        }
    }
}

private extension RoadLayerConflictKind {
    var displayName: String {
        switch self {
        case .unsupportedNonGroundJunction:
            "非地面层缺少明确的立交连接"
        case .nonGroundStructureOverlap:
            "非地面结构发生重叠"
        }
    }
}

private extension RoadEngineeringConstraintIssue {
    var shortDescription: String {
        switch kind {
        case .belowMinimumLength:
            "结构长度不足"
        case .aboveMaximumBridgeLength:
            "桥梁超过连续长度上限"
        case .structureGradeTooSteep:
            "结构纵坡过陡"
        case .entranceApproachTooSteep:
            "入口引道过陡"
        case .exitApproachTooSteep:
            "出口引道过陡"
        case .bridgeheadInWater:
            "桥头位于水域"
        case .tunnelPortalInWater:
            "隧道洞口位于水域"
        case .insufficientTunnelCover:
            "隧道覆土不足"
        case .bridgeDeckBelowTerrain:
            "桥面与地形相交"
        }
    }
}

private extension RoadConstructionIssue {
    var shortDescription: String {
        switch kind {
        case .localGradeAboveLimit:
            "地面道路局部纵坡过陡"
        case .groundRoadInWater:
            "地面道路穿过水域"
        case .elevatedAxisGradeAboveLimit:
            "高架轴线纵坡过陡"
        }
    }
}
