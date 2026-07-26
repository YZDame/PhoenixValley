import Foundation

/// How a final road segment was assessed for construction feasibility.
///
/// Bridge and tunnel grades are deliberately excluded here because
/// `RoadEngineeringPlanner` already evaluates their persisted vertical
/// profiles. An elevated segment does not yet have a persisted profile, so its
/// axis is conservatively modeled as a straight line between its two ground
/// attachment elevations.
public enum RoadConstructionAssessmentStrategy: String, Codable, Hashable, Sendable {
    case groundLocalTerrainProfile
    case elevatedStraightAxisBetweenEndpoints
    case handledByStructureEngineering
}

public enum RoadConstructionIssueKind: String, Codable, Hashable, Sendable {
    case localGradeAboveLimit
    case groundRoadInWater
    case elevatedAxisGradeAboveLimit
}

public enum RoadConstructionIssueSeverity: String, Codable, Hashable, Sendable {
    case error
}

public enum RoadConstructionIssueComparison: String, Codable, Hashable, Sendable {
    case atMost
    case greaterThan
}

public enum RoadConstructionIssueUnit: String, Codable, Hashable, Sendable {
    case grade
    case meters
}

/// Physical sampling rules for final-road construction checks.
///
/// Ground elevations are sampled at equal metre intervals. A centered median
/// removes terrain spikes shorter than half the smoothing window, then local
/// grades are measured with a centered secant of `gradeWindowMeters`. Each
/// elementary sample interval is classified independently before adjacent
/// violations are merged.
public struct RoadConstructionFeasibilityConfiguration: Codable, Hashable, Sendable {
    public var sampleSpacingMeters: Double
    public var elevationMedianWindowMeters: Double
    public var gradeWindowMeters: Double
    public var minimumIssueLengthMeters: Double
    public var maximumMergeGapMeters: Double
    public var gradeComparisonTolerance: Double
    public var engineering: RoadEngineeringConfiguration

    public init(
        sampleSpacingMeters: Double = 5,
        elevationMedianWindowMeters: Double = 25,
        gradeWindowMeters: Double = 30,
        minimumIssueLengthMeters: Double = 10,
        maximumMergeGapMeters: Double = 5,
        gradeComparisonTolerance: Double = 0.0005,
        engineering: RoadEngineeringConfiguration = .standard
    ) {
        self.sampleSpacingMeters = sampleSpacingMeters
        self.elevationMedianWindowMeters = elevationMedianWindowMeters
        self.gradeWindowMeters = gradeWindowMeters
        self.minimumIssueLengthMeters = minimumIssueLengthMeters
        self.maximumMergeGapMeters = maximumMergeGapMeters
        self.gradeComparisonTolerance = gradeComparisonTolerance
        self.engineering = engineering
    }

    public static let standard = RoadConstructionFeasibilityConfiguration()
}

