import Foundation

public struct RoadRampPlannerConfiguration: Codable, Hashable, Sendable {
    /// Maximum physical distance from a drawn terminal to either host road.
    public var endpointSnapDistanceMeters: Double
    /// Minimum along-road distance between a ramp terminal and the crossing.
    public var minimumDistanceFromCrossingMeters: Double
    /// Keeps a level transition away from either end of the ramp.
    public var transitionFractionRange: ClosedRange<Double>
    /// Minimum physical centerline length after both terminals have snapped.
    public var minimumRampLengthMeters: Double

    public init(
        endpointSnapDistanceMeters: Double = 30,
        minimumDistanceFromCrossingMeters: Double = 25,
        transitionFractionRange: ClosedRange<Double> = 0.2...0.8,
        minimumRampLengthMeters: Double = 60
    ) {
        self.endpointSnapDistanceMeters = endpointSnapDistanceMeters
        self.minimumDistanceFromCrossingMeters = minimumDistanceFromCrossingMeters
        self.transitionFractionRange = transitionFractionRange
        self.minimumRampLengthMeters = minimumRampLengthMeters
    }
}

public struct RoadRampPlan: Hashable, Sendable {
    public var interchange: RoadInterchange
    public var ramp: RoadRamp
    public var roadSegments: [RoadSegment]

    public init(
        interchange: RoadInterchange,
        ramp: RoadRamp,
        roadSegments: [RoadSegment]
    ) {
        self.interchange = interchange
        self.ramp = ramp
        self.roadSegments = roadSegments
    }
}

public enum RoadRampPlannerError: Error, Hashable, Sendable {
    case invalidConfiguration
    case railwayRampUnsupported
    case crossingMustBeSingleGradeSeparatedPoint
    case crossingRoadsMustBeDistinct
    case missingHostRoad(UUID)
    case railwayHostUnsupported(UUID)
    case tunnelHostUnsupported(UUID)
    case insufficientGeometry
    case nonFiniteGeometry
    case endpointsDoNotSnapToDistinctHosts
    case terminalTooCloseToCrossing(
        role: RoadRampTerminalRole,
        distanceMeters: Double
    )
    case rampTooShort(lengthMeters: Double, minimumMeters: Double)
}

extension RoadRampPlannerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "匝道规划参数无效。"
        case .railwayRampUnsupported:
            "铁路不能作为公路立交匝道。"
        case .crossingMustBeSingleGradeSeparatedPoint:
            "只能在单点分层交叉处规划匝道。"
        case .crossingRoadsMustBeDistinct:
            "匝道必须连接两条不同的宿主道路。"
        case .missingHostRoad:
            "立交引用的宿主道路不存在。"
        case .railwayHostUnsupported:
            "首版匝道规划不支持铁路宿主。"
        case .tunnelHostUnsupported:
            "首版匝道规划不支持隧道宿主。"
        case .insufficientGeometry:
            "匝道笔迹至少需要两个不同的点。"
        case .nonFiniteGeometry:
            "匝道笔迹包含无效坐标。"
        case .endpointsDoNotSnapToDistinctHosts:
            "匝道首尾必须分别靠近立交的两条宿主道路。"
        case .terminalTooCloseToCrossing:
            "匝道接入口离交叉中心过近。"
        case let .rampTooShort(lengthMeters, minimumMeters):
            "匝道长度 \(lengthMeters.formatted(.number.precision(.fractionLength(1)))) 米，短于最小值 \(minimumMeters.formatted(.number.precision(.fractionLength(1)))) 米。"
        }
    }
}

