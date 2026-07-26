import Foundation

/// Engineering semantics for an automatically planned span.
///
/// `bridge` is deliberately independent from `RoadLevel.elevated`: a bridge may
/// be elevated, but it also carries water-crossing constraints and bridgehead
/// transitions that a generic viaduct does not.
public enum RoadStructureType: String, Codable, CaseIterable, Hashable, Sendable {
    case ground
    case bridge
    case tunnel
    case elevated
}

public enum AutoStructureTrigger: String, Codable, CaseIterable, Hashable, Sendable {
    case water
    case steepGrade
    case mountainRelief
    case tunnelLengthAdvantage
    case roadCrossing
    case roadPriority
    case crossingAngle
    case existingVerticalSeparation
}

public struct StructureSampleRange: Codable, Hashable, Sendable {
    public var startSampleIndex: Int
    public var endSampleIndex: Int
    public var startDistance: Double
    public var endDistance: Double

    public init(
        startSampleIndex: Int,
        endSampleIndex: Int,
        startDistance: Double,
        endDistance: Double
    ) {
        self.startSampleIndex = startSampleIndex
        self.endSampleIndex = endSampleIndex
        self.startDistance = startDistance
        self.endDistance = endDistance
    }

    public var length: Double {
        max(0, endDistance - startDistance)
    }
}

public struct AutoStructureMetrics: Codable, Hashable, Sendable {
    public var minimumElevation: Double
    public var maximumElevation: Double
    public var maximumAbsoluteGrade: Double
    public var maximumRidgeProminence: Double
    public var surfaceLength: Double
    public var directStructureLength: Double
    public var lengthAdvantageRatio: Double
    public var waterSampleCount: Int

    public init(
        minimumElevation: Double,
        maximumElevation: Double,
        maximumAbsoluteGrade: Double,
        maximumRidgeProminence: Double,
        surfaceLength: Double,
        directStructureLength: Double,
        lengthAdvantageRatio: Double,
        waterSampleCount: Int
    ) {
        self.minimumElevation = minimumElevation
        self.maximumElevation = maximumElevation
        self.maximumAbsoluteGrade = maximumAbsoluteGrade
        self.maximumRidgeProminence = maximumRidgeProminence
        self.surfaceLength = surfaceLength
        self.directStructureLength = directStructureLength
        self.lengthAdvantageRatio = lengthAdvantageRatio
        self.waterSampleCount = waterSampleCount
    }
}

public enum StructureTransitionRole: String, Codable, Hashable, Sendable {
    case entrance
    case exit
}

public enum StructureTransitionKind: String, Codable, Hashable, Sendable {
    case bridgehead
    case tunnelPortal
    case elevatedRamp
}

public enum StructureTransitionWarning: String, Codable, Hashable, Sendable {
    case steepApproach
    case belowPreferredStructureLength
}

public struct StructureTransitionHint: Codable, Hashable, Sendable {
    public var role: StructureTransitionRole
    public var kind: StructureTransitionKind
    public var point: RoadPoint
    public var distance: Double
    public var terrainElevation: Double
    public var approachGrade: Double
    public var recommendedApproachLength: Double
    public var warnings: Set<StructureTransitionWarning>

    public init(
        role: StructureTransitionRole,
        kind: StructureTransitionKind,
        point: RoadPoint,
        distance: Double,
        terrainElevation: Double,
        approachGrade: Double,
        recommendedApproachLength: Double,
        warnings: Set<StructureTransitionWarning> = []
    ) {
        self.role = role
        self.kind = kind
        self.point = point
        self.distance = distance
        self.terrainElevation = terrainElevation
        self.approachGrade = approachGrade
        self.recommendedApproachLength = recommendedApproachLength
        self.warnings = warnings
    }
}

public struct AutoStructureEvidence: Codable, Hashable, Sendable {
    public var triggers: Set<AutoStructureTrigger>
    public var sampleRange: StructureSampleRange
    public var metrics: AutoStructureMetrics
    public var relatedRoadIDs: [UUID]

    public init(
        triggers: Set<AutoStructureTrigger>,
        sampleRange: StructureSampleRange,
        metrics: AutoStructureMetrics,
        relatedRoadIDs: [UUID] = []
    ) {
        self.triggers = triggers
        self.sampleRange = sampleRange
        self.metrics = metrics
        self.relatedRoadIDs = relatedRoadIDs
    }
}

public struct AutoStructureCandidate: Identifiable, Codable, Hashable, Sendable {
    /// Stable while source road geometry and sampling configuration are unchanged.
    public var id: String
    public var sourceRoadID: UUID
    public var sourceEdgeID: UUID
    public var structure: RoadStructureType
    public var startPoint: RoadPoint
    public var endPoint: RoadPoint
    public var evidence: AutoStructureEvidence
    public var entrance: StructureTransitionHint
    public var exit: StructureTransitionHint

    public init(
        id: String,
        sourceRoadID: UUID,
        sourceEdgeID: UUID,
        structure: RoadStructureType,
        startPoint: RoadPoint,
        endPoint: RoadPoint,
        evidence: AutoStructureEvidence,
        entrance: StructureTransitionHint,
        exit: StructureTransitionHint
    ) {
        self.id = id
        self.sourceRoadID = sourceRoadID
        self.sourceEdgeID = sourceEdgeID
        self.structure = structure
        self.startPoint = startPoint
        self.endPoint = endPoint
        self.evidence = evidence
        self.entrance = entrance
        self.exit = exit
    }
}

public struct TerrainRoadSample: Codable, Hashable, Sendable {
    public var index: Int
    public var distance: Double
    public var point: RoadPoint
    public var normalizedElevation: Double
    public var isWater: Bool
    /// Signed rise/run in model units after applying `elevationScale`.
    public var longitudinalGrade: Double
    /// Positive on a ridge, negative in a valley.
    public var ridgeProminence: Double

    public init(
        index: Int,
        distance: Double,
        point: RoadPoint,
        normalizedElevation: Double,
        isWater: Bool,
        longitudinalGrade: Double,
        ridgeProminence: Double
    ) {
        self.index = index
        self.distance = distance
        self.point = point
        self.normalizedElevation = normalizedElevation
        self.isWater = isWater
        self.longitudinalGrade = longitudinalGrade
        self.ridgeProminence = ridgeProminence
    }
}

public enum RoadCrossingTreatment: String, Codable, Hashable, Sendable {
    case atGrade
    case elevated
    case interchange
    case preserveExistingSeparation
    case deferToPrimaryStructure
}

