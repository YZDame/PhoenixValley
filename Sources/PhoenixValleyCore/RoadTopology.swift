import Foundation

public struct RoadNode: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var point: RoadPoint
    public var level: RoadLevel

    public init(id: UUID, point: RoadPoint, level: RoadLevel) {
        self.id = id
        self.point = point
        self.level = level
    }
}

public struct RoadEdge: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var sourceRoadID: UUID
    public var startNodeID: UUID
    public var endNodeID: UUID
    public var kind: RoadKind
    public private(set) var level: RoadLevel
    public private(set) var structure: RoadStructureType
    public var direction: RoadDirection
    public var priority: RoadPriority
    public var points: [RoadPoint]

    public init(
        id: UUID,
        sourceRoadID: UUID,
        startNodeID: UUID,
        endNodeID: UUID,
        kind: RoadKind,
        level: RoadLevel,
        structure: RoadStructureType? = nil,
        direction: RoadDirection,
        priority: RoadPriority,
        points: [RoadPoint]
    ) {
        self.id = id
        self.sourceRoadID = sourceRoadID
        self.startNodeID = startNodeID
        self.endNodeID = endNodeID
        self.kind = kind
        let normalizedStructure = structure ?? RoadStructureType(defaultFor: level)
        self.level = normalizedStructure.renderLevel
        self.structure = normalizedStructure
        self.direction = direction
        self.priority = priority
        self.points = points
    }

    public var roadSegment: RoadSegment {
        RoadSegment(
            id: id,
            kind: kind,
            level: level,
            structure: structure,
            points: points,
            direction: direction,
            priority: priority,
            sourceRoadID: sourceRoadID,
            startNodeID: startNodeID,
            endNodeID: endNodeID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceRoadID, startNodeID, endNodeID, kind, level, structure
        case direction, priority, points
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        sourceRoadID = try values.decode(UUID.self, forKey: .sourceRoadID)
        startNodeID = try values.decode(UUID.self, forKey: .startNodeID)
        endNodeID = try values.decode(UUID.self, forKey: .endNodeID)
        kind = try values.decode(RoadKind.self, forKey: .kind)
        let decodedLevel = try values.decode(RoadLevel.self, forKey: .level)
        structure = try values.decodeIfPresent(RoadStructureType.self, forKey: .structure)
            ?? RoadStructureType(defaultFor: decodedLevel)
        level = structure.renderLevel
        direction = try values.decode(RoadDirection.self, forKey: .direction)
        priority = try values.decode(RoadPriority.self, forKey: .priority)
        points = try values.decode([RoadPoint].self, forKey: .points)
    }

    public mutating func setStructure(_ structure: RoadStructureType) {
        self.structure = structure
        level = structure.renderLevel
    }

    public func permitsDeparture(from nodeID: UUID) -> Bool {
        switch direction {
        case .bidirectional:
            nodeID == startNodeID || nodeID == endNodeID
        case .forward:
            nodeID == startNodeID
        case .reverse:
            nodeID == endNodeID
        }
    }

    public func permitsArrival(at nodeID: UUID) -> Bool {
        switch direction {
        case .bidirectional:
            nodeID == startNodeID || nodeID == endNodeID
        case .forward:
            nodeID == endNodeID
        case .reverse:
            nodeID == startNodeID
        }
    }

    public func destinationNodeID(departingFrom nodeID: UUID) -> UUID? {
        guard permitsDeparture(from: nodeID) else { return nil }
        if nodeID == startNodeID { return endNodeID }
        if nodeID == endNodeID { return startNodeID }
        return nil
    }
}

public enum RoadRelationKind: String, Codable, CaseIterable, Sendable {
    case atGradeJunction
    case interchangeRampConnection
    case sameLevelOverlap
    case gradeSeparatedCrossing
    case structureTransition
}

public struct RoadRelation: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: RoadRelationKind
    public var point: RoadPoint
    public var secondaryPoint: RoadPoint?
    public var firstRoadID: UUID
    public var secondRoadID: UUID
    public var firstLevel: RoadLevel
    public var secondLevel: RoadLevel
    public var firstEdgeIDs: [UUID]
    public var secondEdgeIDs: [UUID]
    public var junctionNodeIDs: [UUID]
    public var interchangeID: UUID?
    public var rampSourceRoadID: UUID?
    public var rampTerminalRole: RoadRampTerminalRole?

    /// Short schema-facing alias for clients that do not need the ramp prefix.
    public var terminalRole: RoadRampTerminalRole? {
        get { rampTerminalRole }
        set { rampTerminalRole = newValue }
    }

    public init(
        id: UUID,
        kind: RoadRelationKind,
        point: RoadPoint,
        secondaryPoint: RoadPoint? = nil,
        firstRoadID: UUID,
        secondRoadID: UUID,
        firstLevel: RoadLevel,
        secondLevel: RoadLevel,
        firstEdgeIDs: [UUID],
        secondEdgeIDs: [UUID],
        junctionNodeIDs: [UUID] = [],
        interchangeID: UUID? = nil,
        rampSourceRoadID: UUID? = nil,
        rampTerminalRole: RoadRampTerminalRole? = nil
    ) {
        self.id = id
        self.kind = kind
        self.point = point
        self.secondaryPoint = secondaryPoint
        self.firstRoadID = firstRoadID
        self.secondRoadID = secondRoadID
        self.firstLevel = firstLevel
        self.secondLevel = secondLevel
        self.firstEdgeIDs = firstEdgeIDs
        self.secondEdgeIDs = secondEdgeIDs
        self.junctionNodeIDs = junctionNodeIDs
        self.interchangeID = interchangeID
        self.rampSourceRoadID = rampSourceRoadID
        self.rampTerminalRole = rampTerminalRole
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, point, secondaryPoint
        case firstRoadID, secondRoadID, firstLevel, secondLevel
        case firstEdgeIDs, secondEdgeIDs, junctionNodeIDs
        case interchangeID, rampSourceRoadID, rampTerminalRole
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(RoadRelationKind.self, forKey: .kind)
        point = try values.decode(RoadPoint.self, forKey: .point)
        secondaryPoint = try values.decodeIfPresent(
            RoadPoint.self,
            forKey: .secondaryPoint
        )
        firstRoadID = try values.decode(UUID.self, forKey: .firstRoadID)
        secondRoadID = try values.decode(UUID.self, forKey: .secondRoadID)
        firstLevel = try values.decode(RoadLevel.self, forKey: .firstLevel)
        secondLevel = try values.decode(RoadLevel.self, forKey: .secondLevel)
        firstEdgeIDs = try values.decodeIfPresent(
            [UUID].self,
            forKey: .firstEdgeIDs
        ) ?? []
        secondEdgeIDs = try values.decodeIfPresent(
            [UUID].self,
            forKey: .secondEdgeIDs
        ) ?? []
        junctionNodeIDs = try values.decodeIfPresent(
            [UUID].self,
            forKey: .junctionNodeIDs
        ) ?? []
        interchangeID = try values.decodeIfPresent(UUID.self, forKey: .interchangeID)
        rampSourceRoadID = try values.decodeIfPresent(
            UUID.self,
            forKey: .rampSourceRoadID
        )
        rampTerminalRole = try values.decodeIfPresent(
            RoadRampTerminalRole.self,
            forKey: .rampTerminalRole
        )
    }

    public var upperRoadID: UUID? {
        guard kind == .gradeSeparatedCrossing, firstLevel != secondLevel else { return nil }
        return firstLevel.rawValue > secondLevel.rawValue ? firstRoadID : secondRoadID
    }

    public var lowerRoadID: UUID? {
        guard kind == .gradeSeparatedCrossing, firstLevel != secondLevel else { return nil }
        return firstLevel.rawValue < secondLevel.rawValue ? firstRoadID : secondRoadID
    }
}