/// One merged interval that cannot be built as its current road structure.
///
/// Chainages are local to `roadID` and always expressed in metres.
/// `centerline` includes the exact interval endpoints and every original road
/// vertex inside the interval, so clients can highlight the real curved path.
public struct RoadConstructionIssue: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var kind: RoadConstructionIssueKind
    public var severity: RoadConstructionIssueSeverity
    public var comparison: RoadConstructionIssueComparison
    public var unit: RoadConstructionIssueUnit
    public var roadID: UUID
    public var sourceRoadID: UUID
    public var roadKind: RoadKind
    public var structure: RoadStructureType
    public var startChainageMeters: Double
    public var endChainageMeters: Double
    public var startPoint: RoadPoint
    public var endPoint: RoadPoint
    public var centerline: [RoadPoint]
    public var measuredValue: Double
    public var limitValue: Double

    public init(
        id: String? = nil,
        kind: RoadConstructionIssueKind,
        severity: RoadConstructionIssueSeverity = .error,
        comparison: RoadConstructionIssueComparison,
        unit: RoadConstructionIssueUnit,
        roadID: UUID,
        sourceRoadID: UUID,
        roadKind: RoadKind,
        structure: RoadStructureType,
        startChainageMeters: Double,
        endChainageMeters: Double,
        startPoint: RoadPoint,
        endPoint: RoadPoint,
        centerline: [RoadPoint],
        measuredValue: Double,
        limitValue: Double
    ) {
        self.id = id ?? Self.stableID(
            kind: kind,
            roadID: roadID,
            sourceRoadID: sourceRoadID,
            structure: structure,
            startChainageMeters: startChainageMeters,
            endChainageMeters: endChainageMeters
        )
        self.kind = kind
        self.severity = severity
        self.comparison = comparison
        self.unit = unit
        self.roadID = roadID
        self.sourceRoadID = sourceRoadID
        self.roadKind = roadKind
        self.structure = structure
        self.startChainageMeters = startChainageMeters
        self.endChainageMeters = endChainageMeters
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.centerline = centerline
        self.measuredValue = measuredValue
        self.limitValue = limitValue
    }

    /// Stable across repeated analyses and equivalent map scales.
    ///
    /// Millimetre chainage quantization prevents insignificant floating-point
    /// interpolation differences from changing UI identity.
    public static func stableID(
        kind: RoadConstructionIssueKind,
        roadID: UUID,
        sourceRoadID: UUID,
        structure: RoadStructureType,
        startChainageMeters: Double,
        endChainageMeters: Double
    ) -> String {
        let startMillimeters = Int64((startChainageMeters * 1_000).rounded())
        let endMillimeters = Int64((endChainageMeters * 1_000).rounded())
        return [
            "construction",
            roadID.uuidString.lowercased(),
            sourceRoadID.uuidString.lowercased(),
            structure.rawValue,
            kind.rawValue,
            String(startMillimeters),
            String(endMillimeters),
        ].joined(separator: "-")
    }
}

public struct RoadConstructionRoadReport: Codable, Hashable, Sendable {
    public var roadID: UUID
    public var sourceRoadID: UUID
    public var roadKind: RoadKind
    public var structure: RoadStructureType
    public var strategy: RoadConstructionAssessmentStrategy
    public var roadLengthMeters: Double
    public var sampleCount: Int
    public var maximumPermittedGrade: Double
    public var issues: [RoadConstructionIssue]

    public init(
        roadID: UUID,
        sourceRoadID: UUID,
        roadKind: RoadKind,
        structure: RoadStructureType,
        strategy: RoadConstructionAssessmentStrategy,
        roadLengthMeters: Double,
        sampleCount: Int,
        maximumPermittedGrade: Double,
        issues: [RoadConstructionIssue]
    ) {
        self.roadID = roadID
        self.sourceRoadID = sourceRoadID
        self.roadKind = roadKind
        self.structure = structure
        self.strategy = strategy
        self.roadLengthMeters = roadLengthMeters
        self.sampleCount = sampleCount
        self.maximumPermittedGrade = maximumPermittedGrade
        self.issues = issues
    }

    public var isFeasible: Bool {
        !issues.contains { $0.severity == .error }
    }
}

public struct RoadConstructionFeasibilityReport: Codable, Hashable, Sendable {
    public var roads: [RoadConstructionRoadReport]

    public init(roads: [RoadConstructionRoadReport]) {
        self.roads = roads
    }

    public var issues: [RoadConstructionIssue] {
        roads.flatMap(\.issues)
    }

    public var isFeasible: Bool {
        roads.allSatisfy(\.isFeasible)
    }

    public func report(forRoadID roadID: UUID) -> RoadConstructionRoadReport? {
        roads.first { $0.roadID == roadID }
    }
}

public enum RoadConstructionFeasibilityAnalyzer {
    public static func evaluate(
        roads: [RoadSegment],
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration = .standard
    ) -> RoadConstructionFeasibilityReport {
        RoadConstructionFeasibilityReport(
            roads: roads.map {
                evaluate(
                    road: $0,
                    terrain: terrain,
                    mapScale: mapScale,
                    configuration: configuration
                )
            }
        )
    }

