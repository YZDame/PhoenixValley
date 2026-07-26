import Foundation

/// An axis-aligned selection rectangle expressed in the road canvas coordinate space.
public struct RoadSourceSelectionRectangle: Hashable, Sendable {
    public let minimumCanvasPoint: RoadPoint
    public let maximumCanvasPoint: RoadPoint

    public init(
        canvasCornerA: RoadPoint,
        canvasCornerB: RoadPoint
    ) {
        minimumCanvasPoint = RoadPoint(
            x: min(canvasCornerA.x, canvasCornerB.x),
            y: min(canvasCornerA.y, canvasCornerB.y)
        )
        maximumCanvasPoint = RoadPoint(
            x: max(canvasCornerA.x, canvasCornerB.x),
            y: max(canvasCornerA.y, canvasCornerB.y)
        )
    }

    public init(
        meterCornerA: RoadPoint,
        meterCornerB: RoadPoint,
        mapScale: MapScale
    ) {
        self.init(
            canvasCornerA: RoadPoint(
                x: mapScale.canvasDistance(forMeters: meterCornerA.x),
                y: mapScale.canvasDistance(forMeters: meterCornerA.y)
            ),
            canvasCornerB: RoadPoint(
                x: mapScale.canvasDistance(forMeters: meterCornerB.x),
                y: mapScale.canvasDistance(forMeters: meterCornerB.y)
            )
        )
    }

    public func contains(canvasPoint: RoadPoint) -> Bool {
        guard minimumCanvasPoint.hasFiniteCoordinates,
              maximumCanvasPoint.hasFiniteCoordinates,
              canvasPoint.hasFiniteCoordinates else {
            return false
        }
        return canvasPoint.x >= minimumCanvasPoint.x
            && canvasPoint.x <= maximumCanvasPoint.x
            && canvasPoint.y >= minimumCanvasPoint.y
            && canvasPoint.y <= maximumCanvasPoint.y
    }
}

public struct RoadSourceHit: Hashable, Sendable {
    public var sourceRoadID: UUID
    public var nearestCanvasPoint: RoadPoint
    public var distanceCanvasPoints: Double
    public var distanceMeters: Double

    public init(
        sourceRoadID: UUID,
        nearestCanvasPoint: RoadPoint,
        distanceCanvasPoints: Double,
        distanceMeters: Double
    ) {
        self.sourceRoadID = sourceRoadID
        self.nearestCanvasPoint = nearestCanvasPoint
        self.distanceCanvasPoints = distanceCanvasPoints
        self.distanceMeters = distanceMeters
    }
}

public struct RoadSourceControlPointHit: Hashable, Sendable {
    public var sourceRoadID: UUID
    public var canvasPoint: RoadPoint
    public var distanceCanvasPoints: Double
    public var distanceMeters: Double

    public init(
        sourceRoadID: UUID,
        canvasPoint: RoadPoint,
        distanceCanvasPoints: Double,
        distanceMeters: Double
    ) {
        self.sourceRoadID = sourceRoadID
        self.canvasPoint = canvasPoint
        self.distanceCanvasPoints = distanceCanvasPoints
        self.distanceMeters = distanceMeters
    }
}