public enum RoadRampPlanner {
    public static func plan(
        points: [RoadPoint],
        crossing: RoadRelation,
        roads: [RoadSegment],
        existingInterchanges: [RoadInterchange],
        kind: RoadKind,
        direction: RoadDirection,
        mapScale: MapScale,
        configuration: RoadRampPlannerConfiguration = .init()
    ) throws -> RoadRampPlan {
        try validate(configuration)
        guard kind != .railway else {
            throw RoadRampPlannerError.railwayRampUnsupported
        }
        guard crossing.kind == .gradeSeparatedCrossing,
              crossing.secondaryPoint == nil,
              crossing.upperRoadID != nil,
              crossing.lowerRoadID != nil
        else {
            throw RoadRampPlannerError.crossingMustBeSingleGradeSeparatedPoint
        }
        guard crossing.firstRoadID != crossing.secondRoadID else {
            throw RoadRampPlannerError.crossingRoadsMustBeDistinct
        }

        let firstHost = try hostCenterline(
            sourceRoadID: crossing.firstRoadID,
            roads: roads
        )
        let secondHost = try hostCenterline(
            sourceRoadID: crossing.secondRoadID,
            roads: roads
        )
        try validate(host: firstHost)
        try validate(host: secondHost)

        let cleanedPoints = try sanitized(points)
        guard cleanedPoints.count >= 2,
              let drawnStart = cleanedPoints.first,
              let drawnEnd = cleanedPoints.last
        else {
            throw RoadRampPlannerError.insufficientGeometry
        }

        let startOnFirst = firstHost.projection(of: drawnStart)
        let startOnSecond = secondHost.projection(of: drawnStart)
        let endOnFirst = firstHost.projection(of: drawnEnd)
        let endOnSecond = secondHost.projection(of: drawnEnd)
        let snapDistance = configuration.endpointSnapDistanceMeters
            / mapScale.metersPerPoint

        let direct = TerminalAssignment(
            startHost: firstHost,
            start: startOnFirst,
            endHost: secondHost,
            end: endOnSecond
        )
        let reversed = TerminalAssignment(
            startHost: secondHost,
            start: startOnSecond,
            endHost: firstHost,
            end: endOnFirst
        )
        let assignment = [direct, reversed]
            .filter {
                $0.start.distance <= snapDistance + 1e-9
                    && $0.end.distance <= snapDistance + 1e-9
            }
            .min {
                let lhsDistance = $0.start.distance + $0.end.distance
                let rhsDistance = $1.start.distance + $1.end.distance
                if abs(lhsDistance - rhsDistance) > 1e-9 {
                    return lhsDistance < rhsDistance
                }
                return $0.startHost.sourceRoadID.uuidString
                    < $1.startHost.sourceRoadID.uuidString
            }
        guard let assignment else {
            throw RoadRampPlannerError.endpointsDoNotSnapToDistinctHosts
        }
        try validate(hostTerminal: assignment.start)
        try validate(hostTerminal: assignment.end)

        try validateTerminalSeparation(
            assignment.start,
            role: .start,
            crossingPoint: crossing.point,
            host: assignment.startHost,
            mapScale: mapScale,
            configuration: configuration
        )
        try validateTerminalSeparation(
            assignment.end,
            role: .end,
            crossingPoint: crossing.point,
            host: assignment.endHost,
            mapScale: mapScale,
            configuration: configuration
        )

        var snappedPoints = cleanedPoints
        snappedPoints[0] = assignment.start.point
        snappedPoints[snappedPoints.count - 1] = assignment.end.point
        snappedPoints = removingConsecutiveDuplicates(snappedPoints)
        guard snappedPoints.count >= 2 else {
            throw RoadRampPlannerError.insufficientGeometry
        }

        let rampCenterline = RampCenterline(points: snappedPoints)
        let rampLengthMeters = mapScale.meters(
            forCanvasDistance: rampCenterline.totalLength
        )
        guard rampLengthMeters + 1e-9 >= configuration.minimumRampLengthMeters else {
            throw RoadRampPlannerError.rampTooShort(
                lengthMeters: rampLengthMeters,
                minimumMeters: configuration.minimumRampLengthMeters
            )
        }

        let rampID = UUID()
        let startTerminal = RoadRampTerminal(
            hostSourceRoadID: assignment.startHost.sourceRoadID,
            normalizedChainage: assignment.start.normalizedChainage,
            lastKnownPoint: assignment.start.point,
            level: assignment.start.road.level
        )
        let endTerminal = RoadRampTerminal(
            hostSourceRoadID: assignment.endHost.sourceRoadID,
            normalizedChainage: assignment.end.normalizedChainage,
            lastKnownPoint: assignment.end.point,
            level: assignment.end.road.level
        )

        let transition: RoadRampTransition?
        let segments: [RoadSegment]
        let priority = min(
            kind.defaultPriority,
            min(assignment.start.road.priority, assignment.end.road.priority)
        )
        if startTerminal.level == endTerminal.level {
            transition = nil
            segments = [
                RoadSegment(
                    id: rampID,
                    kind: kind,
                    level: startTerminal.level,
                    structure: assignment.start.road.structure,
                    points: snappedPoints,
                    direction: direction,
                    priority: priority,
                    sourceRoadID: rampID
                ),
            ]
        } else {
            let nearestCrossingFraction = rampCenterline.normalizedChainage(
                nearestTo: crossing.point
            )
            let transitionFraction = min(
                configuration.transitionFractionRange.upperBound,
                max(
                    configuration.transitionFractionRange.lowerBound,
                    nearestCrossingFraction
                )
            )
            let split = rampCenterline.split(atNormalizedChainage: transitionFraction)
            transition = RoadRampTransition(
                fromLevel: startTerminal.level,
                toLevel: endTerminal.level,
                chainageFraction: transitionFraction
            )
            segments = [
                RoadSegment(
                    id: rampID,
                    kind: kind,
                    level: startTerminal.level,
                    structure: assignment.start.road.structure,
                    points: split.before,
                    direction: direction,
                    priority: priority,
                    sourceRoadID: rampID
                ),
                RoadSegment(
                    kind: kind,
                    level: endTerminal.level,
                    structure: assignment.end.road.structure,
                    points: split.after,
                    direction: direction,
                    priority: priority,
                    sourceRoadID: rampID
                ),
            ]
        }

        let ramp = RoadRamp(
            id: rampID,
            start: startTerminal,
            end: endTerminal,
            direction: direction,
            transition: transition
        )
        let interchange = appending(
            ramp,
            crossing: crossing,
            existingInterchanges: existingInterchanges,
            mapScale: mapScale,
            reuseDistanceMeters: configuration.endpointSnapDistanceMeters
        )
        return RoadRampPlan(
            interchange: interchange,
            ramp: ramp,
            roadSegments: segments
        )
    }
}