public struct RoadCrossingSuggestion: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceRoadID: UUID
    public var sourceEdgeID: UUID
    public var existingRoadID: UUID
    public var existingEdgeID: UUID
    public var point: RoadPoint
    public var sourceDistance: Double
    public var crossingAngle: Double
    public var sourcePriority: RoadPriority
    public var existingPriority: RoadPriority
    public var existingLevel: RoadLevel
    public var treatment: RoadCrossingTreatment
    public var triggers: Set<AutoStructureTrigger>
    public var protectedStructure: RoadStructureType?

    public init(
        id: String,
        sourceRoadID: UUID,
        sourceEdgeID: UUID,
        existingRoadID: UUID,
        existingEdgeID: UUID,
        point: RoadPoint,
        sourceDistance: Double,
        crossingAngle: Double,
        sourcePriority: RoadPriority,
        existingPriority: RoadPriority,
        existingLevel: RoadLevel,
        treatment: RoadCrossingTreatment,
        triggers: Set<AutoStructureTrigger>,
        protectedStructure: RoadStructureType? = nil
    ) {
        self.id = id
        self.sourceRoadID = sourceRoadID
        self.sourceEdgeID = sourceEdgeID
        self.existingRoadID = existingRoadID
        self.existingEdgeID = existingEdgeID
        self.point = point
        self.sourceDistance = sourceDistance
        self.crossingAngle = crossingAngle
        self.sourcePriority = sourcePriority
        self.existingPriority = existingPriority
        self.existingLevel = existingLevel
        self.treatment = treatment
        self.triggers = triggers
        self.protectedStructure = protectedStructure
    }
}

public enum AutoStructureDecisionResolution: Codable, Hashable, Sendable {
    case accept
    case reject
    case replace(with: RoadStructureType)
}

public struct AutoStructureDecision: Codable, Hashable, Sendable {
    public var candidateID: String
    public var resolution: AutoStructureDecisionResolution

    public init(candidateID: String, resolution: AutoStructureDecisionResolution) {
        self.candidateID = candidateID
        self.resolution = resolution
    }
}

public struct ResolvedRoadStructureSpan: Codable, Hashable, Sendable {
    public var sourceRoadID: UUID
    public var sourceEdgeID: UUID
    public var roadKind: RoadKind
    public var sourceLevel: RoadLevel
    public var structure: RoadStructureType
    public var range: ClosedRange<Double>
    public var points: [RoadPoint]
    public var candidateID: String?

    public init(
        sourceRoadID: UUID,
        sourceEdgeID: UUID,
        roadKind: RoadKind,
        sourceLevel: RoadLevel,
        structure: RoadStructureType,
        range: ClosedRange<Double>,
        points: [RoadPoint],
        candidateID: String?
    ) {
        self.sourceRoadID = sourceRoadID
        self.sourceEdgeID = sourceEdgeID
        self.roadKind = roadKind
        self.sourceLevel = sourceLevel
        self.structure = structure
        self.range = range
        self.points = points
        self.candidateID = candidateID
    }
}

public struct AutoStructurePlan: Codable, Hashable, Sendable {
    public var sourceRoadID: UUID
    public var sourceEdgeID: UUID
    public var roadKind: RoadKind
    public var sourceLevel: RoadLevel
    public var sourcePoints: [RoadPoint]
    public var totalLength: Double
    public var samples: [TerrainRoadSample]
    public var candidates: [AutoStructureCandidate]
    public var crossingSuggestions: [RoadCrossingSuggestion]

    public init(
        sourceRoadID: UUID,
        sourceEdgeID: UUID,
        roadKind: RoadKind,
        sourceLevel: RoadLevel,
        sourcePoints: [RoadPoint],
        totalLength: Double,
        samples: [TerrainRoadSample],
        candidates: [AutoStructureCandidate],
        crossingSuggestions: [RoadCrossingSuggestion]
    ) {
        self.sourceRoadID = sourceRoadID
        self.sourceEdgeID = sourceEdgeID
        self.roadKind = roadKind
        self.sourceLevel = sourceLevel
        self.sourcePoints = sourcePoints
        self.totalLength = totalLength
        self.samples = samples
        self.candidates = candidates
        self.crossingSuggestions = crossingSuggestions
    }

    /// Applies explicit decisions for soft candidates. A bridge stays active
    /// when undecided or rejected because a water span may not resolve to
    /// ordinary ground. Callers can replace it with a tunnel, but not ground or
    /// a generic elevated span.
    public func resolving(
        _ decisions: [AutoStructureDecision]
    ) -> [ResolvedRoadStructureSpan] {
        let decisionsByID = Dictionary(
            decisions.map { ($0.candidateID, $0.resolution) },
            uniquingKeysWith: { _, latest in latest }
        )
        let accepted = candidates.compactMap { candidate
            -> (candidate: AutoStructureCandidate, structure: RoadStructureType)? in
            guard let resolution = decisionsByID[candidate.id] else {
                return candidate.structure == .bridge
                    ? (candidate, RoadStructureType.bridge)
                    : nil
            }
            switch resolution {
            case .accept:
                return (candidate, candidate.structure)
            case .reject:
                return candidate.structure == .bridge
                    ? (candidate, RoadStructureType.bridge)
                    : nil
            case let .replace(structure):
                if candidate.structure == .bridge {
                    return structure == .tunnel
                        ? (candidate, RoadStructureType.tunnel)
                        : (candidate, RoadStructureType.bridge)
                }
                return structure == .ground ? nil : (candidate, structure)
            }
        }

        var boundaries = [0.0, totalLength]
        for item in accepted {
            boundaries.append(item.candidate.evidence.sampleRange.startDistance)
            boundaries.append(item.candidate.evidence.sampleRange.endDistance)
        }
        boundaries = Array(Set(boundaries.map { min(totalLength, max(0, $0)) })).sorted()
        guard boundaries.count >= 2 else { return [] }

        let sampler = RoadPolylineSampler(points: sourcePoints)
        return zip(boundaries, boundaries.dropFirst()).compactMap { start, end in
            guard end - start > 1e-9 else { return nil }
            let midpoint = (start + end) / 2
            let acceptedCandidate = accepted.first {
                let range = $0.candidate.evidence.sampleRange
                return midpoint >= range.startDistance && midpoint <= range.endDistance
            }
            let baseline: RoadStructureType
            switch sourceLevel {
            case .ground: baseline = .ground
            case .tunnel: baseline = .tunnel
            case .elevated: baseline = .elevated
            }
            return ResolvedRoadStructureSpan(
                sourceRoadID: sourceRoadID,
                sourceEdgeID: sourceEdgeID,
                roadKind: roadKind,
                sourceLevel: sourceLevel,
                structure: acceptedCandidate?.structure ?? baseline,
                range: start...end,
                points: acceptedCandidate?.structure == .tunnel
                    ? [sampler.point(at: start), sampler.point(at: end)]
                    : sampler.slice(from: start, to: end),
                candidateID: acceptedCandidate?.candidate.id
            )
        }
    }