/// Source-level hit testing and marquee selection for road editing.
public enum RoadSourceGeometry {
    public static func nearestSource(
        toCanvasPoint point: RoadPoint,
        maximumDistanceMeters: Double,
        mapScale: MapScale,
        in roads: [RoadSegment]
    ) -> RoadSourceHit? {
        guard point.hasFiniteCoordinates,
              maximumDistanceMeters.isFinite,
              mapScale.metersPerPoint.isFinite,
              mapScale.metersPerPoint > 0 else {
            return nil
        }
        let maximumDistanceCanvasPoints = mapScale.canvasDistance(
            forMeters: max(0, maximumDistanceMeters)
        )
        guard maximumDistanceCanvasPoints.isFinite else { return nil }
        var best: (
            hit: RoadSourceHit,
            roadID: UUID,
            segmentIndex: Int
        )?

        for road in roads {
            if road.points.count == 1,
               let onlyPoint = road.points.first,
               onlyPoint.hasFiniteCoordinates {
                considerSourceHit(
                    sourceRoadID: road.sourceRoadID,
                    roadID: road.id,
                    segmentIndex: 0,
                    nearestPoint: onlyPoint,
                    queryPoint: point,
                    maximumDistanceCanvasPoints: maximumDistanceCanvasPoints,
                    mapScale: mapScale,
                    best: &best
                )
                continue
            }

            guard road.points.count >= 2 else { continue }
            for segmentIndex in 0..<(road.points.count - 1) {
                let nearestPoint = projected(
                    point,
                    ontoSegmentFrom: road.points[segmentIndex],
                    to: road.points[segmentIndex + 1]
                )
                considerSourceHit(
                    sourceRoadID: road.sourceRoadID,
                    roadID: road.id,
                    segmentIndex: segmentIndex,
                    nearestPoint: nearestPoint,
                    queryPoint: point,
                    maximumDistanceCanvasPoints: maximumDistanceCanvasPoints,
                    mapScale: mapScale,
                    best: &best
                )
            }
        }
        return best?.hit
    }

    public static func nearestSource(
        toMeterPoint point: RoadPoint,
        maximumDistanceMeters: Double,
        mapScale: MapScale,
        in roads: [RoadSegment]
    ) -> RoadSourceHit? {
        guard point.hasFiniteCoordinates else { return nil }
        return nearestSource(
            toCanvasPoint: RoadPoint(
                x: mapScale.canvasDistance(forMeters: point.x),
                y: mapScale.canvasDistance(forMeters: point.y)
            ),
            maximumDistanceMeters: maximumDistanceMeters,
            mapScale: mapScale,
            in: roads
        )
    }

    public static func nearestControlPoint(
        toCanvasPoint point: RoadPoint,
        on sourceRoadID: UUID,
        maximumDistanceMeters: Double,
        mapScale: MapScale,
        in roads: [RoadSegment]
    ) -> RoadSourceControlPointHit? {
        guard point.hasFiniteCoordinates,
              maximumDistanceMeters.isFinite,
              mapScale.metersPerPoint.isFinite,
              mapScale.metersPerPoint > 0 else {
            return nil
        }
        let maximumDistanceCanvasPoints = mapScale.canvasDistance(
            forMeters: max(0, maximumDistanceMeters)
        )
        guard maximumDistanceCanvasPoints.isFinite else { return nil }
        var best: (
            hit: RoadSourceControlPointHit,
            roadID: UUID,
            pointIndex: Int
        )?

        for road in roads where road.sourceRoadID == sourceRoadID {
            for (pointIndex, candidatePoint) in road.points.enumerated() {
                guard candidatePoint.hasFiniteCoordinates else { continue }
                let distance = point.distance(to: candidatePoint)
                guard distance.isFinite,
                      distance <= maximumDistanceCanvasPoints else {
                    continue
                }
                let hit = RoadSourceControlPointHit(
                    sourceRoadID: sourceRoadID,
                    canvasPoint: candidatePoint,
                    distanceCanvasPoints: distance,
                    distanceMeters: mapScale.meters(forCanvasDistance: distance)
                )
                let candidate = (
                    hit: hit,
                    roadID: road.id,
                    pointIndex: pointIndex
                )
                if isBetterControlPointHit(candidate, than: best) {
                    best = candidate
                }
            }
        }
        return best?.hit
    }

    public static func nearestControlPoint(
        toMeterPoint point: RoadPoint,
        on sourceRoadID: UUID,
        maximumDistanceMeters: Double,
        mapScale: MapScale,
        in roads: [RoadSegment]
    ) -> RoadSourceControlPointHit? {
        guard point.hasFiniteCoordinates else { return nil }
        return nearestControlPoint(
            toCanvasPoint: RoadPoint(
                x: mapScale.canvasDistance(forMeters: point.x),
                y: mapScale.canvasDistance(forMeters: point.y)
            ),
            on: sourceRoadID,
            maximumDistanceMeters: maximumDistanceMeters,
            mapScale: mapScale,
            in: roads
        )
    }