    public static func evaluate(
        road: RoadSegment,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration = .standard
    ) -> RoadConstructionRoadReport {
        let polyline = ConstructionPolyline(points: road.points)
        let lengthMeters = mapScale.meters(forCanvasDistance: polyline.totalLength)
        let maximumGrade = configuration.engineering
            .limits(for: road.kind)
            .maximumApproachGrade

        switch road.structure {
        case .bridge, .tunnel:
            return RoadConstructionRoadReport(
                roadID: road.id,
                sourceRoadID: road.sourceRoadID,
                roadKind: road.kind,
                structure: road.structure,
                strategy: .handledByStructureEngineering,
                roadLengthMeters: lengthMeters,
                sampleCount: 0,
                maximumPermittedGrade: maximumGrade,
                issues: []
            )

        case .elevated:
            return elevatedReport(
                road: road,
                polyline: polyline,
                lengthMeters: lengthMeters,
                maximumGrade: maximumGrade,
                terrain: terrain,
                mapScale: mapScale,
                configuration: configuration
            )

        case .ground:
            return groundReport(
                road: road,
                polyline: polyline,
                lengthMeters: lengthMeters,
                maximumGrade: maximumGrade,
                terrain: terrain,
                mapScale: mapScale,
                configuration: configuration
            )
        }
    }

    private static func groundReport(
        road: RoadSegment,
        polyline: ConstructionPolyline,
        lengthMeters: Double,
        maximumGrade: Double,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration
    ) -> RoadConstructionRoadReport {
        let samples = makeSamples(
            polyline: polyline,
            lengthMeters: lengthMeters,
            terrain: terrain,
            mapScale: mapScale,
            configuration: configuration
        )
        guard samples.count >= 2 else {
            return RoadConstructionRoadReport(
                roadID: road.id,
                sourceRoadID: road.sourceRoadID,
                roadKind: road.kind,
                structure: road.structure,
                strategy: .groundLocalTerrainProfile,
                roadLengthMeters: lengthMeters,
                sampleCount: samples.count,
                maximumPermittedGrade: maximumGrade,
                issues: []
            )
        }

        let smoothedElevations = medianSmoothedElevations(
            samples: samples,
            windowMeters: max(0, configuration.elevationMedianWindowMeters)
        )
        let gradeViolations = localGradeViolations(
            samples: samples,
            smoothedElevations: smoothedElevations,
            maximumGrade: maximumGrade,
            configuration: configuration
        )
        let waterViolations = groundWaterViolations(
            samples: samples,
            polyline: polyline,
            terrain: terrain,
            mapScale: mapScale,
            configuration: configuration
        )
        let mergedGrades = merge(
            gradeViolations,
            maximumGapMeters: max(0, configuration.maximumMergeGapMeters),
            minimumLengthMeters: max(0, configuration.minimumIssueLengthMeters),
            extreme: .maximum
        )
        let mergedWater = merge(
            waterViolations,
            maximumGapMeters: max(0, configuration.maximumMergeGapMeters),
            minimumLengthMeters: max(0, configuration.minimumIssueLengthMeters),
            extreme: .minimum
        )

        let gradeIssues = mergedGrades.map {
            issue(
                kind: .localGradeAboveLimit,
                comparison: .atMost,
                unit: .grade,
                road: road,
                interval: $0,
                limitValue: maximumGrade,
                polyline: polyline,
                mapScale: mapScale
            )
        }
        let waterLimit = (
            terrain.waterLevel + configuration.engineering.waterTolerance
        ) * configuration.engineering.elevationScaleMeters
        let waterIssues = mergedWater.map {
            issue(
                kind: .groundRoadInWater,
                comparison: .greaterThan,
                unit: .meters,
                road: road,
                interval: $0,
                limitValue: waterLimit,
                polyline: polyline,
                mapScale: mapScale
            )
        }

        return RoadConstructionRoadReport(
            roadID: road.id,
            sourceRoadID: road.sourceRoadID,
            roadKind: road.kind,
            structure: road.structure,
            strategy: .groundLocalTerrainProfile,
            roadLengthMeters: lengthMeters,
            sampleCount: samples.count,
            maximumPermittedGrade: maximumGrade,
            issues: (gradeIssues + waterIssues).sorted {
                if abs($0.startChainageMeters - $1.startChainageMeters) > 1e-9 {
                    return $0.startChainageMeters < $1.startChainageMeters
                }
                return $0.kind.rawValue < $1.kind.rawValue
            }
        )
    }