    public func acceptingAllCandidates() -> [ResolvedRoadStructureSpan] {
        resolving(candidates.map {
            AutoStructureDecision(candidateID: $0.id, resolution: .accept)
        })
    }
}

public struct RoadStructureKindRule: Codable, Hashable, Sendable {
    public var maximumApproachGrade: Double
    public var supportsInterchange: Bool

    public init(
        maximumApproachGrade: Double,
        supportsInterchange: Bool
    ) {
        self.maximumApproachGrade = maximumApproachGrade
        self.supportsInterchange = supportsInterchange
    }
}

public struct AutoStructurePlannerConfiguration: Codable, Hashable, Sendable {
    public var sampleSpacing: Double
    public var elevationScale: Double
    public var waterTolerance: Double
    public var steepGradeThreshold: Double
    public var mountainElevationThreshold: Double
    public var ridgeProminenceThreshold: Double
    public var crossSectionProbeDistance: Double
    public var tunnelLengthAdvantageThreshold: Double
    public var tunnelPortalSearchDistance: Double
    public var bridgeApproachLength: Double
    public var crossingApproachLength: Double
    public var minimumBridgeLength: Double
    public var minimumTunnelLength: Double
    public var minimumElevatedLength: Double
    public var maximumMergeableGroundGap: Double
    public var crossingMinimumAngle: Double
    public var crossingEndpointExclusionDistance: Double
    public var gradeSeparationMinimumPriority: RoadPriority
    public var interchangeMinimumPriority: RoadPriority
    public var motorwayRule: RoadStructureKindRule
    public var arterialRule: RoadStructureKindRule
    public var streetRule: RoadStructureKindRule
    public var railwayRule: RoadStructureKindRule

    public init(
        sampleSpacing: Double = 12,
        elevationScale: Double = 420,
        waterTolerance: Double = 0.001,
        steepGradeThreshold: Double = 0.11,
        mountainElevationThreshold: Double = 0.48,
        ridgeProminenceThreshold: Double = 0.055,
        crossSectionProbeDistance: Double = 36,
        tunnelLengthAdvantageThreshold: Double = 0.08,
        tunnelPortalSearchDistance: Double = 30,
        bridgeApproachLength: Double = 18,
        crossingApproachLength: Double = 32,
        minimumBridgeLength: Double = 30,
        minimumTunnelLength: Double = 48,
        minimumElevatedLength: Double = 36,
        maximumMergeableGroundGap: Double = 18,
        crossingMinimumAngle: Double = .pi / 6,
        crossingEndpointExclusionDistance: Double = 12,
        gradeSeparationMinimumPriority: RoadPriority = .motorway,
        interchangeMinimumPriority: RoadPriority = .arterial,
        motorwayRule: RoadStructureKindRule = .init(
            maximumApproachGrade: 0.06,
            supportsInterchange: true
        ),
        arterialRule: RoadStructureKindRule = .init(
            maximumApproachGrade: 0.08,
            supportsInterchange: true
        ),
        streetRule: RoadStructureKindRule = .init(
            maximumApproachGrade: 0.12,
            supportsInterchange: false
        ),
        railwayRule: RoadStructureKindRule = .init(
            maximumApproachGrade: 0.035,
            supportsInterchange: false
        )
    ) {
        self.sampleSpacing = sampleSpacing
        self.elevationScale = elevationScale
        self.waterTolerance = waterTolerance
        self.steepGradeThreshold = steepGradeThreshold
        self.mountainElevationThreshold = mountainElevationThreshold
        self.ridgeProminenceThreshold = ridgeProminenceThreshold
        self.crossSectionProbeDistance = crossSectionProbeDistance
        self.tunnelLengthAdvantageThreshold = tunnelLengthAdvantageThreshold
        self.tunnelPortalSearchDistance = tunnelPortalSearchDistance
        self.bridgeApproachLength = bridgeApproachLength
        self.crossingApproachLength = crossingApproachLength
        self.minimumBridgeLength = minimumBridgeLength
        self.minimumTunnelLength = minimumTunnelLength
        self.minimumElevatedLength = minimumElevatedLength
        self.maximumMergeableGroundGap = maximumMergeableGroundGap
        self.crossingMinimumAngle = crossingMinimumAngle
        self.crossingEndpointExclusionDistance = crossingEndpointExclusionDistance
        self.gradeSeparationMinimumPriority = gradeSeparationMinimumPriority
        self.interchangeMinimumPriority = interchangeMinimumPriority
        self.motorwayRule = motorwayRule
        self.arterialRule = arterialRule
        self.streetRule = streetRule
        self.railwayRule = railwayRule
    }

    public static let standard = AutoStructurePlannerConfiguration()

    public func rule(for kind: RoadKind) -> RoadStructureKindRule {
        switch kind {
        case .motorway: motorwayRule
        case .arterial: arterialRule
        case .street: streetRule
        case .railway: railwayRule
        }
    }

    public func scaledForCanvas(
        metersPerPoint: Double
    ) -> AutoStructurePlannerConfiguration {
        let scale = min(10, max(0.1, metersPerPoint))
        var copy = self
        copy.sampleSpacing /= scale
        copy.elevationScale /= scale
        copy.crossSectionProbeDistance /= scale
        copy.tunnelPortalSearchDistance /= scale
        copy.bridgeApproachLength /= scale
        copy.crossingApproachLength /= scale
        copy.minimumBridgeLength /= scale
        copy.minimumTunnelLength /= scale
        copy.minimumElevatedLength /= scale
        copy.maximumMergeableGroundGap /= scale
        copy.crossingEndpointExclusionDistance /= scale
        return copy
    }
}