public enum RoadLayerConflictKind: String, Codable, CaseIterable, Sendable {
    case unsupportedNonGroundJunction
    case nonGroundStructureOverlap
}

public struct RoadLayerConflict: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var kind: RoadLayerConflictKind
    public var point: RoadPoint
    public var secondaryPoint: RoadPoint?
    public var roadIDs: Set<UUID>
    public var relationID: UUID

    public init(
        id: UUID,
        kind: RoadLayerConflictKind,
        point: RoadPoint,
        secondaryPoint: RoadPoint? = nil,
        roadIDs: Set<UUID>,
        relationID: UUID
    ) {
        self.id = id
        self.kind = kind
        self.point = point
        self.secondaryPoint = secondaryPoint
        self.roadIDs = roadIDs
        self.relationID = relationID
    }
}

public struct RoadTopologyConfiguration: Codable, Hashable, Sendable {
    public var snapTolerance: Double
    public var intersectionTolerance: Double
    public var minimumEdgeLength: Double

    public init(
        snapTolerance: Double = 1,
        intersectionTolerance: Double = 1e-8,
        minimumEdgeLength: Double = 1e-6
    ) {
        self.snapTolerance = max(0, snapTolerance)
        self.intersectionTolerance = max(1e-12, intersectionTolerance)
        self.minimumEdgeLength = max(1e-12, minimumEdgeLength)
    }
}

public struct RoadNetworkBuildResult: Codable, Hashable, Sendable {
    public var roads: [RoadSegment]
    public var network: RoadNetwork

    public init(roads: [RoadSegment], network: RoadNetwork) {
        self.roads = roads
        self.network = network
    }
}

public struct RoadNetwork: Codable, Hashable, Sendable {
    public var nodes: [RoadNode]
    public var edges: [RoadEdge]
    public var relations: [RoadRelation]

    public init(
        nodes: [RoadNode] = [],
        edges: [RoadEdge] = [],
        relations: [RoadRelation] = []
    ) {
        self.nodes = nodes
        self.edges = edges
        self.relations = relations
    }

    public var roadSegments: [RoadSegment] {
        edges.map(\.roadSegment)
    }

    public func node(id: UUID) -> RoadNode? {
        nodes.first { $0.id == id }
    }

    public func edge(id: UUID) -> RoadEdge? {
        edges.first { $0.id == id }
    }

    public func edges(at nodeID: UUID) -> [RoadEdge] {
        edges.filter { $0.startNodeID == nodeID || $0.endNodeID == nodeID }
    }

    public func outgoingEdges(from nodeID: UUID) -> [RoadEdge] {
        edges(at: nodeID).filter { $0.permitsDeparture(from: nodeID) }
    }

    public func adjacentNodeIDs(to nodeID: UUID) -> Set<UUID> {
        var result = Set(
            outgoingEdges(from: nodeID).compactMap {
                $0.destinationNodeID(departingFrom: nodeID)
            }
        )
        for relation in relations
        where relation.kind == .structureTransition
            && relation.junctionNodeIDs.contains(nodeID) {
            let transitionEdgeIDs = Set(relation.firstEdgeIDs + relation.secondEdgeIDs)
            let arrivingEdges = edges.filter {
                transitionEdgeIDs.contains($0.id)
                    && ($0.startNodeID == nodeID || $0.endNodeID == nodeID)
                    && $0.permitsArrival(at: nodeID)
            }
            guard !arrivingEdges.isEmpty else { continue }

            for destinationNodeID in relation.junctionNodeIDs where destinationNodeID != nodeID {
                let canContinue = edges.contains {
                    transitionEdgeIDs.contains($0.id)
                        && ($0.startNodeID == destinationNodeID
                            || $0.endNodeID == destinationNodeID)
                        && $0.permitsDeparture(from: destinationNodeID)
                }
                if canContinue {
                    result.insert(destinationNodeID)
                }
            }
        }
        return result
    }

    public func relations(involving sourceRoadID: UUID) -> [RoadRelation] {
        relations.filter {
            $0.firstRoadID == sourceRoadID || $0.secondRoadID == sourceRoadID
        }
    }

    public var layerConflicts: [RoadLayerConflict] {
        relations.compactMap { relation in
            switch relation.kind {
            case .atGradeJunction:
                guard relation.firstLevel != .ground
                    || relation.secondLevel != .ground
                else { return nil }
                guard !isCompatibleNonGroundEndpointContinuation(relation) else {
                    return nil
                }
                return RoadLayerConflict(
                    id: relation.id,
                    kind: .unsupportedNonGroundJunction,
                    point: relation.point,
                    secondaryPoint: relation.secondaryPoint,
                    roadIDs: [relation.firstRoadID, relation.secondRoadID],
                    relationID: relation.id
                )

            case .sameLevelOverlap:
                guard relation.firstLevel != .ground
                    || relation.secondLevel != .ground
                else { return nil }
                return RoadLayerConflict(
                    id: relation.id,
                    kind: .nonGroundStructureOverlap,
                    point: relation.point,
                    secondaryPoint: relation.secondaryPoint,
                    roadIDs: [relation.firstRoadID, relation.secondRoadID],
                    relationID: relation.id
                )

            case .interchangeRampConnection, .gradeSeparatedCrossing, .structureTransition:
                return nil
            }
        }
    }