    private static func elevatedReport(
        road: RoadSegment,
        polyline: ConstructionPolyline,
        lengthMeters: Double,
        maximumGrade: Double,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration
    ) -> RoadConstructionRoadReport {
        guard lengthMeters > 1e-9,
              let first = road.points.first,
              let last = road.points.last
        else {
            return RoadConstructionRoadReport(
                roadID: road.id,
                sourceRoadID: road.sourceRoadID,
                roadKind: road.kind,
                structure: road.structure,
                strategy: .elevatedStraightAxisBetweenEndpoints,
                roadLengthMeters: lengthMeters,
                sampleCount: road.points.isEmpty ? 0 : 1,
                maximumPermittedGrade: maximumGrade,
                issues: []
            )
        }

        let elevationScale = configuration.engineering.elevationScaleMeters
        let startElevation = terrain.normalizedElevation(at: first) * elevationScale
        let endElevation = terrain.normalizedElevation(at: last) * elevationScale
        let grade = abs(endElevation - startElevation) / lengthMeters
        let issues: [RoadConstructionIssue]
        if grade > maximumGrade + max(0, configuration.gradeComparisonTolerance) {
            let interval = RawConstructionInterval(
                startChainageMeters: 0,
                endChainageMeters: lengthMeters,
                measuredValue: grade
            )
            issues = [
                issue(
                    kind: .elevatedAxisGradeAboveLimit,
                    comparison: .atMost,
                    unit: .grade,
                    road: road,
                    interval: interval,
                    limitValue: maximumGrade,
                    polyline: polyline,
                    mapScale: mapScale
                ),
            ]
        } else {
            issues = []
        }

        return RoadConstructionRoadReport(
            roadID: road.id,
            sourceRoadID: road.sourceRoadID,
            roadKind: road.kind,
            structure: road.structure,
            strategy: .elevatedStraightAxisBetweenEndpoints,
            roadLengthMeters: lengthMeters,
            sampleCount: 2,
            maximumPermittedGrade: maximumGrade,
            issues: issues
        )
    }

    private static func makeSamples(
        polyline: ConstructionPolyline,
        lengthMeters: Double,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration
    ) -> [ConstructionTerrainSample] {
        guard polyline.totalLength > 1e-9, lengthMeters > 1e-9 else {
            if let point = polyline.points.first {
                let normalized = terrain.normalizedElevation(at: point)
                return [
                    ConstructionTerrainSample(
                        chainageMeters: 0,
                        point: point,
                        normalizedElevation: normalized,
                        elevationMeters: normalized
                            * configuration.engineering.elevationScaleMeters
                    ),
                ]
            }
            return []
        }

        let requestedSpacing = max(0.25, configuration.sampleSpacingMeters)
        let intervalCount = max(1, Int(ceil(lengthMeters / requestedSpacing)))
        return (0...intervalCount).map { index in
            let fraction = Double(index) / Double(intervalCount)
            let chainageMeters = lengthMeters * fraction
            let canvasDistance = polyline.totalLength * fraction
            let point = polyline.sample(atCanvasDistance: canvasDistance)
            let normalized = terrain.normalizedElevation(at: point)
            return ConstructionTerrainSample(
                chainageMeters: chainageMeters,
                point: point,
                normalizedElevation: normalized,
                elevationMeters: normalized
                    * configuration.engineering.elevationScaleMeters
            )
        }
    }

    private static func medianSmoothedElevations(
        samples: [ConstructionTerrainSample],
        windowMeters: Double
    ) -> [Double] {
        guard samples.count >= 3, windowMeters > 1e-9 else {
            return samples.map(\.elevationMeters)
        }
        let radius = windowMeters / 2
        return samples.indices.map { index in
            let center = samples[index].chainageMeters
            let values = samples.lazy
                .filter { abs($0.chainageMeters - center) <= radius + 1e-9 }
                .map(\.elevationMeters)
                .sorted()
            guard !values.isEmpty else { return samples[index].elevationMeters }
            let middle = values.count / 2
            if values.count.isMultiple(of: 2) {
                return (values[middle - 1] + values[middle]) / 2
            }
            return values[middle]
        }
    }

