import Foundation

public struct StrokeProcessingConfiguration: Sendable {
    public var minimumSampleDistance: Double
    public var smoothingPasses: Int
    public var simplificationTolerance: Double
    public var endpointSnapRadius: Double
    public var angleSnapTolerance: Double

    public init(
        minimumSampleDistance: Double = 1.5,
        smoothingPasses: Int = 2,
        simplificationTolerance: Double = 2.4,
        endpointSnapRadius: Double = 14,
        angleSnapTolerance: Double = .pi / 36
    ) {
        self.minimumSampleDistance = minimumSampleDistance
        self.smoothingPasses = smoothingPasses
        self.simplificationTolerance = simplificationTolerance
        self.endpointSnapRadius = endpointSnapRadius
        self.angleSnapTolerance = angleSnapTolerance
    }

    public static let standard = StrokeProcessingConfiguration()
}

public enum StrokeProcessor {
    public static func process(
        _ rawPoints: [RoadPoint],
        existingRoads: [RoadSegment],
        configuration: StrokeProcessingConfiguration = .standard
    ) -> [RoadPoint] {
        var points = removeNearDuplicates(
            rawPoints,
            minimumDistance: configuration.minimumSampleDistance
        )
        guard points.count >= 2 else { return [] }

        for _ in 0..<max(0, configuration.smoothingPasses) {
            points = chaikin(points)
        }
        points = simplify(points, tolerance: configuration.simplificationTolerance)
        points = snapNearlyStraightStroke(
            points,
            angleTolerance: configuration.angleSnapTolerance
        )
        points = snapEndpoints(
            points,
            to: existingRoads,
            radius: configuration.endpointSnapRadius
        )
        return points
    }

    public static func removeNearDuplicates(
        _ points: [RoadPoint],
        minimumDistance: Double
    ) -> [RoadPoint] {
        guard let first = points.first else { return [] }
        var result = [first]
        for point in points.dropFirst() where point.distance(to: result[result.count - 1]) >= minimumDistance {
            result.append(point)
        }
        if let last = points.last, last != result.last {
            result.append(last)
        }
        return result
    }

    public static func chaikin(_ points: [RoadPoint]) -> [RoadPoint] {
        guard points.count > 2 else { return points }
        var result = [points[0]]
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            result.append(start * 0.75 + end * 0.25)
            result.append(start * 0.25 + end * 0.75)
        }
        result.append(points[points.count - 1])
        return result
    }

    public static func simplify(_ points: [RoadPoint], tolerance: Double) -> [RoadPoint] {
        guard points.count > 2 else { return points }

        let start = points[0]
        let end = points[points.count - 1]
        var farthestDistance = 0.0
        var farthestIndex = 0

        for index in 1..<(points.count - 1) {
            let distance = perpendicularDistance(points[index], lineStart: start, lineEnd: end)
            if distance > farthestDistance {
                farthestDistance = distance
                farthestIndex = index
            }
        }

        guard farthestDistance > tolerance else { return [start, end] }
        let left = simplify(Array(points[0...farthestIndex]), tolerance: tolerance)
        let right = simplify(Array(points[farthestIndex...]), tolerance: tolerance)
        return Array(left.dropLast()) + right
    }

    private static func snapEndpoints(
        _ points: [RoadPoint],
        to roads: [RoadSegment],
        radius: Double
    ) -> [RoadPoint] {
        guard !roads.isEmpty else { return points }
        var result = points
        result[0] = nearestPoint(to: result[0], on: roads, radius: radius) ?? result[0]
        let lastIndex = result.count - 1
        result[lastIndex] = nearestPoint(to: result[lastIndex], on: roads, radius: radius) ?? result[lastIndex]
        return result
    }

    private static func nearestPoint(
        to point: RoadPoint,
        on roads: [RoadSegment],
        radius: Double
    ) -> RoadPoint? {
        var candidates: [RoadPoint] = []
        for road in roads {
            candidates.append(contentsOf: road.points)
            for (start, end) in zip(road.points, road.points.dropFirst()) {
                candidates.append(project(point, ontoSegmentFrom: start, to: end))
            }
        }
        return candidates
            .map { candidate in (candidate, point.distance(to: candidate)) }
            .filter { $0.1 <= radius }
            .min { $0.1 < $1.1 }?
            .0
    }

    private static func project(
        _ point: RoadPoint,
        ontoSegmentFrom start: RoadPoint,
        to end: RoadPoint
    ) -> RoadPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let denominator = dx * dx + dy * dy
        guard denominator > 0 else { return start }
        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / denominator))
        return RoadPoint(x: start.x + t * dx, y: start.y + t * dy)
    }

    private static func snapNearlyStraightStroke(
        _ points: [RoadPoint],
        angleTolerance: Double
    ) -> [RoadPoint] {
        guard points.count >= 2 else { return points }
        let start = points[0]
        let end = points[points.count - 1]
        let length = start.distance(to: end)
        guard length > 0 else { return points }

        let maximumDeviation = points
            .map { perpendicularDistance($0, lineStart: start, lineEnd: end) }
            .max() ?? 0
        guard maximumDeviation / length < 0.04 else { return points }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let increment = Double.pi / 12
        let snappedAngle = (angle / increment).rounded() * increment
        guard abs(normalizedAngle(angle - snappedAngle)) <= angleTolerance else {
            return [start, end]
        }

        return [
            start,
            RoadPoint(
                x: start.x + cos(snappedAngle) * length,
                y: start.y + sin(snappedAngle) * length
            ),
        ]
    }

    private static func normalizedAngle(_ angle: Double) -> Double {
        atan2(sin(angle), cos(angle))
    }

    private static func perpendicularDistance(
        _ point: RoadPoint,
        lineStart: RoadPoint,
        lineEnd: RoadPoint
    ) -> Double {
        let dx = lineEnd.x - lineStart.x
        let dy = lineEnd.y - lineStart.y
        let denominator = dx * dx + dy * dy
        guard denominator > 0 else { return point.distance(to: lineStart) }
        let t = max(0, min(1, ((point.x - lineStart.x) * dx + (point.y - lineStart.y) * dy) / denominator))
        let projection = RoadPoint(x: lineStart.x + t * dx, y: lineStart.y + t * dy)
        return point.distance(to: projection)
    }
}