    public static func rebuilding(
        from roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadNetworkBuildResult {
        RoadTopologyBuilder.build(
            roads: roads,
            interchanges: interchanges,
            configuration: configuration
        )
    }

    public static func integrating(
        existingRoads: [RoadSegment],
        newRoad: RoadSegment,
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadNetworkBuildResult {
        let snappedRoad = RoadTopologyBuilder.snapping(
            newRoad,
            to: existingRoads,
            tolerance: configuration.snapTolerance,
            minimumEdgeLength: configuration.minimumEdgeLength
        )
        return RoadTopologyBuilder.build(
            roads: existingRoads + [snappedRoad],
            interchanges: interchanges,
            configuration: configuration
        )
    }

    public static func removing(
        sourceRoadIDs: Set<UUID>,
        from roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadNetworkBuildResult {
        rebuilding(
            from: roads.filter { !sourceRoadIDs.contains($0.sourceRoadID) },
            interchanges: interchanges,
            configuration: configuration
        )
    }

    private func isCompatibleNonGroundEndpointContinuation(
        _ relation: RoadRelation
    ) -> Bool {
        guard relation.firstLevel == relation.secondLevel,
              relation.firstEdgeIDs.count == 1,
              relation.secondEdgeIDs.count == 1,
              let firstEdge = edge(id: relation.firstEdgeIDs[0]),
              let secondEdge = edge(id: relation.secondEdgeIDs[0])
        else { return false }
        return firstEdge.structure == secondEdge.structure
    }
}

private enum RoadTopologyBuilder {
    private static let coordinateScale = 1_000_000.0

    struct MeasuredRoad {
        var road: RoadSegment
        var cumulativeLengths: [Double]

        var totalLength: Double { cumulativeLengths.last ?? 0 }
    }

    struct Cut {
        var measure: Double
        var point: RoadPoint
    }

    struct PendingRelation {
        var kind: RoadRelationKind
        var point: RoadPoint
        var secondaryPoint: RoadPoint?
        var firstRoadIndex: Int
        var secondRoadIndex: Int
    }

    struct QuantizedPoint: Hashable, Comparable {
        var x: Int64
        var y: Int64

        init(_ point: RoadPoint) {
            x = Int64((point.x * coordinateScale).rounded())
            y = Int64((point.y * coordinateScale).rounded())
        }

        var point: RoadPoint {
            RoadPoint(
                x: Double(x) / coordinateScale,
                y: Double(y) / coordinateScale
            )
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.x == rhs.x ? lhs.y < rhs.y : lhs.x < rhs.x
        }
    }

    struct NodeKey: Hashable, Comparable {
        var point: QuantizedPoint
        var level: RoadLevel

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.level.rawValue != rhs.level.rawValue {
                return lhs.level.rawValue < rhs.level.rawValue
            }
            return lhs.point < rhs.point
        }
    }

    enum SegmentIntersection {
        case point(point: RoadPoint, firstT: Double, secondT: Double)
        case overlap(
            start: RoadPoint,
            end: RoadPoint,
            firstStartT: Double,
            firstEndT: Double,
            secondStartT: Double,
            secondEndT: Double
        )
    }

    static func snapping(
        _ road: RoadSegment,
        to existingRoads: [RoadSegment],
        tolerance: Double,
        minimumEdgeLength: Double
    ) -> RoadSegment {
        guard tolerance > 0, road.points.count >= 2 else { return road }
        var snapped = road

        func nearestPoint(to point: RoadPoint) -> RoadPoint? {
            var best: (distance: Double, roadID: String, segmentIndex: Int, point: RoadPoint)?
            for existing in existingRoads where existing.level == road.level {
                for index in 0..<(max(0, existing.points.count - 1)) {
                    let projection = projected(
                        point,
                        ontoSegmentFrom: existing.points[index],
                        to: existing.points[index + 1]
                    )
                    let distance = point.distance(to: projection)
                    guard distance <= tolerance else { continue }
                    let candidate = (
                        distance: distance,
                        roadID: existing.id.uuidString,
                        segmentIndex: index,
                        point: projection
                    )
                    if let currentBest = best {
                        let isCloser = candidate.distance
                            < currentBest.distance - minimumEdgeLength
                        let isStableTie = abs(candidate.distance - currentBest.distance)
                            <= minimumEdgeLength
                            && (candidate.roadID, candidate.segmentIndex)
                            < (currentBest.roadID, currentBest.segmentIndex)
                        if isCloser || isStableTie {
                            best = candidate
                        }
                    } else {
                        best = candidate
                    }
                }
            }
            return best?.point
        }

        if let first = snapped.points.first, let replacement = nearestPoint(to: first) {
            snapped.points[0] = replacement
            if first.distance(to: replacement) > minimumEdgeLength {
                snapped.startNodeID = nil
            }
        }
        if let lastIndex = snapped.points.indices.last,
           let replacement = nearestPoint(to: snapped.points[lastIndex]) {
            let previous = snapped.points[lastIndex]
            snapped.points[lastIndex] = replacement
            if previous.distance(to: replacement) > minimumEdgeLength {
                snapped.endNodeID = nil
            }
        }
        snapped.points = removingConsecutiveDuplicates(
            snapped.points,
            tolerance: minimumEdgeLength
        )
        return snapped
    }

    static func build(
        roads: [RoadSegment],
        interchanges: [RoadInterchange],
        configuration: RoadTopologyConfiguration
    ) -> RoadNetworkBuildResult {
        let measuredRoads = roads.compactMap {
            measuredRoad(from: $0, minimumEdgeLength: configuration.minimumEdgeLength)
        }
        guard !measuredRoads.isEmpty else {
            return RoadNetworkBuildResult(roads: [], network: RoadNetwork())
        }

        var cuts = measuredRoads.map { measured in
            [
                Cut(measure: 0, point: measured.road.points[0]),
                Cut(measure: measured.totalLength, point: measured.road.points.last!),
            ]
        }
        var pendingRelations: [PendingRelation] = []

        func record(
            _ intersection: SegmentIntersection,
            firstRoadIndex: Int,
            firstSegmentIndex: Int,
            firstLength: Double,
            secondRoadIndex: Int,
            secondSegmentIndex: Int,
            secondLength: Double
        ) {
            let firstRoad = measuredRoads[firstRoadIndex]
            let secondRoad = measuredRoads[secondRoadIndex]
            let sharesLevel = firstRoad.road.level == secondRoad.road.level

            switch intersection {
            case let .point(point, firstT, secondT):
                if sharesLevel {
                    cuts[firstRoadIndex].append(
                        Cut(
                            measure: firstRoad.cumulativeLengths[firstSegmentIndex]
                                + firstLength * firstT,
                            point: point
                        )
                    )
                    cuts[secondRoadIndex].append(
                        Cut(
                            measure: secondRoad.cumulativeLengths[secondSegmentIndex]
                                + secondLength * secondT,
                            point: point
                        )
                    )
                }
                pendingRelations.append(
                    PendingRelation(
                        kind: sharesLevel ? .atGradeJunction : .gradeSeparatedCrossing,
                        point: point,
                        secondaryPoint: nil,
                        firstRoadIndex: firstRoadIndex,
                        secondRoadIndex: secondRoadIndex
                    )
                )

            case let .overlap(
                start,
                end,
                firstStartT,
                firstEndT,
                secondStartT,
                secondEndT
            ):
                if sharesLevel {
                    cuts[firstRoadIndex].append(
                        Cut(
                            measure: firstRoad.cumulativeLengths[firstSegmentIndex]
                                + firstLength * firstStartT,
                            point: start
                        )
                    )
                    cuts[firstRoadIndex].append(
                        Cut(
                            measure: firstRoad.cumulativeLengths[firstSegmentIndex]
                                + firstLength * firstEndT,
                            point: end
                        )
                    )
                    cuts[secondRoadIndex].append(
                        Cut(
                            measure: secondRoad.cumulativeLengths[secondSegmentIndex]
                                + secondLength * secondStartT,
                            point: start
                        )
                    )
                    cuts[secondRoadIndex].append(
                        Cut(
                            measure: secondRoad.cumulativeLengths[secondSegmentIndex]
                                + secondLength * secondEndT,
                            point: end
                        )
                    )
                }
                pendingRelations.append(
                    PendingRelation(
                        kind: sharesLevel ? .sameLevelOverlap : .gradeSeparatedCrossing,
                        point: start,
                        secondaryPoint: end,
                        firstRoadIndex: firstRoadIndex,
                        secondRoadIndex: secondRoadIndex
                    )
                )
            }
        }

        for firstRoadIndex in measuredRoads.indices {
            for secondRoadIndex in measuredRoads.indices where secondRoadIndex > firstRoadIndex {
                let firstRoad = measuredRoads[firstRoadIndex]
                let secondRoad = measuredRoads[secondRoadIndex]
                let sharesSource = firstRoad.road.sourceRoadID
                    == secondRoad.road.sourceRoadID

                for firstSegmentIndex in 0..<(firstRoad.road.points.count - 1) {
                    let firstStart = firstRoad.road.points[firstSegmentIndex]
                    let firstEnd = firstRoad.road.points[firstSegmentIndex + 1]
                    let firstLength = firstStart.distance(to: firstEnd)
                    for secondSegmentIndex in 0..<(secondRoad.road.points.count - 1) {
                        let secondStart = secondRoad.road.points[secondSegmentIndex]
                        let secondEnd = secondRoad.road.points[secondSegmentIndex + 1]
                        let secondLength = secondStart.distance(to: secondEnd)
                        guard let intersection = intersection(
                            firstStart,
                            firstEnd,
                            secondStart,
                            secondEnd,
                            tolerance: configuration.intersectionTolerance
                        ) else {
                            continue
                        }
                        if sharesSource,
                           isEndpointOnlyConnection(
                               intersection,
                               tolerance: configuration.intersectionTolerance
                           ) {
                            continue
                        }
                        record(
                            intersection,
                            firstRoadIndex: firstRoadIndex,
                            firstSegmentIndex: firstSegmentIndex,
                            firstLength: firstLength,
                            secondRoadIndex: secondRoadIndex,
                            secondSegmentIndex: secondSegmentIndex,
                            secondLength: secondLength
                        )
                    }
                }
            }
        }

        for roadIndex in measuredRoads.indices {
            let road = measuredRoads[roadIndex]
            let segmentCount = road.road.points.count - 1
            guard segmentCount >= 3 else { continue }

            for firstSegmentIndex in 0..<segmentCount {
                for secondSegmentIndex in (firstSegmentIndex + 1)..<segmentCount {
                    if areAdjacentPolylineSegments(
                        firstSegmentIndex,
                        secondSegmentIndex,
                        segmentCount: segmentCount,
                        points: road.road.points,
                        tolerance: configuration.intersectionTolerance
                    ) {
                        continue
                    }

                    let firstStart = road.road.points[firstSegmentIndex]
                    let firstEnd = road.road.points[firstSegmentIndex + 1]
                    let secondStart = road.road.points[secondSegmentIndex]
                    let secondEnd = road.road.points[secondSegmentIndex + 1]
                    guard let selfIntersection = intersection(
                        firstStart,
                        firstEnd,
                        secondStart,
                        secondEnd,
                        tolerance: configuration.intersectionTolerance
                    ) else {
                        continue
                    }
                    record(
                        selfIntersection,
                        firstRoadIndex: roadIndex,
                        firstSegmentIndex: firstSegmentIndex,
                        firstLength: firstStart.distance(to: firstEnd),
                        secondRoadIndex: roadIndex,
                        secondSegmentIndex: secondSegmentIndex,
                        secondLength: secondStart.distance(to: secondEnd)
                    )
                }
            }
        }

        let uniqueCuts = zip(measuredRoads, cuts).map { measured, roadCuts in
            normalizedCuts(
                roadCuts,
                totalLength: measured.totalLength,
                tolerance: configuration.minimumEdgeLength
            )
        }
        let nodeIDs = makeNodeIDs(measuredRoads: measuredRoads, cuts: uniqueCuts)
        var nodesByID: [UUID: RoadNode] = [:]
        var edges: [RoadEdge] = []
        var edgesByInputRoadID: [UUID: [RoadEdge]] = [:]

        for roadIndex in measuredRoads.indices {
            let measured = measuredRoads[roadIndex]
            let roadCuts = uniqueCuts[roadIndex]
            guard roadCuts.count >= 2 else { continue }

            for fragmentIndex in 0..<(roadCuts.count - 1) {
                let startCut = roadCuts[fragmentIndex]
                let endCut = roadCuts[fragmentIndex + 1]
                guard endCut.measure - startCut.measure > configuration.minimumEdgeLength else {
                    continue
                }
                let startKey = NodeKey(
                    point: QuantizedPoint(startCut.point),
                    level: measured.road.level
                )
                let endKey = NodeKey(
                    point: QuantizedPoint(endCut.point),
                    level: measured.road.level
                )
                guard let startNodeID = nodeIDs[startKey],
                      let endNodeID = nodeIDs[endKey]
                else {
                    continue
                }
                let fragmentPoints = points(
                    along: measured,
                    from: startCut,
                    to: endCut,
                    minimumEdgeLength: configuration.minimumEdgeLength
                )
                guard fragmentPoints.count >= 2 else { continue }

                let edgeID: UUID
                if fragmentIndex == 0 {
                    edgeID = measured.road.id
                } else {
                    edgeID = StableTopologyID.make(
                        "edge",
                        measured.road.id.uuidString,
                        String(startKey.point.x),
                        String(startKey.point.y),
                        String(endKey.point.x),
                        String(endKey.point.y)
                    )
                }
                let edge = RoadEdge(
                    id: edgeID,
                    sourceRoadID: measured.road.sourceRoadID,
                    startNodeID: startNodeID,
                    endNodeID: endNodeID,
                    kind: measured.road.kind,
                    level: measured.road.level,
                    structure: measured.road.structure,
                    direction: measured.road.direction,
                    priority: measured.road.priority,
                    points: fragmentPoints
                )
                edges.append(edge)
                edgesByInputRoadID[measured.road.id, default: []].append(edge)
                nodesByID[startNodeID] = RoadNode(
                    id: startNodeID,
                    point: startKey.point.point,
                    level: measured.road.level
                )
                nodesByID[endNodeID] = RoadNode(
                    id: endNodeID,
                    point: endKey.point.point,
                    level: measured.road.level
                )
            }
        }

        let rawIntersectionRelations = makeRelations(
            consolidatingOverlapRelations(
                pendingRelations,
                measuredRoads: measuredRoads,
                tolerance: max(
                    configuration.minimumEdgeLength,
                    configuration.intersectionTolerance * 10
                )
            ),
            measuredRoads: measuredRoads,
            edges: edges,
            edgesByInputRoadID: edgesByInputRoadID,
            nodeIDs: nodeIDs,
            tolerance: max(
                configuration.minimumEdgeLength,
                configuration.intersectionTolerance * 10
            )
        )
        let intersectionRelations = markingInterchangeRampConnections(
            rawIntersectionRelations,
            measuredRoads: measuredRoads,
            interchanges: interchanges,
            tolerance: max(
                configuration.snapTolerance,
                configuration.minimumEdgeLength * 10
            )
        )
        let transitionRelations = makeStructureTransitionRelations(
            edges: edges,
            nodesByID: nodesByID
        )
        let relations = (intersectionRelations + transitionRelations).sorted {
            $0.id.uuidString < $1.id.uuidString
        }
        let nodes = nodesByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
        let network = RoadNetwork(nodes: nodes, edges: edges, relations: relations)
        return RoadNetworkBuildResult(roads: network.roadSegments, network: network)
    }

    private static func measuredRoad(
        from road: RoadSegment,
        minimumEdgeLength: Double
    ) -> MeasuredRoad? {
        var normalizedRoad = road
        normalizedRoad.points = removingConsecutiveDuplicates(
            road.points,
            tolerance: minimumEdgeLength
        )
        guard normalizedRoad.points.count >= 2 else { return nil }

        var cumulativeLengths = [0.0]
        cumulativeLengths.reserveCapacity(normalizedRoad.points.count)
        for index in 1..<normalizedRoad.points.count {
            cumulativeLengths.append(
                cumulativeLengths[index - 1]
                    + normalizedRoad.points[index - 1].distance(to: normalizedRoad.points[index])
            )
        }
        guard let totalLength = cumulativeLengths.last,
              totalLength > minimumEdgeLength
        else {
            return nil
        }
        return MeasuredRoad(road: normalizedRoad, cumulativeLengths: cumulativeLengths)
    }

    private static func normalizedCuts(
        _ cuts: [Cut],
        totalLength: Double,
        tolerance: Double
    ) -> [Cut] {
        let sorted = cuts.map { cut in
            Cut(
                measure: min(totalLength, max(0, cut.measure)),
                point: QuantizedPoint(cut.point).point
            )
        }.sorted { lhs, rhs in
            if abs(lhs.measure - rhs.measure) <= tolerance {
                return QuantizedPoint(lhs.point) < QuantizedPoint(rhs.point)
            }
            return lhs.measure < rhs.measure
        }

        var result: [Cut] = []
        for cut in sorted {
            if let last = result.last, abs(last.measure - cut.measure) <= tolerance {
                continue
            }
            result.append(cut)
        }
        return result
    }

    private static func makeNodeIDs(
        measuredRoads: [MeasuredRoad],
        cuts: [[Cut]]
    ) -> [NodeKey: UUID] {
        var preferredIDs: [NodeKey: Set<UUID>] = [:]
        var allKeys = Set<NodeKey>()

        for index in measuredRoads.indices {
            let measured = measuredRoads[index]
            for cut in cuts[index] {
                allKeys.insert(
                    NodeKey(
                        point: QuantizedPoint(cut.point),
                        level: measured.road.level
                    )
                )
            }

            let startKey = NodeKey(
                point: QuantizedPoint(measured.road.points[0]),
                level: measured.road.level
            )
            let endKey = NodeKey(
                point: QuantizedPoint(measured.road.points.last!),
                level: measured.road.level
            )
            if let startNodeID = measured.road.startNodeID {
                preferredIDs[startKey, default: []].insert(startNodeID)
            }
            if let endNodeID = measured.road.endNodeID {
                preferredIDs[endKey, default: []].insert(endNodeID)
            }
        }

        var result: [NodeKey: UUID] = [:]
        var usedIDs = Set<UUID>()
        for key in allKeys.sorted() {
            let preferred = preferredIDs[key, default: []]
                .sorted { $0.uuidString < $1.uuidString }
                .first { !usedIDs.contains($0) }
            var nodeID = preferred ?? StableTopologyID.make(
                "node",
                String(key.level.rawValue),
                String(key.point.x),
                String(key.point.y)
            )
            var salt = 0
            while usedIDs.contains(nodeID) {
                salt += 1
                nodeID = StableTopologyID.make(
                    "node",
                    String(key.level.rawValue),
                    String(key.point.x),
                    String(key.point.y),
                    String(salt)
                )
            }
            result[key] = nodeID
            usedIDs.insert(nodeID)
        }
        return result
    }

    private static func points(
        along measured: MeasuredRoad,
        from startCut: Cut,
        to endCut: Cut,
        minimumEdgeLength: Double
    ) -> [RoadPoint] {
        var points = [QuantizedPoint(startCut.point).point]
        for index in measured.road.points.indices {
            let measure = measured.cumulativeLengths[index]
            if measure > startCut.measure + minimumEdgeLength
                && measure < endCut.measure - minimumEdgeLength {
                points.append(measured.road.points[index])
            }
        }
        points.append(QuantizedPoint(endCut.point).point)
        return removingConsecutiveDuplicates(points, tolerance: minimumEdgeLength)
    }

    private static func makeRelations(
        _ pendingRelations: [PendingRelation],
        measuredRoads: [MeasuredRoad],
        edges: [RoadEdge],
        edgesByInputRoadID: [UUID: [RoadEdge]],
        nodeIDs: [NodeKey: UUID],
        tolerance: Double
    ) -> [RoadRelation] {
        var relationsByID: [UUID: RoadRelation] = [:]

        for pending in pendingRelations {
            let originalFirst = measuredRoads[pending.firstRoadIndex].road
            let originalSecond = measuredRoads[pending.secondRoadIndex].road
            let firstComesFirst = originalFirst.sourceRoadID.uuidString
                <= originalSecond.sourceRoadID.uuidString
            let first = firstComesFirst ? originalFirst : originalSecond
            let second = firstComesFirst ? originalSecond : originalFirst
            let point = QuantizedPoint(pending.point).point
            let secondaryPoint = pending.secondaryPoint.map { QuantizedPoint($0).point }
            let orderedPoints: (RoadPoint, RoadPoint?)
            if let secondaryPoint,
               QuantizedPoint(secondaryPoint) < QuantizedPoint(point) {
                orderedPoints = (secondaryPoint, point)
            } else {
                orderedPoints = (point, secondaryPoint)
            }

            var junctionNodeIDs: [UUID] = []
            if pending.kind != .gradeSeparatedCrossing {
                let firstKey = NodeKey(
                    point: QuantizedPoint(orderedPoints.0),
                    level: first.level
                )
                if let nodeID = nodeIDs[firstKey] {
                    junctionNodeIDs.append(nodeID)
                }
                if let secondary = orderedPoints.1 {
                    let secondKey = NodeKey(
                        point: QuantizedPoint(secondary),
                        level: first.level
                    )
                    if let nodeID = nodeIDs[secondKey], !junctionNodeIDs.contains(nodeID) {
                        junctionNodeIDs.append(nodeID)
                    }
                }
            }

            let relationID = StableTopologyID.make(
                "relation",
                pending.kind.rawValue,
                first.sourceRoadID.uuidString,
                second.sourceRoadID.uuidString,
                String(QuantizedPoint(orderedPoints.0).x),
                String(QuantizedPoint(orderedPoints.0).y),
                orderedPoints.1.map { String(QuantizedPoint($0).x) } ?? "",
                orderedPoints.1.map { String(QuantizedPoint($0).y) } ?? ""
            )

            let firstEdgeIDs: [UUID]
            let secondEdgeIDs: [UUID]
            if pending.kind == .atGradeJunction {
                firstEdgeIDs = edgeIDs(
                    for: first.sourceRoadID,
                    incidentTo: junctionNodeIDs,
                    edges: edges
                )
                secondEdgeIDs = edgeIDs(
                    for: second.sourceRoadID,
                    incidentTo: junctionNodeIDs,
                    edges: edges
                )
            } else if pending.kind == .sameLevelOverlap {
                let probe = orderedPoints.1.map {
                    RoadPoint(
                        x: (orderedPoints.0.x + $0.x) / 2,
                        y: (orderedPoints.0.y + $0.y) / 2
                    )
                } ?? orderedPoints.0
                firstEdgeIDs = edges
                    .filter {
                        $0.sourceRoadID == first.sourceRoadID
                            && distance(from: probe, to: $0.points) <= tolerance
                    }
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
                secondEdgeIDs = edges
                    .filter {
                        $0.sourceRoadID == second.sourceRoadID
                            && distance(from: probe, to: $0.points) <= tolerance
                    }
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
            } else {
                let probe: RoadPoint
                if let secondary = orderedPoints.1 {
                    probe = RoadPoint(
                        x: (orderedPoints.0.x + secondary.x) / 2,
                        y: (orderedPoints.0.y + secondary.y) / 2
                    )
                } else {
                    probe = orderedPoints.0
                }
                let originalFirstEdges = edgesByInputRoadID[originalFirst.id, default: []]
                let originalSecondEdges = edgesByInputRoadID[originalSecond.id, default: []]
                let firstCandidates = firstComesFirst
                    ? originalFirstEdges
                    : originalSecondEdges
                let secondCandidates = firstComesFirst
                    ? originalSecondEdges
                    : originalFirstEdges
                firstEdgeIDs = firstCandidates
                    .filter { distance(from: probe, to: $0.points) <= tolerance }
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
                secondEdgeIDs = secondCandidates
                    .filter { distance(from: probe, to: $0.points) <= tolerance }
                    .map(\.id)
                    .sorted { $0.uuidString < $1.uuidString }
            }

            let relation = RoadRelation(
                id: relationID,
                kind: pending.kind,
                point: orderedPoints.0,
                secondaryPoint: orderedPoints.1,
                firstRoadID: first.sourceRoadID,
                secondRoadID: second.sourceRoadID,
                firstLevel: first.level,
                secondLevel: second.level,
                firstEdgeIDs: firstEdgeIDs,
                secondEdgeIDs: secondEdgeIDs,
                junctionNodeIDs: junctionNodeIDs.sorted {
                    $0.uuidString < $1.uuidString
                }
            )
            if var existing = relationsByID[relationID] {
                existing.firstEdgeIDs = union(existing.firstEdgeIDs, relation.firstEdgeIDs)
                existing.secondEdgeIDs = union(existing.secondEdgeIDs, relation.secondEdgeIDs)
                existing.junctionNodeIDs = union(
                    existing.junctionNodeIDs,
                    relation.junctionNodeIDs
                )
                relationsByID[relationID] = existing
            } else {
                relationsByID[relationID] = relation
            }
        }
        return relationsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func consolidatingOverlapRelations(
        _ pendingRelations: [PendingRelation],
        measuredRoads: [MeasuredRoad],
        tolerance: Double
    ) -> [PendingRelation] {
        struct OverlapKey: Hashable {
            var firstRoadID: UUID
            var secondRoadID: UUID
            var level: RoadLevel
        }

        func overlapKey(for relation: PendingRelation) -> OverlapKey {
            let firstRoad = measuredRoads[relation.firstRoadIndex].road
            let secondRoad = measuredRoads[relation.secondRoadIndex].road
            let firstID = firstRoad.sourceRoadID
            let secondID = secondRoad.sourceRoadID
            if firstID.uuidString < secondID.uuidString {
                return OverlapKey(
                    firstRoadID: firstID,
                    secondRoadID: secondID,
                    level: firstRoad.level
                )
            }
            return OverlapKey(
                firstRoadID: secondID,
                secondRoadID: firstID,
                level: firstRoad.level
            )
        }

        func mergedOverlap(
            _ lhs: PendingRelation,
            _ rhs: PendingRelation
        ) -> PendingRelation? {
            guard overlapKey(for: lhs) == overlapKey(for: rhs),
                  let lhsEnd = lhs.secondaryPoint,
                  let rhsEnd = rhs.secondaryPoint
            else {
                return nil
            }

            let lhsVector = lhsEnd - lhs.point
            let lhsLength = sqrt(dot(lhsVector, lhsVector))
            guard lhsLength > tolerance else { return nil }
            let unit = lhsVector * (1 / lhsLength)
            let rhsPoints = [rhs.point, rhsEnd]
            let maximumLineDistance = rhsPoints.map {
                abs(cross($0 - lhs.point, unit))
            }.max() ?? .infinity
            guard maximumLineDistance <= tolerance else { return nil }

            let lhsRange = 0.0...lhsLength
            let rhsProjections = rhsPoints.map { dot($0 - lhs.point, unit) }
            let rhsLower = rhsProjections.min() ?? 0
            let rhsUpper = rhsProjections.max() ?? 0
            guard rhsLower <= lhsRange.upperBound + tolerance,
                  rhsUpper >= lhsRange.lowerBound - tolerance
            else {
                return nil
            }

            let candidates = [lhs.point, lhsEnd, rhs.point, rhsEnd].map {
                (projection: dot($0 - lhs.point, unit), point: $0)
            }.sorted { $0.projection < $1.projection }
            guard let firstCandidate = candidates.first,
                  let lastCandidate = candidates.last
            else {
                return nil
            }
            var start = QuantizedPoint(firstCandidate.point).point
            var end = QuantizedPoint(lastCandidate.point).point
            if QuantizedPoint(end) < QuantizedPoint(start) {
                swap(&start, &end)
            }

            var result = lhs
            result.point = start
            result.secondaryPoint = end
            return result
        }

        func contains(
            _ point: RoadPoint,
            in overlap: PendingRelation
        ) -> Bool {
            guard let end = overlap.secondaryPoint else { return false }
            let vector = end - overlap.point
            let length = sqrt(dot(vector, vector))
            guard length > tolerance else {
                return point.distance(to: overlap.point) <= tolerance
            }
            let unit = vector * (1 / length)
            let offset = point - overlap.point
            guard abs(cross(offset, unit)) <= tolerance else { return false }
            let projection = dot(offset, unit)
            return projection >= -tolerance && projection <= length + tolerance
        }

        var mergedOverlaps: [PendingRelation] = []
        for overlap in pendingRelations where overlap.kind == .sameLevelOverlap {
            var candidate = overlap
            var index = 0
            while index < mergedOverlaps.count {
                if let merged = mergedOverlap(mergedOverlaps[index], candidate) {
                    candidate = merged
                    mergedOverlaps.remove(at: index)
                    index = 0
                } else {
                    index += 1
                }
            }
            mergedOverlaps.append(candidate)
        }

        let otherRelations = pendingRelations.filter { relation in
            guard relation.kind != .sameLevelOverlap else { return false }
            guard relation.kind == .atGradeJunction else { return true }
            let relationKey = overlapKey(for: relation)
            return !mergedOverlaps.contains {
                overlapKey(for: $0) == relationKey
                    && contains(relation.point, in: $0)
            }
        }
        return otherRelations + mergedOverlaps
    }

    private static func makeStructureTransitionRelations(
        edges: [RoadEdge],
        nodesByID: [UUID: RoadNode]
    ) -> [RoadRelation] {
        let grouped = Dictionary(grouping: edges, by: \.sourceRoadID)
        var relationsByID: [UUID: RoadRelation] = [:]

        for (sourceRoadID, sourceEdges) in grouped {
            for firstIndex in sourceEdges.indices {
                for secondIndex in sourceEdges.indices where secondIndex > firstIndex {
                    let first = sourceEdges[firstIndex]
                    let second = sourceEdges[secondIndex]
                    guard first.level != second.level else { continue }

                    let firstNodeIDs = [first.startNodeID, first.endNodeID]
                    let secondNodeIDs = [second.startNodeID, second.endNodeID]
                    for firstNodeID in firstNodeIDs {
                        guard let firstNode = nodesByID[firstNodeID] else { continue }
                        for secondNodeID in secondNodeIDs {
                            guard let secondNode = nodesByID[secondNodeID],
                                  QuantizedPoint(firstNode.point) == QuantizedPoint(secondNode.point)
                            else { continue }

                            let orderedEdgeIDs = [first.id, second.id].sorted {
                                $0.uuidString < $1.uuidString
                            }
                            let orderedNodeIDs = [firstNodeID, secondNodeID].sorted {
                                $0.uuidString < $1.uuidString
                            }
                            let relationID = StableTopologyID.make(
                                "structure-transition",
                                sourceRoadID.uuidString,
                                orderedEdgeIDs[0].uuidString,
                                orderedEdgeIDs[1].uuidString,
                                String(QuantizedPoint(firstNode.point).x),
                                String(QuantizedPoint(firstNode.point).y)
                            )
                            relationsByID[relationID] = RoadRelation(
                                id: relationID,
                                kind: .structureTransition,
                                point: QuantizedPoint(firstNode.point).point,
                                firstRoadID: sourceRoadID,
                                secondRoadID: sourceRoadID,
                                firstLevel: first.level,
                                secondLevel: second.level,
                                firstEdgeIDs: [first.id],
                                secondEdgeIDs: [second.id],
                                junctionNodeIDs: orderedNodeIDs
                            )
                        }
                    }
                }
            }
        }

        return relationsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    private static func markingInterchangeRampConnections(
        _ relations: [RoadRelation],
        measuredRoads: [MeasuredRoad],
        interchanges: [RoadInterchange],
        tolerance: Double
    ) -> [RoadRelation] {
        struct Declaration {
            var interchangeID: UUID
            var rampSourceRoadID: UUID
            var role: RoadRampTerminalRole
            var terminal: RoadRampTerminal
            var rampEndpoint: RoadPoint
            var hostPoint: RoadPoint
        }

        let boundedTolerance = max(1e-6, tolerance)
        var polylines: [UUID: [RoadPoint]] = [:]
        for sourceRoadID in Set(measuredRoads.map(\.road.sourceRoadID)) {
            if let polyline = stitchedSourcePolyline(
                sourceRoadID: sourceRoadID,
                measuredRoads: measuredRoads,
                tolerance: boundedTolerance
            ) {
                polylines[sourceRoadID] = polyline
            }
        }

        var declarations: [Declaration] = []
        for interchange in interchanges {
            let allowedHosts = Set(
                [
                    interchange.anchor.upperSourceRoadID,
                    interchange.anchor.lowerSourceRoadID,
                ] + interchange.ramps.map(\.sourceRoadID)
            )
            for ramp in interchange.ramps {
                guard let rampPolyline = polylines[ramp.sourceRoadID],
                      let rampStart = rampPolyline.first,
                      let rampEnd = rampPolyline.last
                else { continue }
                for (role, terminal, endpoint) in [
                    (RoadRampTerminalRole.start, ramp.start, rampStart),
                    (RoadRampTerminalRole.end, ramp.end, rampEnd),
                ] {
                    guard terminal.hostSourceRoadID != ramp.sourceRoadID,
                          allowedHosts.contains(terminal.hostSourceRoadID),
                          terminal.normalizedChainage >= 0,
                          terminal.normalizedChainage <= 1,
                          let hostPolyline = polylines[terminal.hostSourceRoadID],
                          let hostPoint = point(
                              on: hostPolyline,
                              atNormalizedChainage: terminal.normalizedChainage
                          )
                    else { continue }
                    declarations.append(
                        Declaration(
                            interchangeID: interchange.id,
                            rampSourceRoadID: ramp.sourceRoadID,
                            role: role,
                            terminal: terminal,
                            rampEndpoint: endpoint,
                            hostPoint: hostPoint
                        )
                    )
                }
            }
        }
        declarations.sort {
            (
                $0.interchangeID.uuidString,
                $0.rampSourceRoadID.uuidString,
                $0.role.rawValue
            ) < (
                $1.interchangeID.uuidString,
                $1.rampSourceRoadID.uuidString,
                $1.role.rawValue
            )
        }

        return relations.map { relation in
            guard relation.kind == .atGradeJunction else { return relation }
            let roadIDs = Set([relation.firstRoadID, relation.secondRoadID])
            guard let declaration = declarations.first(where: { declaration in
                roadIDs == Set([
                    declaration.rampSourceRoadID,
                    declaration.terminal.hostSourceRoadID,
                ])
                    && relation.firstLevel == declaration.terminal.level
                    && relation.secondLevel == declaration.terminal.level
                    && relation.point.distance(to: declaration.terminal.lastKnownPoint)
                        <= boundedTolerance
                    && relation.point.distance(to: declaration.rampEndpoint)
                        <= boundedTolerance
                    && relation.point.distance(to: declaration.hostPoint)
                        <= boundedTolerance
            }) else {
                return relation
            }

            return RoadRelation(
                id: StableTopologyID.make(
                    "interchange-ramp-connection",
                    declaration.interchangeID.uuidString,
                    declaration.rampSourceRoadID.uuidString,
                    declaration.role.rawValue,
                    relation.firstRoadID.uuidString,
                    relation.secondRoadID.uuidString,
                    String(QuantizedPoint(relation.point).x),
                    String(QuantizedPoint(relation.point).y)
                ),
                kind: .interchangeRampConnection,
                point: relation.point,
                secondaryPoint: relation.secondaryPoint,
                firstRoadID: relation.firstRoadID,
                secondRoadID: relation.secondRoadID,
                firstLevel: relation.firstLevel,
                secondLevel: relation.secondLevel,
                firstEdgeIDs: relation.firstEdgeIDs,
                secondEdgeIDs: relation.secondEdgeIDs,
                junctionNodeIDs: relation.junctionNodeIDs,
                interchangeID: declaration.interchangeID,
                rampSourceRoadID: declaration.rampSourceRoadID,
                rampTerminalRole: declaration.role
            )
        }
    }

    private static func stitchedSourcePolyline(
        sourceRoadID: UUID,
        measuredRoads: [MeasuredRoad],
        tolerance: Double
    ) -> [RoadPoint]? {
        var fragments = measuredRoads
            .filter { $0.road.sourceRoadID == sourceRoadID }
            .map(\.road)
        guard !fragments.isEmpty else { return nil }
        if fragments.count == 1 {
            return fragments[0].points
        }

        fragments.sort { $0.id.uuidString < $1.id.uuidString }
        let startIndex = fragments.indices.first { candidateIndex in
            guard let start = fragments[candidateIndex].points.first else { return false }
            return !fragments.indices.contains { otherIndex in
                guard otherIndex != candidateIndex,
                      let end = fragments[otherIndex].points.last
                else { return false }
                return end.distance(to: start) <= tolerance
            }
        } ?? fragments.startIndex

        var ordered = [fragments.remove(at: startIndex)]
        while !fragments.isEmpty {
            guard let currentEnd = ordered.last?.points.last else {
                return nil
            }
            let candidates = fragments.indices.filter { index in
                (
                    fragments[index].points.first?.distance(to: currentEnd)
                        ?? .infinity
                ) <= tolerance
            }
            guard let nextIndex = candidates.min(by: {
                fragments[$0].id.uuidString < fragments[$1].id.uuidString
            }) else { return nil }
            ordered.append(fragments.remove(at: nextIndex))
        }

        var points = ordered[0].points
        for fragment in ordered.dropFirst() {
            points.append(contentsOf: fragment.points.dropFirst())
        }
        return removingConsecutiveDuplicates(points, tolerance: tolerance)
    }

    private static func point(
        on polyline: [RoadPoint],
        atNormalizedChainage normalizedChainage: Double
    ) -> RoadPoint? {
        guard let first = polyline.first, let last = polyline.last else { return nil }
        guard polyline.count >= 2 else { return first }
        let lengths = zip(polyline, polyline.dropFirst()).map { $0.distance(to: $1) }
        let totalLength = lengths.reduce(0, +)
        guard totalLength > 1e-12 else { return first }
        let target = min(1, max(0, normalizedChainage)) * totalLength
        var traversed = 0.0
        for (index, length) in lengths.enumerated() {
            if target <= traversed + length || index == lengths.count - 1 {
                guard length > 1e-12 else { return polyline[index] }
                let fraction = min(1, max(0, (target - traversed) / length))
                return polyline[index] + (polyline[index + 1] - polyline[index]) * fraction
            }
            traversed += length
        }
        return last
    }

    private static func edgeIDs(
        for sourceRoadID: UUID,
        incidentTo nodeIDs: [UUID],
        edges: [RoadEdge]
    ) -> [UUID] {
        edges.filter { edge in
            edge.sourceRoadID == sourceRoadID
                && (nodeIDs.contains(edge.startNodeID) || nodeIDs.contains(edge.endNodeID))
        }
        .map(\.id)
        .sorted { $0.uuidString < $1.uuidString }
    }

    private static func union(_ lhs: [UUID], _ rhs: [UUID]) -> [UUID] {
        Array(Set(lhs).union(rhs)).sorted { $0.uuidString < $1.uuidString }
    }

    private static func isEndpointOnlyConnection(
        _ intersection: SegmentIntersection,
        tolerance: Double
    ) -> Bool {
        guard case let .point(_, firstT, secondT) = intersection else { return false }
        return isEndpointParameter(firstT, tolerance: tolerance)
            && isEndpointParameter(secondT, tolerance: tolerance)
    }

    private static func isEndpointParameter(_ value: Double, tolerance: Double) -> Bool {
        value <= tolerance || value >= 1 - tolerance
    }

    private static func areAdjacentPolylineSegments(
        _ firstIndex: Int,
        _ secondIndex: Int,
        segmentCount: Int,
        points: [RoadPoint],
        tolerance: Double
    ) -> Bool {
        if secondIndex == firstIndex + 1 {
            return true
        }
        let endpointDistance = points.first?.distance(
            to: points.last ?? RoadPoint(x: 0, y: 0)
        ) ?? .infinity
        let isClosed = endpointDistance <= tolerance
        return isClosed && firstIndex == 0 && secondIndex == segmentCount - 1
    }

    private static func intersection(
        _ firstStart: RoadPoint,
        _ firstEnd: RoadPoint,
        _ secondStart: RoadPoint,
        _ secondEnd: RoadPoint,
        tolerance: Double
    ) -> SegmentIntersection? {
        let r = firstEnd - firstStart
        let s = secondEnd - secondStart
        let qMinusP = secondStart - firstStart
        let rLengthSquared = dot(r, r)
        let sLengthSquared = dot(s, s)
        guard rLengthSquared > tolerance * tolerance,
              sLengthSquared > tolerance * tolerance
        else {
            return nil
        }

        let rCrossS = cross(r, s)
        let parallelThreshold = tolerance * max(1, sqrt(rLengthSquared * sLengthSquared))
        if abs(rCrossS) <= parallelThreshold {
            let collinearThreshold = tolerance
                * max(1, sqrt(dot(qMinusP, qMinusP) * rLengthSquared))
            guard abs(cross(qMinusP, r)) <= collinearThreshold else { return nil }

            let t0 = dot(qMinusP, r) / rLengthSquared
            let t1 = t0 + dot(s, r) / rLengthSquared
            let overlapStartT = max(0, min(t0, t1))
            let overlapEndT = min(1, max(t0, t1))
            guard overlapEndT >= overlapStartT - tolerance else { return nil }

            let startT = clamped(overlapStartT)
            let endT = clamped(overlapEndT)
            let start = firstStart + r * startT
            let end = firstStart + r * endT
            let secondStartT = clamped(dot(start - secondStart, s) / sLengthSquared)
            let secondEndT = clamped(dot(end - secondStart, s) / sLengthSquared)
            if start.distance(to: end) <= tolerance {
                return .point(
                    point: start,
                    firstT: startT,
                    secondT: secondStartT
                )
            }
            return .overlap(
                start: start,
                end: end,
                firstStartT: startT,
                firstEndT: endT,
                secondStartT: secondStartT,
                secondEndT: secondEndT
            )
        }

        let firstT = cross(qMinusP, s) / rCrossS
        let secondT = cross(qMinusP, r) / rCrossS
        guard firstT >= -tolerance, firstT <= 1 + tolerance,
              secondT >= -tolerance, secondT <= 1 + tolerance
        else {
            return nil
        }
        let clampedFirstT = clamped(firstT)
        let clampedSecondT = clamped(secondT)
        let firstPoint = firstStart + r * clampedFirstT
        let secondPoint = secondStart + s * clampedSecondT
        return .point(
            point: RoadPoint(
                x: (firstPoint.x + secondPoint.x) / 2,
                y: (firstPoint.y + secondPoint.y) / 2
            ),
            firstT: clampedFirstT,
            secondT: clampedSecondT
        )
    }

    private static func projected(
        _ point: RoadPoint,
        ontoSegmentFrom start: RoadPoint,
        to end: RoadPoint
    ) -> RoadPoint {
        let delta = end - start
        let lengthSquared = dot(delta, delta)
        guard lengthSquared > 0 else { return start }
        let t = clamped(dot(point - start, delta) / lengthSquared)
        return start + delta * t
    }

    private static func distance(from point: RoadPoint, to polyline: [RoadPoint]) -> Double {
        guard polyline.count >= 2 else { return .infinity }
        return (0..<(polyline.count - 1)).reduce(Double.infinity) { best, index in
            min(
                best,
                point.distance(
                    to: projected(
                        point,
                        ontoSegmentFrom: polyline[index],
                        to: polyline[index + 1]
                    )
                )
            )
        }
    }

    private static func removingConsecutiveDuplicates(
        _ points: [RoadPoint],
        tolerance: Double
    ) -> [RoadPoint] {
        var result: [RoadPoint] = []
        for point in points {
            if let last = result.last, last.distance(to: point) <= tolerance {
                continue
            }
            result.append(point)
        }
        return result
    }

    private static func dot(_ lhs: RoadPoint, _ rhs: RoadPoint) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y
    }

    private static func cross(_ lhs: RoadPoint, _ rhs: RoadPoint) -> Double {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}

private enum StableTopologyID {
    static func make(_ components: String...) -> UUID {
        let bytes = components.joined(separator: "\u{1F}").utf8
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x84222325cbf29ce4
        for byte in bytes {
            first ^= UInt64(byte)
            first = first &* 0x100000001b3
            second ^= UInt64(byte) &+ (first >> 32)
            second = second &* 0x100000001b3
        }

        var uuidBytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<8 {
            uuidBytes[index] = UInt8(truncatingIfNeeded: first >> UInt64((7 - index) * 8))
            uuidBytes[index + 8] = UInt8(
                truncatingIfNeeded: second >> UInt64((7 - index) * 8)
            )
        }
        uuidBytes[6] = (uuidBytes[6] & 0x0F) | 0x50
        uuidBytes[8] = (uuidBytes[8] & 0x3F) | 0x80
        return UUID(
            uuid: (
                uuidBytes[0], uuidBytes[1], uuidBytes[2], uuidBytes[3],
                uuidBytes[4], uuidBytes[5], uuidBytes[6], uuidBytes[7],
                uuidBytes[8], uuidBytes[9], uuidBytes[10], uuidBytes[11],
                uuidBytes[12], uuidBytes[13], uuidBytes[14], uuidBytes[15]
            )
        )
    }
}