private extension RoadRampPlanner {
    struct HostPiece: Sendable {
        var road: RoadSegment
        var startChainage: Double
        var centerline: RampCenterline
    }

    struct HostProjection: Sendable {
        var point: RoadPoint
        var distance: Double
        var chainage: Double
        var normalizedChainage: Double
        var road: RoadSegment
    }

    struct HostCenterline: Sendable {
        var sourceRoadID: UUID
        var pieces: [HostPiece]
        var totalLength: Double

        var roads: [RoadSegment] {
            pieces.map(\.road)
        }

        func projection(of point: RoadPoint) -> HostProjection {
            var best: HostProjection?
            for piece in pieces {
                let local = piece.centerline.projection(of: point)
                let chainage = piece.startChainage + local.chainage
                let candidate = HostProjection(
                    point: local.point,
                    distance: local.distance,
                    chainage: chainage,
                    normalizedChainage: totalLength > 1e-9
                        ? chainage / totalLength
                        : 0,
                    road: piece.road
                )
                if best == nil
                    || candidate.distance < best!.distance - 1e-9
                    || (
                        abs(candidate.distance - best!.distance) <= 1e-9
                            && candidate.chainage < best!.chainage
                    ) {
                    best = candidate
                }
            }
            return best!
        }
    }

    struct TerminalAssignment: Sendable {
        var startHost: HostCenterline
        var start: HostProjection
        var endHost: HostCenterline
        var end: HostProjection
    }

    static func validate(_ configuration: RoadRampPlannerConfiguration) throws {
        let values = [
            configuration.endpointSnapDistanceMeters,
            configuration.minimumDistanceFromCrossingMeters,
            configuration.minimumRampLengthMeters,
            configuration.transitionFractionRange.lowerBound,
            configuration.transitionFractionRange.upperBound,
        ]
        guard values.allSatisfy(\.isFinite),
              configuration.endpointSnapDistanceMeters >= 0,
              configuration.minimumDistanceFromCrossingMeters >= 0,
              configuration.minimumRampLengthMeters >= 0,
              configuration.transitionFractionRange.lowerBound > 0,
              configuration.transitionFractionRange.upperBound < 1,
              configuration.transitionFractionRange.lowerBound
                <= configuration.transitionFractionRange.upperBound
        else {
            throw RoadRampPlannerError.invalidConfiguration
        }
    }

    static func hostCenterline(
        sourceRoadID: UUID,
        roads: [RoadSegment]
    ) throws -> HostCenterline {
        var remaining = roads.filter {
            $0.sourceRoadID == sourceRoadID
                && $0.points.count >= 2
        }
        guard !remaining.isEmpty else {
            throw RoadRampPlannerError.missingHostRoad(sourceRoadID)
        }
        guard remaining.allSatisfy({
            $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite }
        }) else {
            throw RoadRampPlannerError.nonFiniteGeometry
        }