    public static func sourceRoadIDs(
        intersecting rectangle: RoadSourceSelectionRectangle,
        in roads: [RoadSegment]
    ) -> Set<UUID> {
        guard rectangle.hasFiniteBounds else { return [] }
        return Set(
            roads.compactMap { road in
                roadIntersectsSelectionRectangle(road, rectangle: rectangle)
                    ? road.sourceRoadID
                    : nil
            }
        )
    }
}

public struct RoadSourceTranslation: Hashable, Sendable {
    public var sourceRoadIDs: Set<UUID>
    public var canvasOffset: RoadPoint

    public init(
        sourceRoadIDs: Set<UUID>,
        canvasOffset: RoadPoint
    ) {
        self.sourceRoadIDs = sourceRoadIDs
        self.canvasOffset = canvasOffset
    }

    public init(
        sourceRoadIDs: Set<UUID>,
        meterOffset: RoadPoint,
        mapScale: MapScale
    ) {
        self.init(
            sourceRoadIDs: sourceRoadIDs,
            canvasOffset: RoadPoint(
                x: mapScale.canvasDistance(forMeters: meterOffset.x),
                y: mapScale.canvasDistance(forMeters: meterOffset.y)
            )
        )
    }
}

public struct RoadSourceControlPointMove: Hashable, Sendable {
    public var sourceRoadID: UUID
    public var probeCanvasPoint: RoadPoint
    public var destinationCanvasPoint: RoadPoint
    public var maximumDistanceMeters: Double
    public var mapScale: MapScale

    public init(
        sourceRoadID: UUID,
        probeCanvasPoint: RoadPoint,
        destinationCanvasPoint: RoadPoint,
        maximumDistanceMeters: Double,
        mapScale: MapScale
    ) {
        self.sourceRoadID = sourceRoadID
        self.probeCanvasPoint = probeCanvasPoint
        self.destinationCanvasPoint = destinationCanvasPoint
        self.maximumDistanceMeters = max(0, maximumDistanceMeters)
        self.mapScale = mapScale
    }

    public init(
        sourceRoadID: UUID,
        probeMeterPoint: RoadPoint,
        destinationMeterPoint: RoadPoint,
        maximumDistanceMeters: Double,
        mapScale: MapScale
    ) {
        self.init(
            sourceRoadID: sourceRoadID,
            probeCanvasPoint: RoadPoint(
                x: mapScale.canvasDistance(forMeters: probeMeterPoint.x),
                y: mapScale.canvasDistance(forMeters: probeMeterPoint.y)
            ),
            destinationCanvasPoint: RoadPoint(
                x: mapScale.canvasDistance(forMeters: destinationMeterPoint.x),
                y: mapScale.canvasDistance(forMeters: destinationMeterPoint.y)
            ),
            maximumDistanceMeters: maximumDistanceMeters,
            mapScale: mapScale
        )
    }
}

public struct RoadSourceKindChange: Hashable, Sendable {
    public var sourceRoadIDs: Set<UUID>
    public var kind: RoadKind

    public init(sourceRoadIDs: Set<UUID>, kind: RoadKind) {
        self.sourceRoadIDs = sourceRoadIDs
        self.kind = kind
    }
}

public enum RoadSourceEditOperation: Hashable, Sendable {
    case translate(RoadSourceTranslation)
    case moveControlPoint(RoadSourceControlPointMove)
    case changeKind(RoadSourceKindChange)
}

public struct RoadSourceEditTransaction: Hashable, Sendable {
    public var operations: [RoadSourceEditOperation]

    public init(operations: [RoadSourceEditOperation]) {
        self.operations = operations
    }
}