    private static func localGradeViolations(
        samples: [ConstructionTerrainSample],
        smoothedElevations: [Double],
        maximumGrade: Double,
        configuration: RoadConstructionFeasibilityConfiguration
    ) -> [RawConstructionInterval] {
        guard samples.count == smoothedElevations.count,
              samples.count >= 2,
              let totalLength = samples.last?.chainageMeters,
              totalLength > 1e-9
        else { return [] }

        let elementarySpacing = totalLength / Double(samples.count - 1)
        let windowMeters = max(
            elementarySpacing,
            configuration.gradeWindowMeters
        )
        let tolerance = max(0, configuration.gradeComparisonTolerance)
        var result: [RawConstructionInterval] = []
        result.reserveCapacity(samples.count - 1)

        for index in 0..<(samples.count - 1) {
            let start = samples[index].chainageMeters
            let end = samples[index + 1].chainageMeters
            let midpoint = (start + end) / 2
            let left = max(0, midpoint - windowMeters / 2)
            let right = min(totalLength, midpoint + windowMeters / 2)
            guard right > left + 1e-9 else { continue }
            let leftElevation = interpolatedElevation(
                at: left,
                samples: samples,
                values: smoothedElevations
            )
            let rightElevation = interpolatedElevation(
                at: right,
                samples: samples,
                values: smoothedElevations
            )
            let grade = abs(rightElevation - leftElevation) / (right - left)
            if grade > maximumGrade + tolerance {
                result.append(
                    RawConstructionInterval(
                        startChainageMeters: start,
                        endChainageMeters: end,
                        measuredValue: grade
                    )
                )
            }
        }
        return result
    }

    private static func groundWaterViolations(
        samples: [ConstructionTerrainSample],
        polyline: ConstructionPolyline,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadConstructionFeasibilityConfiguration
    ) -> [RawConstructionInterval] {
        guard samples.count >= 2 else { return [] }
        let threshold = terrain.waterLevel + configuration.engineering.waterTolerance
        let elevationScale = configuration.engineering.elevationScaleMeters
        return (0..<(samples.count - 1)).compactMap { index in
            let start = samples[index].chainageMeters
            let end = samples[index + 1].chainageMeters
            let midpoint = (start + end) / 2
            let point = polyline.sample(
                atCanvasDistance: mapScale.canvasDistance(forMeters: midpoint)
            )
            let normalized = terrain.normalizedElevation(at: point)
            guard normalized <= threshold else { return nil }
            return RawConstructionInterval(
                startChainageMeters: start,
                endChainageMeters: end,
                measuredValue: normalized * elevationScale
            )
        }
    }

    private static func interpolatedElevation(
        at chainageMeters: Double,
        samples: [ConstructionTerrainSample],
        values: [Double]
    ) -> Double {
        guard samples.count >= 2,
              samples.count == values.count,
              let totalLength = samples.last?.chainageMeters,
              totalLength > 1e-9
        else { return values.first ?? 0 }
        let bounded = min(totalLength, max(0, chainageMeters))
        let position = bounded / totalLength * Double(samples.count - 1)
        let lower = min(samples.count - 1, Int(position.rounded(.down)))
        let upper = min(samples.count - 1, lower + 1)
        guard upper > lower else { return values[lower] }
        let fraction = position - Double(lower)
        return values[lower] * (1 - fraction) + values[upper] * fraction
    }

    private static func issue(
        kind: RoadConstructionIssueKind,
        comparison: RoadConstructionIssueComparison,
        unit: RoadConstructionIssueUnit,
        road: RoadSegment,
        interval: RawConstructionInterval,
        limitValue: Double,
        polyline: ConstructionPolyline,
        mapScale: MapScale
    ) -> RoadConstructionIssue {
        let startCanvas = mapScale.canvasDistance(
            forMeters: interval.startChainageMeters
        )
        let endCanvas = mapScale.canvasDistance(
            forMeters: interval.endChainageMeters
        )
        let centerline = polyline.slice(
            fromCanvasDistance: startCanvas,
            toCanvasDistance: endCanvas
        )
        let startPoint = centerline.first
            ?? polyline.sample(atCanvasDistance: startCanvas)
        let endPoint = centerline.last
            ?? polyline.sample(atCanvasDistance: endCanvas)
        return RoadConstructionIssue(
            kind: kind,
            comparison: comparison,
            unit: unit,
            roadID: road.id,
            sourceRoadID: road.sourceRoadID,
            roadKind: road.kind,
            structure: road.structure,
            startChainageMeters: interval.startChainageMeters,
            endChainageMeters: interval.endChainageMeters,
            startPoint: startPoint,
            endPoint: endPoint,
            centerline: centerline,
            measuredValue: interval.measuredValue,
            limitValue: limitValue
        )
    }