        var ordered: [RoadSegment] = []
        while !remaining.isEmpty {
            let startIndex = remaining.indices
                .filter { candidateIndex in
                    guard let candidateStart = remaining[candidateIndex].points.first else {
                        return false
                    }
                    return !remaining.indices.contains { otherIndex in
                        otherIndex != candidateIndex
                            && remaining[otherIndex].points.last?
                                .distance(to: candidateStart) ?? .infinity <= 1e-6
                    }
                }
                .min {
                    remaining[$0].id.uuidString < remaining[$1].id.uuidString
                } ?? remaining.indices.min {
                    remaining[$0].id.uuidString < remaining[$1].id.uuidString
                }!
            var current = remaining.remove(at: startIndex)
            ordered.append(current)
            while let currentEnd = current.points.last {
                let candidates = remaining.indices.filter { index in
                    guard let nextStart = remaining[index].points.first else {
                        return false
                    }
                    return nextStart.distance(to: currentEnd) <= 1e-6
                }
                guard let nextIndex = candidates.min(by: {
                    remaining[$0].id.uuidString
                        < remaining[$1].id.uuidString
                }) else {
                    break
                }
                current = remaining.remove(at: nextIndex)
                ordered.append(current)
            }
        }

        var chainage = 0.0
        var pieces: [HostPiece] = []
        for road in ordered {
            let centerline = RampCenterline(points: road.points)
            guard centerline.totalLength > 1e-9 else { continue }
            pieces.append(
                HostPiece(
                    road: road,
                    startChainage: chainage,
                    centerline: centerline
                )
            )
            chainage += centerline.totalLength
        }
        guard !pieces.isEmpty else {
            throw RoadRampPlannerError.missingHostRoad(sourceRoadID)
        }
        return HostCenterline(
            sourceRoadID: sourceRoadID,
            pieces: pieces,
            totalLength: chainage
        )
    }

    static func validate(host: HostCenterline) throws {
        if host.roads.contains(where: { $0.kind == .railway }) {
            throw RoadRampPlannerError.railwayHostUnsupported(host.sourceRoadID)
        }
    }

    static func validate(hostTerminal terminal: HostProjection) throws {
        if terminal.road.level == .tunnel || terminal.road.structure == .tunnel {
            throw RoadRampPlannerError.tunnelHostUnsupported(
                terminal.road.sourceRoadID
            )
        }
    }

    static func validateTerminalSeparation(
        _ terminal: HostProjection,
        role: RoadRampTerminalRole,
        crossingPoint: RoadPoint,
        host: HostCenterline,
        mapScale: MapScale,
        configuration: RoadRampPlannerConfiguration
    ) throws {
        let crossingProjection = host.projection(of: crossingPoint)
        let separation = mapScale.meters(
            forCanvasDistance: abs(
                terminal.chainage - crossingProjection.chainage
            )
        )
        guard separation + 1e-9
                >= configuration.minimumDistanceFromCrossingMeters
        else {
            throw RoadRampPlannerError.terminalTooCloseToCrossing(
                role: role,
                distanceMeters: separation
            )
        }
    }

    static func sanitized(_ points: [RoadPoint]) throws -> [RoadPoint] {
        guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else {
            throw RoadRampPlannerError.nonFiniteGeometry
        }
        return removingConsecutiveDuplicates(points)
    }

    static func removingConsecutiveDuplicates(
        _ points: [RoadPoint]
    ) -> [RoadPoint] {
        var result: [RoadPoint] = []
        for point in points
        where result.last?.distance(to: point) ?? .infinity > 1e-9 {
            result.append(point)
        }
        return result
    }

    static func appending(
        _ ramp: RoadRamp,
        crossing: RoadRelation,
        existingInterchanges: [RoadInterchange],
        mapScale: MapScale,
        reuseDistanceMeters: Double
    ) -> RoadInterchange {
        let upperID = crossing.upperRoadID!
        let lowerID = crossing.lowerRoadID!
        let pair = Set([upperID, lowerID])
        let reusable = existingInterchanges
            .filter {
                Set([
                    $0.anchor.upperSourceRoadID,
                    $0.anchor.lowerSourceRoadID,
                ]) == pair
            }
            .map {
                (
                    interchange: $0,
                    distanceMeters: mapScale.meters(
                        forCanvasDistance: $0.anchor.lastKnownPoint.distance(
                            to: crossing.point
                        )
                    )
                )
            }
            .filter {
                $0.distanceMeters <= reuseDistanceMeters + 1e-9
            }
            .min {
                if abs($0.distanceMeters - $1.distanceMeters) > 1e-9 {
                    return $0.distanceMeters < $1.distanceMeters
                }
                return $0.interchange.id.uuidString
                    < $1.interchange.id.uuidString
            }?
            .interchange

        let anchor = InterchangeCrossingAnchor(
            upperSourceRoadID: upperID,
            lowerSourceRoadID: lowerID,
            lastKnownPoint: crossing.point
        )
        if var reusable {
            reusable.anchor = anchor
            reusable.ramps.append(ramp)
            return reusable
        }
        return RoadInterchange(
            name: "立交 \(existingInterchanges.count + 1)",
            anchor: anchor,
            ramps: [ramp]
        )
    }
}