public struct RoadSourceEditResult: Hashable, Sendable {
    public var network: RoadNetwork
    public var affectedSourceRoadIDs: Set<UUID>

    public init(
        network: RoadNetwork,
        affectedSourceRoadIDs: Set<UUID>
    ) {
        self.network = network
        self.affectedSourceRoadIDs = affectedSourceRoadIDs
    }
}

public extension RoadNetwork {
    /// Applies every edit to one working copy and rebuilds topology exactly once.
    static func editingSources(
        _ transaction: RoadSourceEditTransaction,
        in roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadSourceEditResult {
        var editedRoads = roads
        var affectedSourceRoadIDs: Set<UUID> = []
        let originalSemantics = sourceSemantics(in: roads)

        for operation in transaction.operations {
            switch operation {
            case let .translate(request):
                apply(
                    request,
                    to: &editedRoads,
                    affectedSourceRoadIDs: &affectedSourceRoadIDs
                )
            case let .moveControlPoint(request):
                apply(
                    request,
                    to: &editedRoads,
                    configuration: configuration,
                    affectedSourceRoadIDs: &affectedSourceRoadIDs
                )
            case let .changeKind(request):
                apply(
                    request,
                    to: &editedRoads,
                    affectedSourceRoadIDs: &affectedSourceRoadIDs
                )
            }
        }

        let editedSemantics = sourceSemantics(in: editedRoads)
        affectedSourceRoadIDs = affectedSourceRoadIDs.filter {
            originalSemantics[$0] != editedSemantics[$0]
        }

        let rebuilt = rebuilding(
            from: editedRoads,
            interchanges: interchanges,
            configuration: configuration
        ).network
        let originallyValidSourceRoadIDs = Set(
            roads.compactMap { road in
                hasValidGeometry(
                    road.points,
                    minimumEdgeLength: configuration.minimumEdgeLength
                ) ? road.sourceRoadID : nil
            }
        )
        let rebuiltSourceRoadIDs = Set(rebuilt.edges.map(\.sourceRoadID))
        let removesWholeSource = !affectedSourceRoadIDs
            .intersection(originallyValidSourceRoadIDs)
            .isSubset(of: rebuiltSourceRoadIDs)
        guard !removesWholeSource else {
            return RoadSourceEditResult(
                network: rebuilding(
                    from: roads,
                    interchanges: interchanges,
                    configuration: configuration
                ).network,
                affectedSourceRoadIDs: []
            )
        }

        return RoadSourceEditResult(
            network: rebuilt,
            affectedSourceRoadIDs: affectedSourceRoadIDs
        )
    }

    static func movingSources(
        _ request: RoadSourceTranslation,
        in roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadSourceEditResult {
        editingSources(
            RoadSourceEditTransaction(operations: [.translate(request)]),
            in: roads,
            interchanges: interchanges,
            configuration: configuration
        )
    }

    static func movingControlPoint(
        _ request: RoadSourceControlPointMove,
        in roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadSourceEditResult {
        editingSources(
            RoadSourceEditTransaction(operations: [.moveControlPoint(request)]),
            in: roads,
            interchanges: interchanges,
            configuration: configuration
        )
    }

    static func changingSourceKinds(
        _ request: RoadSourceKindChange,
        in roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadSourceEditResult {
        editingSources(
            RoadSourceEditTransaction(operations: [.changeKind(request)]),
            in: roads,
            interchanges: interchanges,
            configuration: configuration
        )
    }
}

private extension RoadNetwork {
    static func apply(
        _ request: RoadSourceTranslation,
        to roads: inout [RoadSegment],
        affectedSourceRoadIDs: inout Set<UUID>
    ) {
        guard request.canvasOffset.hasFiniteCoordinates else { return }
        let selectedPoints = roads
            .filter { request.sourceRoadIDs.contains($0.sourceRoadID) }
            .flatMap(\.points)
        guard !selectedPoints.isEmpty,
              selectedPoints.allSatisfy(\.hasFiniteCoordinates) else {
            return
        }

        let minimumX = selectedPoints.map(\.x).min() ?? 0
        let maximumX = selectedPoints.map(\.x).max() ?? 0
        let minimumY = selectedPoints.map(\.y).min() ?? 0
        let maximumY = selectedPoints.map(\.y).max() ?? 0
        let offset = RoadPoint(
            x: constrainedOffset(
                request.canvasOffset.x,
                lowerBound: -minimumX,
                upperBound: MapScale.canvasWidth - maximumX
            ),
            y: constrainedOffset(
                request.canvasOffset.y,
                lowerBound: -minimumY,
                upperBound: MapScale.canvasHeight - maximumY
            )
        )

        for index in roads.indices
        where request.sourceRoadIDs.contains(roads[index].sourceRoadID) {
            var didChange = false
            roads[index].points = roads[index].points.map { point in
                let moved = clampedToCanvas(point + offset)
                didChange = didChange || moved != point
                return moved
            }
            if didChange {
                roads[index].startNodeID = nil
                roads[index].endNodeID = nil
                affectedSourceRoadIDs.insert(roads[index].sourceRoadID)
            }
        }
    }

    static func apply(
        _ request: RoadSourceControlPointMove,
        to roads: inout [RoadSegment],
        configuration: RoadTopologyConfiguration,
        affectedSourceRoadIDs: inout Set<UUID>
    ) {
        guard request.probeCanvasPoint.hasFiniteCoordinates,
              request.destinationCanvasPoint.hasFiniteCoordinates,
              request.maximumDistanceMeters.isFinite,
              request.mapScale.metersPerPoint.isFinite,
              request.mapScale.metersPerPoint > 0 else {
            return
        }
        guard let hit = RoadSourceGeometry.nearestControlPoint(
            toCanvasPoint: request.probeCanvasPoint,
            on: request.sourceRoadID,
            maximumDistanceMeters: request.maximumDistanceMeters,
            mapScale: request.mapScale,
            in: roads
        ) else {
            return
        }

        let destination = clampedToCanvas(request.destinationCanvasPoint)
        let matchingTolerance = max(
            1e-9,
            configuration.minimumEdgeLength
        )
        var didChangeSource = false

        for roadIndex in roads.indices
        where roads[roadIndex].sourceRoadID == request.sourceRoadID {
            var movedFirstPoint = false
            var movedLastPoint = false
            let lastPointIndex = roads[roadIndex].points.indices.last

            for pointIndex in roads[roadIndex].points.indices
            where roads[roadIndex].points[pointIndex]
                .distance(to: hit.canvasPoint) <= matchingTolerance {
                guard roads[roadIndex].points[pointIndex] != destination else {
                    continue
                }
                roads[roadIndex].points[pointIndex] = destination
                movedFirstPoint = movedFirstPoint || pointIndex == 0
                movedLastPoint = movedLastPoint || pointIndex == lastPointIndex
                didChangeSource = true
            }

            if movedFirstPoint {
                roads[roadIndex].startNodeID = nil
            }
            if movedLastPoint {
                roads[roadIndex].endNodeID = nil
            }
        }

        if didChangeSource {
            affectedSourceRoadIDs.insert(request.sourceRoadID)
        }
    }

    static func apply(
        _ request: RoadSourceKindChange,
        to roads: inout [RoadSegment],
        affectedSourceRoadIDs: inout Set<UUID>
    ) {
        for index in roads.indices
        where request.sourceRoadIDs.contains(roads[index].sourceRoadID)
            && roads[index].kind != request.kind {
            roads[index].kind = request.kind
            affectedSourceRoadIDs.insert(roads[index].sourceRoadID)
        }
    }

    static func constrainedOffset(
        _ desired: Double,
        lowerBound: Double,
        upperBound: Double
    ) -> Double {
        guard desired.isFinite,
              lowerBound.isFinite,
              upperBound.isFinite,
              lowerBound <= upperBound else {
            return 0
        }
        return min(upperBound, max(lowerBound, desired))
    }

    struct RoadSourceSegmentSemantic: Hashable {
        var id: UUID
        var kind: RoadKind
        var structure: RoadStructureType
        var points: [RoadPoint]
        var direction: RoadDirection
        var priority: RoadPriority
    }

    static func sourceSemantics(
        in roads: [RoadSegment]
    ) -> [UUID: [RoadSourceSegmentSemantic]] {
        Dictionary(grouping: roads, by: \.sourceRoadID).mapValues { segments in
            segments
                .sorted { $0.id.uuidString < $1.id.uuidString }
                .map {
                    RoadSourceSegmentSemantic(
                        id: $0.id,
                        kind: $0.kind,
                        structure: $0.structure,
                        points: $0.points,
                        direction: $0.direction,
                        priority: $0.priority
                    )
                }
        }
    }

    static func hasValidGeometry(
        _ points: [RoadPoint],
        minimumEdgeLength: Double
    ) -> Bool {
        guard minimumEdgeLength.isFinite,
              minimumEdgeLength >= 0,
              points.allSatisfy(\.hasFiniteCoordinates) else {
            return false
        }
        var normalized: [RoadPoint] = []
        for point in points {
            guard let last = normalized.last else {
                normalized.append(point)
                continue
            }
            if last.distance(to: point) > minimumEdgeLength {
                normalized.append(point)
            }
        }
        guard normalized.count >= 2 else { return false }
        let totalLength = zip(normalized, normalized.dropFirst()).reduce(0.0) {
            $0 + $1.0.distance(to: $1.1)
        }
        return totalLength.isFinite && totalLength > minimumEdgeLength
    }
}

private extension RoadSourceGeometry {
    static func considerSourceHit(
        sourceRoadID: UUID,
        roadID: UUID,
        segmentIndex: Int,
        nearestPoint: RoadPoint,
        queryPoint: RoadPoint,
        maximumDistanceCanvasPoints: Double,
        mapScale: MapScale,
        best: inout (
            hit: RoadSourceHit,
            roadID: UUID,
            segmentIndex: Int
        )?
    ) {
        guard nearestPoint.hasFiniteCoordinates,
              queryPoint.hasFiniteCoordinates,
              maximumDistanceCanvasPoints.isFinite else {
            return
        }
        let distance = queryPoint.distance(to: nearestPoint)
        guard distance.isFinite,
              distance <= maximumDistanceCanvasPoints else {
            return
        }
        let hit = RoadSourceHit(
            sourceRoadID: sourceRoadID,
            nearestCanvasPoint: nearestPoint,
            distanceCanvasPoints: distance,
            distanceMeters: mapScale.meters(forCanvasDistance: distance)
        )
        let candidate = (
            hit: hit,
            roadID: roadID,
            segmentIndex: segmentIndex
        )
        if isBetterSourceHit(candidate, than: best) {
            best = candidate
        }
    }

    static func isBetterSourceHit(
        _ candidate: (
            hit: RoadSourceHit,
            roadID: UUID,
            segmentIndex: Int
        ),
        than current: (
            hit: RoadSourceHit,
            roadID: UUID,
            segmentIndex: Int
        )?
    ) -> Bool {
        guard let current else { return true }
        let epsilon = 1e-12
        if candidate.hit.distanceCanvasPoints
            < current.hit.distanceCanvasPoints - epsilon {
            return true
        }
        guard abs(
            candidate.hit.distanceCanvasPoints
                - current.hit.distanceCanvasPoints
        ) <= epsilon else {
            return false
        }
        return (
            candidate.hit.sourceRoadID.uuidString,
            candidate.roadID.uuidString,
            candidate.segmentIndex
        ) < (
            current.hit.sourceRoadID.uuidString,
            current.roadID.uuidString,
            current.segmentIndex
        )
    }

    static func isBetterControlPointHit(
        _ candidate: (
            hit: RoadSourceControlPointHit,
            roadID: UUID,
            pointIndex: Int
        ),
        than current: (
            hit: RoadSourceControlPointHit,
            roadID: UUID,
            pointIndex: Int
        )?
    ) -> Bool {
        guard let current else { return true }
        let epsilon = 1e-12
        if candidate.hit.distanceCanvasPoints
            < current.hit.distanceCanvasPoints - epsilon {
            return true
        }
        guard abs(
            candidate.hit.distanceCanvasPoints
                - current.hit.distanceCanvasPoints
        ) <= epsilon else {
            return false
        }
        return (
            candidate.hit.canvasPoint.x,
            candidate.hit.canvasPoint.y,
            candidate.roadID.uuidString,
            candidate.pointIndex
        ) < (
            current.hit.canvasPoint.x,
            current.hit.canvasPoint.y,
            current.roadID.uuidString,
            current.pointIndex
        )
    }

    static func projected(
        _ point: RoadPoint,
        ontoSegmentFrom start: RoadPoint,
        to end: RoadPoint
    ) -> RoadPoint {
        guard point.hasFiniteCoordinates,
              start.hasFiniteCoordinates,
              end.hasFiniteCoordinates else {
            return RoadPoint(x: .nan, y: .nan)
        }
        let delta = end - start
        let lengthSquared = delta.x * delta.x + delta.y * delta.y
        guard lengthSquared.isFinite,
              lengthSquared > 1e-18 else {
            return start
        }
        let offset = point - start
        let t = min(
            1,
            max(0, (offset.x * delta.x + offset.y * delta.y) / lengthSquared)
        )
        return start + delta * t
    }

    static func roadIntersectsSelectionRectangle(
        _ road: RoadSegment,
        rectangle: RoadSourceSelectionRectangle
    ) -> Bool {
        if road.points.contains(where: rectangle.contains(canvasPoint:)) {
            return true
        }
        guard road.points.count >= 2 else { return false }
        return (0..<(road.points.count - 1)).contains { index in
            segment(
                from: road.points[index],
                to: road.points[index + 1],
                intersects: rectangle
            )
        }
    }

    static func segment(
        from start: RoadPoint,
        to end: RoadPoint,
        intersects rectangle: RoadSourceSelectionRectangle
    ) -> Bool {
        guard start.hasFiniteCoordinates,
              end.hasFiniteCoordinates,
              rectangle.hasFiniteBounds else {
            return false
        }
        let delta = end - start
        var lowerParameter = 0.0
        var upperParameter = 1.0
        let boundaries = [
            (-delta.x, start.x - rectangle.minimumCanvasPoint.x),
            (delta.x, rectangle.maximumCanvasPoint.x - start.x),
            (-delta.y, start.y - rectangle.minimumCanvasPoint.y),
            (delta.y, rectangle.maximumCanvasPoint.y - start.y),
        ]

        for (coefficient, distance) in boundaries {
            if abs(coefficient) <= 1e-18 {
                if distance < 0 { return false }
                continue
            }
            let parameter = distance / coefficient
            if coefficient < 0 {
                if parameter > upperParameter { return false }
                lowerParameter = max(lowerParameter, parameter)
            } else {
                if parameter < lowerParameter { return false }
                upperParameter = min(upperParameter, parameter)
            }
        }
        return lowerParameter <= upperParameter
    }
}

private extension RoadSourceSelectionRectangle {
    var hasFiniteBounds: Bool {
        minimumCanvasPoint.hasFiniteCoordinates
            && maximumCanvasPoint.hasFiniteCoordinates
    }
}

private extension RoadPoint {
    var hasFiniteCoordinates: Bool {
        x.isFinite && y.isFinite
    }
}

private func clampedToCanvas(_ point: RoadPoint) -> RoadPoint {
    RoadPoint(
        x: min(MapScale.canvasWidth, max(0, point.x)),
        y: min(MapScale.canvasHeight, max(0, point.y))
    )
}