public enum AutoStructurePlanner {
    public static func plan(
        for road: RoadSegment,
        terrain: TerrainLayout,
        existingRoads: [RoadSegment],
        configuration: AutoStructurePlannerConfiguration = .standard
    ) -> AutoStructurePlan {
        let sampler = RoadPolylineSampler(points: road.points)
        guard sampler.totalLength > 1e-9 else {
            return AutoStructurePlan(
                sourceRoadID: road.sourceRoadID,
                sourceEdgeID: road.id,
                roadKind: road.kind,
                sourceLevel: road.level,
                sourcePoints: road.points,
                totalLength: sampler.totalLength,
                samples: [],
                candidates: [],
                crossingSuggestions: []
            )
        }

        let spacing = max(0.5, configuration.sampleSpacing)
        let intervalCount = max(1, Int(ceil(sampler.totalLength / spacing)))
        let distances = (0...intervalCount).map {
            sampler.totalLength * Double($0) / Double(intervalCount)
        }
        var samples = distances.enumerated().map { index, distance in
            let point = sampler.point(at: distance)
            let elevation = terrain.normalizedElevation(at: point)
            let probe = min(spacing, max(0.5, sampler.totalLength / 2))
            let before = sampler.point(at: max(0, distance - probe))
            let after = sampler.point(at: min(sampler.totalLength, distance + probe))
            let tangentX = after.x - before.x
            let tangentY = after.y - before.y
            let tangentLength = hypot(tangentX, tangentY)
            let normalX = tangentLength > 1e-9 ? -tangentY / tangentLength : 0
            let normalY = tangentLength > 1e-9 ? tangentX / tangentLength : 0
            let offset = max(0, configuration.crossSectionProbeDistance)
            let left = RoadPoint(x: point.x + normalX * offset, y: point.y + normalY * offset)
            let right = RoadPoint(x: point.x - normalX * offset, y: point.y - normalY * offset)
            let lateralMean = (
                terrain.normalizedElevation(at: left)
                    + terrain.normalizedElevation(at: right)
            ) / 2
            return TerrainRoadSample(
                index: index,
                distance: distance,
                point: point,
                normalizedElevation: elevation,
                isWater: elevation <= terrain.waterLevel + configuration.waterTolerance,
                longitudinalGrade: 0,
                ridgeProminence: elevation - lateralMean
            )
        }

        for index in samples.indices {
            let lower = max(0, index - 1)
            let upper = min(samples.count - 1, index + 1)
            let run = samples[upper].distance - samples[lower].distance
            if run > 1e-9 {
                samples[index].longitudinalGrade = (
                    samples[upper].normalizedElevation - samples[lower].normalizedElevation
                ) * configuration.elevationScale / run
            }
        }

        guard samples.count >= 2 else {
            return AutoStructurePlan(
                sourceRoadID: road.sourceRoadID,
                sourceEdgeID: road.id,
                roadKind: road.kind,
                sourceLevel: road.level,
                sourcePoints: road.points,
                totalLength: sampler.totalLength,
                samples: samples,
                candidates: [],
                crossingSuggestions: []
            )
        }

        var labels = Array(repeating: RoadStructureType.ground, count: samples.count - 1)

        // Water has the highest structural priority.
        for index in labels.indices
        where samples[index].isWater || samples[index + 1].isWater {
            labels[index] = .bridge
        }
        expand(
            type: .bridge,
            by: configuration.bridgeApproachLength,
            labels: &labels,
            samples: samples,
            mayReplace: { _ in true }
        )

        let mountainFlags = samples.map { sample in
            guard !sample.isWater else { return false }
            let steepMountain = abs(sample.longitudinalGrade)
                >= configuration.steepGradeThreshold
                && sample.normalizedElevation >= configuration.mountainElevationThreshold
            return steepMountain
                || sample.ridgeProminence >= configuration.ridgeProminenceThreshold
        }
        var tunnelRanges: [ClosedRange<Int>] = []
        for run in trueRuns(in: mountainFlags) {
            let startDistance = max(
                0,
                samples[run.lowerBound].distance - configuration.tunnelPortalSearchDistance
            )
            let endDistance = min(
                sampler.totalLength,
                samples[run.upperBound].distance + configuration.tunnelPortalSearchDistance
            )
            let startIndex = startIntervalIndex(at: startDistance, samples: samples)
            let endIndex = endIntervalIndex(at: endDistance, samples: samples)
            guard endIndex >= startIndex else { continue }
            tunnelRanges.append(startIndex...endIndex)
        }
        tunnelRanges = mergedIntervalRanges(
            tunnelRanges,
            samples: samples,
            maximumGap: configuration.maximumMergeableGroundGap
        )
        for tunnelRange in tunnelRanges {
            let metrics = metrics(
                fromSample: tunnelRange.lowerBound,
                throughSample: min(samples.count - 1, tunnelRange.upperBound + 1),
                samples: samples,
                elevationScale: configuration.elevationScale
            )
            let length = samples[min(samples.count - 1, tunnelRange.upperBound + 1)].distance
                - samples[tunnelRange.lowerBound].distance
            guard length + 1e-9 >= configuration.minimumTunnelLength,
                  metrics.lengthAdvantageRatio + 1e-12
                    >= configuration.tunnelLengthAdvantageThreshold
            else { continue }
            for index in tunnelRange where labels[index] == .ground {
                labels[index] = .tunnel
            }
        }

        var crossings = crossingSuggestions(
            for: road,
            sampler: sampler,
            existingRoads: existingRoads,
            configuration: configuration
        )
        for crossing in crossings
        where crossing.treatment == .elevated || crossing.treatment == .interchange {
            let start = max(0, crossing.sourceDistance - configuration.crossingApproachLength)
            let end = min(
                sampler.totalLength,
                crossing.sourceDistance + configuration.crossingApproachLength
            )
            let first = startIntervalIndex(at: start, samples: samples)
            let last = endIntervalIndex(at: end, samples: samples)
            guard last >= first else { continue }
            for index in first...last where labels[index] == .ground {
                labels[index] = .elevated
            }
        }

        mergeSmallGroundGaps(
            labels: &labels,
            samples: samples,
            maximumGap: configuration.maximumMergeableGroundGap
        )
        enforceMinimumRuns(
            labels: &labels,
            samples: samples,
            configuration: configuration
        )
        extendBridgesToFeasibleApproaches(
            labels: &labels,
            samples: samples,
            roadKind: road.kind,
            configuration: configuration
        )
        mergeSmallGroundGaps(
            labels: &labels,
            samples: samples,
            maximumGap: configuration.maximumMergeableGroundGap
        )
        enforceMinimumRuns(
            labels: &labels,
            samples: samples,
            configuration: configuration
        )
        validateFinalTunnelRuns(
            labels: &labels,
            samples: samples,
            configuration: configuration
        )
        crossings = crossings.map { crossing in
            guard crossing.treatment == .elevated || crossing.treatment == .interchange
            else { return crossing }
            let index = startIntervalIndex(at: crossing.sourceDistance, samples: samples)
            let primary = labels[index]
            guard primary == .bridge || primary == .tunnel else { return crossing }
            var deferred = crossing
            deferred.treatment = .deferToPrimaryStructure
            deferred.protectedStructure = primary
            return deferred
        }

        let candidates = makeCandidates(
            road: road,
            labels: labels,
            samples: samples,
            crossings: crossings,
            configuration: configuration
        )
        return AutoStructurePlan(
            sourceRoadID: road.sourceRoadID,
            sourceEdgeID: road.id,
            roadKind: road.kind,
            sourceLevel: road.level,
            sourcePoints: road.points,
            totalLength: sampler.totalLength,
            samples: samples,
            candidates: candidates,
            crossingSuggestions: crossings
        )
    }