private struct RampCenterline: Sendable {
    struct Projection: Sendable {
        var point: RoadPoint
        var distance: Double
        var chainage: Double
    }

    var points: [RoadPoint]
    var cumulative: [Double]
    var totalLength: Double

    init(points: [RoadPoint]) {
        self.points = points
        var cumulative = [0.0]
        if points.count >= 2 {
            for index in 1..<points.count {
                cumulative.append(
                    cumulative[cumulative.count - 1]
                        + points[index - 1].distance(to: points[index])
                )
            }
        }
        self.cumulative = cumulative
        totalLength = cumulative.last ?? 0
    }

    func projection(of query: RoadPoint) -> Projection {
        if points.count == 1 {
            return Projection(
                point: points[0],
                distance: query.distance(to: points[0]),
                chainage: 0
            )
        }
        var best: Projection?
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let delta = end - start
            let lengthSquared = delta.x * delta.x + delta.y * delta.y
            guard lengthSquared > 1e-18 else { continue }
            let offset = query - start
            let fraction = min(
                1,
                max(
                    0,
                    (offset.x * delta.x + offset.y * delta.y)
                        / lengthSquared
                )
            )
            let point = start + delta * fraction
            let candidate = Projection(
                point: point,
                distance: query.distance(to: point),
                chainage: cumulative[index]
                    + sqrt(lengthSquared) * fraction
            )
            if best == nil
                || candidate.distance < best!.distance - 1e-9
                || (
                    abs(candidate.distance - best!.distance) <= 1e-9
                        && candidate.chainage < best!.chainage
                ) {
                best = candidate
            }
        }
        return best ?? Projection(
            point: points[0],
            distance: query.distance(to: points[0]),
            chainage: 0
        )
    }

    func normalizedChainage(nearestTo point: RoadPoint) -> Double {
        guard totalLength > 1e-9 else { return 0 }
        return projection(of: point).chainage / totalLength
    }

    func point(at chainage: Double) -> RoadPoint {
        guard let first = points.first else {
            return RoadPoint(x: 0, y: 0)
        }
        guard points.count >= 2 else { return first }
        let bounded = min(totalLength, max(0, chainage))
        for index in 0..<(points.count - 1)
        where bounded <= cumulative[index + 1] + 1e-9 {
            let length = cumulative[index + 1] - cumulative[index]
            guard length > 1e-9 else { return points[index] }
            let fraction = (bounded - cumulative[index]) / length
            return points[index]
                + (points[index + 1] - points[index]) * fraction
        }
        return points[points.count - 1]
    }

    func split(
        atNormalizedChainage fraction: Double
    ) -> (before: [RoadPoint], after: [RoadPoint]) {
        let splitChainage = totalLength * fraction
        let splitPoint = point(at: splitChainage)
        var before = [points[0]]
        var after = [splitPoint]
        for index in 1..<(points.count - 1) {
            let chainage = cumulative[index]
            if chainage < splitChainage - 1e-9 {
                before.append(points[index])
            } else if chainage > splitChainage + 1e-9 {
                after.append(points[index])
            }
        }
        if before.last != splitPoint {
            before.append(splitPoint)
        }
        if after.last != points[points.count - 1] {
            after.append(points[points.count - 1])
        }
        return (before, after)
    }
}