    private enum MeasurementExtreme {
        case minimum
        case maximum
    }

    private static func merge(
        _ intervals: [RawConstructionInterval],
        maximumGapMeters: Double,
        minimumLengthMeters: Double,
        extreme: MeasurementExtreme
    ) -> [RawConstructionInterval] {
        guard var current = intervals.first else { return [] }
        var merged: [RawConstructionInterval] = []

        func combinedMeasurement(_ lhs: Double, _ rhs: Double) -> Double {
            switch extreme {
            case .minimum: min(lhs, rhs)
            case .maximum: max(lhs, rhs)
            }
        }

        for next in intervals.dropFirst() {
            if next.startChainageMeters
                <= current.endChainageMeters + maximumGapMeters + 1e-9 {
                current.endChainageMeters = max(
                    current.endChainageMeters,
                    next.endChainageMeters
                )
                current.measuredValue = combinedMeasurement(
                    current.measuredValue,
                    next.measuredValue
                )
            } else {
                if current.lengthMeters + 1e-9 >= minimumLengthMeters {
                    merged.append(current)
                }
                current = next
            }
        }
        if current.lengthMeters + 1e-9 >= minimumLengthMeters {
            merged.append(current)
        }
        return merged
    }
}

private struct ConstructionTerrainSample {
    var chainageMeters: Double
    var point: RoadPoint
    var normalizedElevation: Double
    var elevationMeters: Double
}

private struct RawConstructionInterval {
    var startChainageMeters: Double
    var endChainageMeters: Double
    var measuredValue: Double

    var lengthMeters: Double {
        max(0, endChainageMeters - startChainageMeters)
    }
}

private struct ConstructionPolyline {
    var points: [RoadPoint]
    var cumulativeCanvasDistances: [Double]
    var totalLength: Double

    init(points: [RoadPoint]) {
        self.points = points
        var cumulative = [0.0]
        cumulative.reserveCapacity(max(1, points.count))
        for pair in zip(points, points.dropFirst()) {
            cumulative.append(cumulative.last! + pair.0.distance(to: pair.1))
        }
        cumulativeCanvasDistances = cumulative
        totalLength = cumulative.last ?? 0
    }

    func sample(atCanvasDistance distance: Double) -> RoadPoint {
        guard let first = points.first else {
            return RoadPoint(x: 0, y: 0)
        }
        guard points.count >= 2, totalLength > 1e-9 else { return first }
        let target = min(totalLength, max(0, distance))
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let segmentLength = start.distance(to: end)
            guard segmentLength > 1e-9 else { continue }
            if target <= cumulativeCanvasDistances[index + 1] + 1e-9 {
                let fraction = min(
                    1,
                    max(
                        0,
                        (target - cumulativeCanvasDistances[index])
                            / segmentLength
                    )
                )
                return RoadPoint(
                    x: start.x + (end.x - start.x) * fraction,
                    y: start.y + (end.y - start.y) * fraction
                )
            }
        }
        return points.last ?? first
    }

    func slice(
        fromCanvasDistance start: Double,
        toCanvasDistance end: Double
    ) -> [RoadPoint] {
        guard !points.isEmpty else { return [] }
        let boundedStart = min(totalLength, max(0, start))
        let boundedEnd = min(totalLength, max(boundedStart, end))
        var result = [sample(atCanvasDistance: boundedStart)]
        for index in points.indices.dropFirst() {
            let chainage = cumulativeCanvasDistances[index]
            if chainage > boundedStart + 1e-9
                && chainage < boundedEnd - 1e-9 {
                result.append(points[index])
            }
        }
        let endPoint = sample(atCanvasDistance: boundedEnd)
        if result.last?.distance(to: endPoint) ?? .infinity > 1e-9 {
            result.append(endPoint)
        }
        return result
    }
}