    private static func makeCandidates(
        road: RoadSegment,
        labels: [RoadStructureType],
        samples: [TerrainRoadSample],
        crossings: [RoadCrossingSuggestion],
        configuration: AutoStructurePlannerConfiguration
    ) -> [AutoStructureCandidate] {
        runs(in: labels).compactMap { run in
            guard run.value != .ground else { return nil }
            let startSample = run.range.lowerBound
            let endSample = run.range.upperBound + 1
            let range = StructureSampleRange(
                startSampleIndex: startSample,
                endSampleIndex: endSample,
                startDistance: samples[startSample].distance,
                endDistance: samples[endSample].distance
            )
            let spanMetrics = metrics(
                fromSample: startSample,
                throughSample: endSample,
                samples: samples,
                elevationScale: configuration.elevationScale
            )
            let relatedCrossings = crossings.filter {
                $0.sourceDistance >= range.startDistance
                    && $0.sourceDistance <= range.endDistance
            }
            var triggers = Set<AutoStructureTrigger>()
            switch run.value {
            case .ground:
                break
            case .bridge:
                triggers.insert(.water)
            case .tunnel:
                if spanMetrics.maximumAbsoluteGrade >= configuration.steepGradeThreshold {
                    triggers.insert(.steepGrade)
                }
                if spanMetrics.maximumRidgeProminence
                    >= configuration.ridgeProminenceThreshold {
                    triggers.insert(.mountainRelief)
                }
                triggers.insert(.tunnelLengthAdvantage)
            case .elevated:
                triggers.formUnion([.roadCrossing, .roadPriority, .crossingAngle])
            }
            let evidence = AutoStructureEvidence(
                triggers: triggers,
                sampleRange: range,
                metrics: spanMetrics,
                relatedRoadIDs: relatedCrossings.map(\.existingRoadID)
            )
            let transitionKind: StructureTransitionKind
            switch run.value {
            case .bridge: transitionKind = .bridgehead
            case .tunnel: transitionKind = .tunnelPortal
            case .elevated: transitionKind = .elevatedRamp
            case .ground: return nil
            }
            let preferredMinimum: Double
            switch run.value {
            case .bridge: preferredMinimum = configuration.minimumBridgeLength
            case .tunnel: preferredMinimum = configuration.minimumTunnelLength
            case .elevated: preferredMinimum = configuration.minimumElevatedLength
            case .ground: preferredMinimum = 0
            }
            let entrance = transitionHint(
                role: .entrance,
                kind: transitionKind,
                sampleIndex: startSample,
                samples: samples,
                roadKind: road.kind,
                rangeLength: range.length,
                preferredMinimum: preferredMinimum,
                configuration: configuration
            )
            let exit = transitionHint(
                role: .exit,
                kind: transitionKind,
                sampleIndex: endSample,
                samples: samples,
                roadKind: road.kind,
                rangeLength: range.length,
                preferredMinimum: preferredMinimum,
                configuration: configuration
            )
            return AutoStructureCandidate(
                id: stableCandidateID(
                    sourceRoadID: road.sourceRoadID,
                    structure: run.value,
                    start: samples[startSample].point,
                    end: samples[endSample].point,
                    midpoint: samples[(startSample + endSample) / 2].point
                ),
                sourceRoadID: road.sourceRoadID,
                sourceEdgeID: road.id,
                structure: run.value,
                startPoint: samples[startSample].point,
                endPoint: samples[endSample].point,
                evidence: evidence,
                entrance: entrance,
                exit: exit
            )
        }
    }

    private static func transitionHint(
        role: StructureTransitionRole,
        kind: StructureTransitionKind,
        sampleIndex: Int,
        samples: [TerrainRoadSample],
        roadKind: RoadKind,
        rangeLength: Double,
        preferredMinimum: Double,
        configuration: AutoStructurePlannerConfiguration
    ) -> StructureTransitionHint {
        let measurement = approachMeasurement(
            role: role,
            sampleIndex: sampleIndex,
            samples: samples,
            configuration: configuration
        )
        let grade = measurement.grade
        let run = measurement.run
        let maximumGrade = configuration.rule(for: roadKind).maximumApproachGrade
        let elevationChange = measurement.elevationChange
        var warnings = Set<StructureTransitionWarning>()
        if abs(grade) > maximumGrade + 1e-12 {
            warnings.insert(.steepApproach)
        }
        if rangeLength + 1e-9 < preferredMinimum {
            warnings.insert(.belowPreferredStructureLength)
        }
        return StructureTransitionHint(
            role: role,
            kind: kind,
            point: samples[sampleIndex].point,
            distance: samples[sampleIndex].distance,
            terrainElevation: samples[sampleIndex].normalizedElevation,
            approachGrade: grade,
            recommendedApproachLength: maximumGrade > 0
                ? max(run, elevationChange / maximumGrade)
                : run,
            warnings: warnings
        )
    }

    private static func extendBridgesToFeasibleApproaches(
        labels: inout [RoadStructureType],
        samples: [TerrainRoadSample],
        roadKind: RoadKind,
        configuration: AutoStructurePlannerConfiguration
    ) {
        let maximumGrade = configuration.rule(for: roadKind).maximumApproachGrade
        guard maximumGrade > 0, samples.count >= 2 else { return }

        for bridge in runs(in: labels) where bridge.value == .bridge {
            let startSample = bridge.range.lowerBound
            let endSample = bridge.range.upperBound + 1
            let feasibleStart = stride(
                from: startSample,
                through: 0,
                by: -1
            ).first { index in
                !samples[index].isWater
                    && abs(
                        approachMeasurement(
                            role: .entrance,
                            sampleIndex: index,
                            samples: samples,
                            configuration: configuration
                        ).grade
                    ) <= maximumGrade + 1e-12
            }
            let feasibleEnd = (endSample..<samples.count).first { index in
                !samples[index].isWater
                    && abs(
                        approachMeasurement(
                            role: .exit,
                            sampleIndex: index,
                            samples: samples,
                            configuration: configuration
                        ).grade
                    ) <= maximumGrade + 1e-12
            }

            if let feasibleStart, feasibleStart < bridge.range.lowerBound {
                for index in feasibleStart..<bridge.range.lowerBound {
                    labels[index] = .bridge
                }
            }
            if let feasibleEnd, feasibleEnd > bridge.range.upperBound + 1 {
                for index in (bridge.range.upperBound + 1)..<feasibleEnd {
                    labels[index] = .bridge
                }
            }
        }
    }

    private static func approachMeasurement(
        role: StructureTransitionRole,
        sampleIndex: Int,
        samples: [TerrainRoadSample],
        configuration: AutoStructurePlannerConfiguration
    ) -> (grade: Double, run: Double, elevationChange: Double) {
        let window = max(1, Int(ceil(
            max(configuration.bridgeApproachLength, configuration.crossingApproachLength)
                / max(0.5, configuration.sampleSpacing)
        )))
        let otherIndex: Int
        switch role {
        case .entrance:
            otherIndex = max(0, sampleIndex - window)
        case .exit:
            otherIndex = min(samples.count - 1, sampleIndex + window)
        }
        let run = abs(samples[sampleIndex].distance - samples[otherIndex].distance)
        let signedElevationChange: Double
        switch role {
        case .entrance:
            signedElevationChange = samples[sampleIndex].normalizedElevation
                - samples[otherIndex].normalizedElevation
        case .exit:
            signedElevationChange = samples[otherIndex].normalizedElevation
                - samples[sampleIndex].normalizedElevation
        }
        let grade = run > 1e-9
            ? signedElevationChange * configuration.elevationScale / run
            : samples[sampleIndex].longitudinalGrade
        let elevationChange = abs(
            samples[sampleIndex].normalizedElevation
                - samples[otherIndex].normalizedElevation
        ) * configuration.elevationScale
        return (grade, run, elevationChange)
    }

    private static func metrics(
        fromSample start: Int,
        throughSample end: Int,
        samples: [TerrainRoadSample],
        elevationScale: Double
    ) -> AutoStructureMetrics {
        let boundedStart = max(0, min(samples.count - 1, start))
        let boundedEnd = max(boundedStart, min(samples.count - 1, end))
        let slice = samples[boundedStart...boundedEnd]
        var surfaceLength = 0.0
        if boundedEnd > boundedStart {
            for index in boundedStart..<boundedEnd {
                // Samples are equally spaced by source-road chainage. Using
                // endpoint chord distance here would undercount a curved final
                // centerline and overstate the tunnel advantage.
                let horizontal = samples[index + 1].distance - samples[index].distance
                let rise = (
                    samples[index + 1].normalizedElevation
                        - samples[index].normalizedElevation
                ) * elevationScale
                surfaceLength += hypot(horizontal, rise)
            }
        }
        let horizontalDirect = samples[boundedStart].point.distance(to: samples[boundedEnd].point)
        let directRise = (
            samples[boundedEnd].normalizedElevation
                - samples[boundedStart].normalizedElevation
        ) * elevationScale
        let directLength = hypot(horizontalDirect, directRise)
        let advantage = surfaceLength > 1e-9
            ? max(0, (surfaceLength - directLength) / surfaceLength)
            : 0
        return AutoStructureMetrics(
            minimumElevation: slice.map(\.normalizedElevation).min() ?? 0,
            maximumElevation: slice.map(\.normalizedElevation).max() ?? 0,
            maximumAbsoluteGrade: slice.map { abs($0.longitudinalGrade) }.max() ?? 0,
            maximumRidgeProminence: slice.map(\.ridgeProminence).max() ?? 0,
            surfaceLength: surfaceLength,
            directStructureLength: directLength,
            lengthAdvantageRatio: advantage,
            waterSampleCount: slice.filter(\.isWater).count
        )
    }

    private static func expand(
        type: RoadStructureType,
        by distance: Double,
        labels: inout [RoadStructureType],
        samples: [TerrainRoadSample],
        mayReplace: (RoadStructureType) -> Bool
    ) {
        guard distance > 0 else { return }
        let originalRuns = runs(in: labels).filter { $0.value == type }
        for run in originalRuns {
            let startDistance = max(0, samples[run.range.lowerBound].distance - distance)
            let endDistance = min(
                samples.last?.distance ?? 0,
                samples[run.range.upperBound + 1].distance + distance
            )
            let first = startIntervalIndex(at: startDistance, samples: samples)
            let last = endIntervalIndex(at: endDistance, samples: samples)
            guard last >= first else { continue }
            for index in first...last where mayReplace(labels[index]) {
                labels[index] = type
            }
        }
    }

    private static func mergeSmallGroundGaps(
        labels: inout [RoadStructureType],
        samples: [TerrainRoadSample],
        maximumGap: Double
    ) {
        guard maximumGap > 0 else { return }
        var changed = true
        while changed {
            changed = false
            let currentRuns = runs(in: labels)
            guard currentRuns.count >= 3 else { break }
            for index in 1..<(currentRuns.count - 1) {
                let gap = currentRuns[index]
                let before = currentRuns[index - 1]
                let after = currentRuns[index + 1]
                guard gap.value == .ground,
                      before.value == after.value,
                      before.value != .ground
                else { continue }
                let length = samples[gap.range.upperBound + 1].distance
                    - samples[gap.range.lowerBound].distance
                guard length <= maximumGap + 1e-9 else { continue }
                for labelIndex in gap.range {
                    labels[labelIndex] = before.value
                }
                changed = true
                break
            }
        }
    }

    private static func enforceMinimumRuns(
        labels: inout [RoadStructureType],
        samples: [TerrainRoadSample],
        configuration: AutoStructurePlannerConfiguration
    ) {
        // Bridge expansion may overwrite tunnel/elevated labels. Recompute the
        // current runs after every expansion so a later stale non-bridge range
        // can never erase the higher-priority bridge.
        var stalledBridgeRanges = Set<ClosedRange<Int>>()
        while let bridge = runs(in: labels).first(where: {
            $0.value == .bridge
                && runLength($0.range, samples: samples) + 1e-9
                    < configuration.minimumBridgeLength
                && !stalledBridgeRanges.contains($0.range)
        }) {
            let length = runLength(bridge.range, samples: samples)
            let missing = configuration.minimumBridgeLength - length
            let currentStart = samples[bridge.range.lowerBound].distance
            let currentEnd = samples[bridge.range.upperBound + 1].distance
            let totalLength = samples.last?.distance ?? 0
            var desiredStart = max(0, currentStart - missing / 2)
            var desiredEnd = min(totalLength, currentEnd + missing / 2)
            let remaining = configuration.minimumBridgeLength
                - (desiredEnd - desiredStart)
            if remaining > 1e-9 {
                if desiredStart <= 1e-9 {
                    desiredEnd = min(totalLength, desiredEnd + remaining)
                } else if desiredEnd >= totalLength - 1e-9 {
                    desiredStart = max(0, desiredStart - remaining)
                }
            }

            let first = startIntervalIndex(at: desiredStart, samples: samples)
            let last = endIntervalIndex(at: desiredEnd, samples: samples)
            let previous = labels
            if last >= first {
                for index in first...last {
                    labels[index] = .bridge
                }
            }
            if labels == previous {
                stalledBridgeRanges.insert(bridge.range)
            } else {
                stalledBridgeRanges.removeAll()
            }
        }

        // Each deletion changes neighboring runs. Always select from the
        // current labels rather than continuing over a pre-mutation snapshot.
        while let shortRun = runs(in: labels).first(where: {
            guard $0.value == .tunnel || $0.value == .elevated else { return false }
            let minimum = $0.value == .tunnel
                ? configuration.minimumTunnelLength
                : configuration.minimumElevatedLength
            return runLength($0.range, samples: samples) + 1e-9 < minimum
        }) {
            for index in shortRun.range {
                labels[index] = .ground
            }
        }
    }

    private static func validateFinalTunnelRuns(
        labels: inout [RoadStructureType],
        samples: [TerrainRoadSample],
        configuration: AutoStructurePlannerConfiguration
    ) {
        while let invalidTunnel = runs(in: labels).first(where: { run in
            guard run.value == .tunnel else { return false }
            let length = runLength(run.range, samples: samples)
            guard length + 1e-9 >= configuration.minimumTunnelLength else {
                return true
            }
            let finalMetrics = metrics(
                fromSample: run.range.lowerBound,
                throughSample: run.range.upperBound + 1,
                samples: samples,
                elevationScale: configuration.elevationScale
            )
            return finalMetrics.lengthAdvantageRatio + 1e-12
                < configuration.tunnelLengthAdvantageThreshold
        }) {
            for index in invalidTunnel.range {
                labels[index] = .ground
            }
        }
    }

    private static func runLength(
        _ range: ClosedRange<Int>,
        samples: [TerrainRoadSample]
    ) -> Double {
        samples[range.upperBound + 1].distance
            - samples[range.lowerBound].distance
    }

    private static func crossingSuggestions(
        for road: RoadSegment,
        sampler: RoadPolylineSampler,
        existingRoads: [RoadSegment],
        configuration: AutoStructurePlannerConfiguration
    ) -> [RoadCrossingSuggestion] {
        var result: [RoadCrossingSuggestion] = []
        let sourceRule = configuration.rule(for: road.kind)
        for existing in existingRoads
        where existing.sourceRoadID != road.sourceRoadID {
            let existingSampler = RoadPolylineSampler(points: existing.points)
            guard existingSampler.totalLength > 1e-9 else { continue }
            for sourceIndex in 0..<(sampler.points.count - 1) {
                let sourceStart = sampler.points[sourceIndex]
                let sourceEnd = sampler.points[sourceIndex + 1]
                let sourcePrefix = sampler.distance(atVertex: sourceIndex)
                for existingIndex in 0..<(existingSampler.points.count - 1) {
                    let existingStart = existingSampler.points[existingIndex]
                    let existingEnd = existingSampler.points[existingIndex + 1]
                    guard let intersection = segmentIntersection(
                        sourceStart,
                        sourceEnd,
                        existingStart,
                        existingEnd
                    ) else { continue }
                    let sourceDistance = sourcePrefix
                        + sourceStart.distance(to: intersection)
                    let existingDistance = existingSampler.distance(atVertex: existingIndex)
                        + existingStart.distance(to: intersection)
                    let exclusion = max(0, configuration.crossingEndpointExclusionDistance)
                    guard sourceDistance > exclusion,
                          sampler.totalLength - sourceDistance > exclusion,
                          existingDistance > exclusion,
                          existingSampler.totalLength - existingDistance > exclusion
                    else { continue }
                    if result.contains(where: {
                        $0.existingRoadID == existing.sourceRoadID
                            && $0.point.distance(to: intersection) < 0.5
                    }) {
                        continue
                    }

                    let angle = acuteAngle(
                        from: sourceEnd - sourceStart,
                        to: existingEnd - existingStart
                    )
                    let existingRule = configuration.rule(for: existing.kind)
                    let treatment: RoadCrossingTreatment
                    var triggers: Set<AutoStructureTrigger> = [.roadCrossing]
                    if road.level != existing.level {
                        treatment = .preserveExistingSeparation
                        triggers.insert(.existingVerticalSeparation)
                    } else if angle + 1e-12 < configuration.crossingMinimumAngle {
                        treatment = .atGrade
                    } else if road.kind == .railway || existing.kind == .railway {
                        treatment = .elevated
                        triggers.formUnion([.roadPriority, .crossingAngle])
                    } else if sourceRule.supportsInterchange,
                              existingRule.supportsInterchange,
                              min(road.priority, existing.priority)
                                >= configuration.interchangeMinimumPriority {
                        treatment = .interchange
                        triggers.formUnion([.roadPriority, .crossingAngle])
                    } else if max(road.priority, existing.priority)
                                    >= configuration.gradeSeparationMinimumPriority {
                        treatment = .elevated
                        triggers.formUnion([.roadPriority, .crossingAngle])
                    } else {
                        treatment = .atGrade
                    }
                    result.append(
                        RoadCrossingSuggestion(
                            id: stableCrossingID(
                                sourceRoadID: road.sourceRoadID,
                                existingRoadID: existing.sourceRoadID,
                                point: intersection
                            ),
                            sourceRoadID: road.sourceRoadID,
                            sourceEdgeID: road.id,
                            existingRoadID: existing.sourceRoadID,
                            existingEdgeID: existing.id,
                            point: intersection,
                            sourceDistance: sourceDistance,
                            crossingAngle: angle,
                            sourcePriority: road.priority,
                            existingPriority: existing.priority,
                            existingLevel: existing.level,
                            treatment: treatment,
                            triggers: triggers
                        )
                    )
                }
            }
        }
        return result.sorted { $0.sourceDistance < $1.sourceDistance }
    }

    private static func stableCandidateID(
        sourceRoadID: UUID,
        structure: RoadStructureType,
        start: RoadPoint,
        end: RoadPoint,
        midpoint: RoadPoint
    ) -> String {
        "\(sourceRoadID.uuidString.lowercased()):\(structure.rawValue):"
            + "\(quantized(start.x)),\(quantized(start.y))-"
            + "\(quantized(midpoint.x)),\(quantized(midpoint.y))-"
            + "\(quantized(end.x)),\(quantized(end.y))"
    }

    private static func stableCrossingID(
        sourceRoadID: UUID,
        existingRoadID: UUID,
        point: RoadPoint
    ) -> String {
        "\(sourceRoadID.uuidString.lowercased()):"
            + "\(existingRoadID.uuidString.lowercased()):"
            + "\(quantized(point.x)),\(quantized(point.y))"
    }

    private static func quantized(_ value: Double) -> Int64 {
        Int64((value * 100).rounded())
    }

    /// Interval whose lower boundary is at or immediately before `distance`.
    /// At an exact interior sample boundary this returns the interval beginning
    /// at that sample, preventing a requested start from consuming the previous
    /// interval.
    private static func startIntervalIndex(
        at distance: Double,
        samples: [TerrainRoadSample]
    ) -> Int {
        guard samples.count >= 2 else { return 0 }
        if distance <= samples[0].distance + 1e-9 { return 0 }
        for index in 0..<(samples.count - 1)
        where distance < samples[index + 1].distance - 1e-9 {
            return index
        }
        return samples.count - 2
    }

    /// Last interval ending at or immediately after `distance`. At an exact
    /// sample boundary this returns the interval ending at that sample.
    private static func endIntervalIndex(
        at distance: Double,
        samples: [TerrainRoadSample]
    ) -> Int {
        guard samples.count >= 2 else { return 0 }
        if distance <= samples[0].distance + 1e-9 { return 0 }
        for index in 0..<(samples.count - 1)
        where distance <= samples[index + 1].distance + 1e-9 {
            return index
        }
        return samples.count - 2
    }

    private static func trueRuns(in values: [Bool]) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        var start: Int?
        for index in values.indices {
            if values[index], start == nil {
                start = index
            } else if !values[index], let runStart = start {
                result.append(runStart...(index - 1))
                start = nil
            }
        }
        if let start {
            result.append(start...(values.count - 1))
        }
        return result
    }

    private static func mergedIntervalRanges(
        _ ranges: [ClosedRange<Int>],
        samples: [TerrainRoadSample],
        maximumGap: Double
    ) -> [ClosedRange<Int>] {
        let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
        guard var current = sorted.first else { return [] }
        var result: [ClosedRange<Int>] = []
        for next in sorted.dropFirst() {
            let gap: Double
            if next.lowerBound <= current.upperBound + 1 {
                gap = 0
            } else {
                gap = samples[next.lowerBound].distance
                    - samples[current.upperBound + 1].distance
            }
            if gap <= maximumGap + 1e-9 {
                current = current.lowerBound...max(current.upperBound, next.upperBound)
            } else {
                result.append(current)
                current = next
            }
        }
        result.append(current)
        return result
    }

    private struct LabelRun {
        var value: RoadStructureType
        var range: ClosedRange<Int>
    }

    private static func runs(in labels: [RoadStructureType]) -> [LabelRun] {
        guard let first = labels.first else { return [] }
        var result: [LabelRun] = []
        var value = first
        var start = 0
        for index in labels.indices.dropFirst() where labels[index] != value {
            result.append(LabelRun(value: value, range: start...(index - 1)))
            value = labels[index]
            start = index
        }
        result.append(LabelRun(value: value, range: start...(labels.count - 1)))
        return result
    }

    private static func segmentIntersection(
        _ a: RoadPoint,
        _ b: RoadPoint,
        _ c: RoadPoint,
        _ d: RoadPoint
    ) -> RoadPoint? {
        let r = b - a
        let s = d - c
        let denominator = cross(r, s)
        guard abs(denominator) > 1e-9 else { return nil }
        let offset = c - a
        let t = cross(offset, s) / denominator
        let u = cross(offset, r) / denominator
        guard t >= -1e-9, t <= 1 + 1e-9, u >= -1e-9, u <= 1 + 1e-9
        else { return nil }
        return a + r * min(1, max(0, t))
    }

    private static func cross(_ lhs: RoadPoint, _ rhs: RoadPoint) -> Double {
        lhs.x * rhs.y - lhs.y * rhs.x
    }

    private static func acuteAngle(from lhs: RoadPoint, to rhs: RoadPoint) -> Double {
        let lhsLength = hypot(lhs.x, lhs.y)
        let rhsLength = hypot(rhs.x, rhs.y)
        guard lhsLength > 1e-9, rhsLength > 1e-9 else { return 0 }
        let cosine = min(
            1,
            max(-1, (lhs.x * rhs.x + lhs.y * rhs.y) / (lhsLength * rhsLength))
        )
        let angle = acos(cosine)
        return min(angle, .pi - angle)
    }
}

private struct RoadPolylineSampler: Sendable {
    let points: [RoadPoint]
    let cumulativeDistances: [Double]
    let totalLength: Double

    init(points: [RoadPoint]) {
        var sanitized: [RoadPoint] = []
        for point in points where sanitized.last?.distance(to: point) ?? .infinity > 1e-9 {
            sanitized.append(point)
        }
        self.points = sanitized
        var cumulative = [0.0]
        if sanitized.count >= 2 {
            for index in 1..<sanitized.count {
                cumulative.append(
                    cumulative[cumulative.count - 1]
                        + sanitized[index - 1].distance(to: sanitized[index])
                )
            }
        }
        cumulativeDistances = cumulative
        totalLength = cumulative.last ?? 0
    }

    func point(at distance: Double) -> RoadPoint {
        guard let first = points.first else { return RoadPoint(x: 0, y: 0) }
        guard points.count >= 2 else { return first }
        let bounded = min(totalLength, max(0, distance))
        for index in 0..<(points.count - 1)
        where bounded <= cumulativeDistances[index + 1] + 1e-9 {
            let startDistance = cumulativeDistances[index]
            let length = cumulativeDistances[index + 1] - startDistance
            guard length > 1e-9 else { return points[index] }
            let t = min(1, max(0, (bounded - startDistance) / length))
            return points[index] + (points[index + 1] - points[index]) * t
        }
        return points[points.count - 1]
    }

    func distance(atVertex index: Int) -> Double {
        guard cumulativeDistances.indices.contains(index) else { return totalLength }
        return cumulativeDistances[index]
    }

    func slice(from start: Double, to end: Double) -> [RoadPoint] {
        guard !points.isEmpty else { return [] }
        let boundedStart = min(totalLength, max(0, start))
        let boundedEnd = min(totalLength, max(boundedStart, end))
        var result = [point(at: boundedStart)]
        for (index, distance) in cumulativeDistances.enumerated()
        where distance > boundedStart + 1e-9 && distance < boundedEnd - 1e-9 {
            result.append(points[index])
        }
        let final = point(at: boundedEnd)
        if result.last != final {
            result.append(final)
        }
        return result
    }
}
