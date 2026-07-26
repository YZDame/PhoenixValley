import Foundation

/// Simplified planning rules used by Phoenix Valley.
///
/// These values are gameplay constraints rather than a substitute for a
/// jurisdiction's bridge or tunnel design code. Distances and elevations are
/// always stored in metres so changing the map scale cannot change feasibility.
public struct RoadEngineeringKindLimits: Codable, Hashable, Sendable {
    public var minimumBridgeLengthMeters: Double
    public var maximumBridgeLengthMeters: Double
    public var maximumBridgeSpanMeters: Double
    public var minimumTunnelLengthMeters: Double
    public var maximumStructureGrade: Double
    public var maximumApproachGrade: Double

    public init(
        minimumBridgeLengthMeters: Double,
        maximumBridgeLengthMeters: Double,
        maximumBridgeSpanMeters: Double,
        minimumTunnelLengthMeters: Double,
        maximumStructureGrade: Double,
        maximumApproachGrade: Double
    ) {
        self.minimumBridgeLengthMeters = minimumBridgeLengthMeters
        self.maximumBridgeLengthMeters = maximumBridgeLengthMeters
        self.maximumBridgeSpanMeters = maximumBridgeSpanMeters
        self.minimumTunnelLengthMeters = minimumTunnelLengthMeters
        self.maximumStructureGrade = maximumStructureGrade
        self.maximumApproachGrade = maximumApproachGrade
    }
}

public struct RoadEngineeringConfiguration: Codable, Hashable, Sendable {
    public var elevationScaleMeters: Double
    public var profileSampleSpacingMeters: Double
    public var minimumTunnelCoverMeters: Double
    public var waterTolerance: Double

    public init(
        elevationScaleMeters: Double = 420,
        profileSampleSpacingMeters: Double = 20,
        minimumTunnelCoverMeters: Double = 8,
        waterTolerance: Double = 0.001
    ) {
        self.elevationScaleMeters = elevationScaleMeters
        self.profileSampleSpacingMeters = profileSampleSpacingMeters
        self.minimumTunnelCoverMeters = minimumTunnelCoverMeters
        self.waterTolerance = waterTolerance
    }

    public static let standard = RoadEngineeringConfiguration()

    public func limits(for kind: RoadKind) -> RoadEngineeringKindLimits {
        switch kind {
        case .motorway:
            RoadEngineeringKindLimits(
                minimumBridgeLengthMeters: 30,
                maximumBridgeLengthMeters: 4_000,
                maximumBridgeSpanMeters: 90,
                minimumTunnelLengthMeters: 48,
                maximumStructureGrade: 0.06,
                maximumApproachGrade: 0.06
            )
        case .arterial:
            RoadEngineeringKindLimits(
                minimumBridgeLengthMeters: 30,
                maximumBridgeLengthMeters: 3_000,
                maximumBridgeSpanMeters: 80,
                minimumTunnelLengthMeters: 48,
                maximumStructureGrade: 0.08,
                maximumApproachGrade: 0.08
            )
        case .street:
            RoadEngineeringKindLimits(
                minimumBridgeLengthMeters: 30,
                maximumBridgeLengthMeters: 2_000,
                maximumBridgeSpanMeters: 55,
                minimumTunnelLengthMeters: 48,
                maximumStructureGrade: 0.12,
                maximumApproachGrade: 0.12
            )
        case .railway:
            RoadEngineeringKindLimits(
                minimumBridgeLengthMeters: 30,
                maximumBridgeLengthMeters: 4_000,
                maximumBridgeSpanMeters: 95,
                minimumTunnelLengthMeters: 48,
                maximumStructureGrade: 0.035,
                maximumApproachGrade: 0.035
            )
        }
    }
}

public struct RoadVerticalProfileSample: Codable, Hashable, Sendable {
    public var chainageMeters: Double
    public var point: RoadPoint
    public var surfaceElevationMeters: Double
    public var structureElevationMeters: Double

    public init(
        chainageMeters: Double,
        point: RoadPoint,
        surfaceElevationMeters: Double,
        structureElevationMeters: Double
    ) {
        self.chainageMeters = chainageMeters
        self.point = point
        self.surfaceElevationMeters = surfaceElevationMeters
        self.structureElevationMeters = structureElevationMeters
    }

    public var verticalSeparationMeters: Double {
        structureElevationMeters - surfaceElevationMeters
    }
}

public struct RoadEngineeringEndpoint: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var role: StructureTransitionRole
    public var chainageMeters: Double
    public var point: RoadPoint
    /// Unit vector following increasing source-road chainage.
    public var tangent: RoadPoint
    public var groundElevationMeters: Double
    public var structureElevationMeters: Double
    public var approachGrade: Double?

    public init(
        id: String,
        role: StructureTransitionRole,
        chainageMeters: Double,
        point: RoadPoint,
        tangent: RoadPoint,
        groundElevationMeters: Double,
        structureElevationMeters: Double,
        approachGrade: Double?
    ) {
        self.id = id
        self.role = role
        self.chainageMeters = chainageMeters
        self.point = point
        self.tangent = tangent
        self.groundElevationMeters = groundElevationMeters
        self.structureElevationMeters = structureElevationMeters
        self.approachGrade = approachGrade
    }
}

public struct BridgePier: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var chainageMeters: Double
    public var point: RoadPoint
    /// Unit vector following increasing source-road chainage.
    public var tangent: RoadPoint
    public var groundElevationMeters: Double
    public var deckElevationMeters: Double

    public init(
        id: String,
        chainageMeters: Double,
        point: RoadPoint,
        tangent: RoadPoint,
        groundElevationMeters: Double,
        deckElevationMeters: Double
    ) {
        self.id = id
        self.chainageMeters = chainageMeters
        self.point = point
        self.tangent = tangent
        self.groundElevationMeters = groundElevationMeters
        self.deckElevationMeters = deckElevationMeters
    }

    public var heightMeters: Double {
        deckElevationMeters - groundElevationMeters
    }
}

public enum RoadEngineeringConstraintSeverity: String, Codable, Hashable, Sendable {
    case error
}

public enum RoadEngineeringConstraintKind: String, Codable, Hashable, Sendable {
    case belowMinimumLength
    case aboveMaximumBridgeLength
    case structureGradeTooSteep
    case entranceApproachTooSteep
    case exitApproachTooSteep
    case bridgeheadInWater
    case tunnelPortalInWater
    case insufficientTunnelCover
    case bridgeDeckBelowTerrain
}

public enum RoadEngineeringConstraintLocation: String, Codable, Hashable, Sendable {
    case structure
    case entrance
    case exit
    case span
}

public enum RoadEngineeringConstraintComparison: String, Codable, Hashable, Sendable {
    case atLeast
    case atMost
}

public enum RoadEngineeringConstraintUnit: String, Codable, Hashable, Sendable {
    case meters
    case grade
}

public struct RoadEngineeringConstraintIssue: Identifiable, Codable, Hashable, Sendable {
    public var kind: RoadEngineeringConstraintKind
    public var severity: RoadEngineeringConstraintSeverity
    public var location: RoadEngineeringConstraintLocation
    public var measuredValue: Double
    public var limitValue: Double
    public var comparison: RoadEngineeringConstraintComparison
    public var unit: RoadEngineeringConstraintUnit

    public init(
        kind: RoadEngineeringConstraintKind,
        severity: RoadEngineeringConstraintSeverity = .error,
        location: RoadEngineeringConstraintLocation,
        measuredValue: Double,
        limitValue: Double,
        comparison: RoadEngineeringConstraintComparison,
        unit: RoadEngineeringConstraintUnit
    ) {
        self.kind = kind
        self.severity = severity
        self.location = location
        self.measuredValue = measuredValue
        self.limitValue = limitValue
        self.comparison = comparison
        self.unit = unit
    }

    public var id: String {
        "\(kind.rawValue)-\(location.rawValue)"
    }
}

public struct RoadEngineeringReport: Codable, Hashable, Sendable {
    public var structureLengthMeters: Double
    public var minimumLengthMeters: Double
    public var maximumLengthMeters: Double?
    public var structureGrade: Double
    public var maximumStructureGrade: Double
    public var maximumApproachGrade: Double
    public var minimumTunnelCoverMeters: Double?
    public var maximumBridgeSpanMeters: Double?
    public var issues: [RoadEngineeringConstraintIssue]

    public init(
        structureLengthMeters: Double,
        minimumLengthMeters: Double,
        maximumLengthMeters: Double?,
        structureGrade: Double,
        maximumStructureGrade: Double,
        maximumApproachGrade: Double,
        minimumTunnelCoverMeters: Double?,
        maximumBridgeSpanMeters: Double?,
        issues: [RoadEngineeringConstraintIssue]
    ) {
        self.structureLengthMeters = structureLengthMeters
        self.minimumLengthMeters = minimumLengthMeters
        self.maximumLengthMeters = maximumLengthMeters
        self.structureGrade = structureGrade
        self.maximumStructureGrade = maximumStructureGrade
        self.maximumApproachGrade = maximumApproachGrade
        self.minimumTunnelCoverMeters = minimumTunnelCoverMeters
        self.maximumBridgeSpanMeters = maximumBridgeSpanMeters
        self.issues = issues
    }

    public var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }
}

public struct RoadEngineeringStructure: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var sourceRoadID: UUID
    public var candidateID: String?
    public var roadKind: RoadKind
    public var structure: RoadStructureType
    public var startChainageMeters: Double
    public var endChainageMeters: Double
    public var centerline: [RoadPoint]
    public var profile: [RoadVerticalProfileSample]
    public var endpoints: [RoadEngineeringEndpoint]
    public var bridgePiers: [BridgePier]
    public var report: RoadEngineeringReport

    public init(
        id: String,
        sourceRoadID: UUID,
        candidateID: String?,
        roadKind: RoadKind,
        structure: RoadStructureType,
        startChainageMeters: Double,
        endChainageMeters: Double,
        centerline: [RoadPoint],
        profile: [RoadVerticalProfileSample],
        endpoints: [RoadEngineeringEndpoint],
        bridgePiers: [BridgePier],
        report: RoadEngineeringReport
    ) {
        self.id = id
        self.sourceRoadID = sourceRoadID
        self.candidateID = candidateID
        self.roadKind = roadKind
        self.structure = structure
        self.startChainageMeters = startChainageMeters
        self.endChainageMeters = endChainageMeters
        self.centerline = centerline
        self.profile = profile
        self.endpoints = endpoints
        self.bridgePiers = bridgePiers
        self.report = report
    }

    public var tunnelPortals: [RoadEngineeringEndpoint] {
        structure == .tunnel ? endpoints : []
    }
}

public struct RoadEngineeringEvaluation: Codable, Hashable, Sendable {
    public var structures: [RoadEngineeringStructure]

    public init(structures: [RoadEngineeringStructure]) {
        self.structures = structures
    }

    public var reports: [RoadEngineeringReport] {
        structures.map(\.report)
    }

    public var issues: [RoadEngineeringConstraintIssue] {
        reports.flatMap(\.issues)
    }

    public var hasErrors: Bool {
        reports.contains(where: \.hasErrors)
    }

    public func structure(forCandidateID candidateID: String) -> RoadEngineeringStructure? {
        structures.first { $0.candidateID == candidateID }
    }
}

public enum RoadEngineeringPlanner {
    public static func evaluate(
        plan: AutoStructurePlan,
        decisions: [AutoStructureDecision],
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadEngineeringConfiguration = .standard
    ) -> RoadEngineeringEvaluation {
        let candidatesByID = Dictionary(
            plan.candidates.map { ($0.id, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
        var structures: [RoadEngineeringStructure] = []
        var finalChainageCanvas = 0.0
        for span in plan.resolving(decisions) {
            let spanLengthCanvas = EngineeringPolyline(
                points: span.points
            ).totalLength
            let startChainageCanvas = finalChainageCanvas
            finalChainageCanvas += spanLengthCanvas

            guard span.structure == .bridge || span.structure == .tunnel else {
                continue
            }
            let candidate = span.candidateID.flatMap { candidatesByID[$0] }
            let structureID: String
            if let candidateID = span.candidateID {
                structureID = "candidate-\(candidateID)-\(span.structure.rawValue)"
            } else {
                structureID = [
                    "resolved",
                    plan.sourceRoadID.uuidString,
                    span.structure.rawValue,
                    String(Int64((span.range.lowerBound * 1_000).rounded())),
                    String(Int64((span.range.upperBound * 1_000).rounded())),
                ].joined(separator: "-")
            }
            structures.append(
                makeStructure(
                    id: structureID,
                    candidateID: span.candidateID,
                    sourceRoadID: plan.sourceRoadID,
                    roadKind: span.roadKind,
                    structure: span.structure,
                    centerline: span.points,
                    startChainageCanvas: startChainageCanvas,
                    entranceApproachGrade: candidate?.entrance.approachGrade,
                    exitApproachGrade: candidate?.exit.approachGrade,
                    terrain: terrain,
                    mapScale: mapScale,
                    configuration: configuration
                )
            )
        }
        return RoadEngineeringEvaluation(structures: structures)
    }

    public static func evaluate(
        road: RoadSegment,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadEngineeringConfiguration = .standard
    ) -> RoadEngineeringEvaluation {
        guard road.structure == .bridge || road.structure == .tunnel else {
            return RoadEngineeringEvaluation(structures: [])
        }
        let sampler = EngineeringPolyline(points: road.points)
        guard sampler.totalLength > 1e-9 else {
            return RoadEngineeringEvaluation(structures: [])
        }
        let structure = makeStructure(
            id: "manual-\(road.id.uuidString)-\(road.structure.rawValue)",
            candidateID: nil,
            sourceRoadID: road.sourceRoadID,
            roadKind: road.kind,
            structure: road.structure,
            centerline: road.points,
            startChainageCanvas: 0,
            entranceApproachGrade: nil,
            exitApproachGrade: nil,
            terrain: terrain,
            mapScale: mapScale,
            configuration: configuration
        )
        return RoadEngineeringEvaluation(structures: [structure])
    }

    public static func evaluate(
        roads: [RoadSegment],
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadEngineeringConfiguration = .standard
    ) -> RoadEngineeringEvaluation {
        RoadEngineeringEvaluation(
            structures: roads.flatMap {
                evaluate(
                    road: $0,
                    terrain: terrain,
                    mapScale: mapScale,
                    configuration: configuration
                ).structures
            }
        )
    }

    private static func makeStructure(
        id: String,
        candidateID: String?,
        sourceRoadID: UUID,
        roadKind: RoadKind,
        structure: RoadStructureType,
        centerline: [RoadPoint],
        startChainageCanvas: Double,
        entranceApproachGrade: Double?,
        exitApproachGrade: Double?,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadEngineeringConfiguration
    ) -> RoadEngineeringStructure {
        let spanSampler = EngineeringPolyline(points: centerline)
        let lengthCanvas = spanSampler.totalLength
        let lengthMeters = mapScale.meters(forCanvasDistance: lengthCanvas)
        let startChainageMeters = mapScale.meters(
            forCanvasDistance: startChainageCanvas
        )
        let endChainageMeters = startChainageMeters + lengthMeters
        let startSample = spanSampler.sample(at: 0)
        let endSample = spanSampler.sample(at: lengthCanvas)
        let startElevation = surfaceElevation(
            at: startSample.point,
            terrain: terrain,
            configuration: configuration
        )
        let endElevation = surfaceElevation(
            at: endSample.point,
            terrain: terrain,
            configuration: configuration
        )
        let structureGrade = lengthMeters > 1e-9
            ? abs(endElevation - startElevation) / lengthMeters
            : 0
        let sampleSpacing = max(1, configuration.profileSampleSpacingMeters)
        let intervalCount = max(1, Int(ceil(lengthMeters / sampleSpacing)))
        let profile = (0...intervalCount).map { index in
            let fraction = Double(index) / Double(intervalCount)
            let localCanvasDistance = lengthCanvas * fraction
            let sampled = spanSampler.sample(at: localCanvasDistance)
            let structureElevation = startElevation
                + (endElevation - startElevation) * fraction
            return RoadVerticalProfileSample(
                chainageMeters: startChainageMeters + lengthMeters * fraction,
                point: sampled.point,
                surfaceElevationMeters: surfaceElevation(
                    at: sampled.point,
                    terrain: terrain,
                    configuration: configuration
                ),
                structureElevationMeters: structureElevation
            )
        }
        let endpoints = [
            RoadEngineeringEndpoint(
                id: "\(id)-entrance",
                role: .entrance,
                chainageMeters: startChainageMeters,
                point: startSample.point,
                tangent: startSample.tangent,
                groundElevationMeters: startElevation,
                structureElevationMeters: startElevation,
                approachGrade: entranceApproachGrade
            ),
            RoadEngineeringEndpoint(
                id: "\(id)-exit",
                role: .exit,
                chainageMeters: endChainageMeters,
                point: endSample.point,
                tangent: endSample.tangent,
                groundElevationMeters: endElevation,
                structureElevationMeters: endElevation,
                approachGrade: exitApproachGrade
            ),
        ]
        let limits = configuration.limits(for: roadKind)
        let piers = structure == .bridge
            ? makeBridgePiers(
                structureID: id,
                sampler: spanSampler,
                lengthMeters: lengthMeters,
                startChainageMeters: startChainageMeters,
                startElevation: startElevation,
                endElevation: endElevation,
                maximumSpanMeters: limits.maximumBridgeSpanMeters,
                terrain: terrain,
                mapScale: mapScale,
                configuration: configuration
            )
            : []
        let minimumTunnelCover = structure == .tunnel
            ? minimumInteriorTunnelCover(profile)
            : nil
        let report = makeReport(
            structure: structure,
            roadKind: roadKind,
            lengthMeters: lengthMeters,
            structureGrade: structureGrade,
            entrance: endpoints[0],
            exit: endpoints[1],
            profile: profile,
            minimumTunnelCover: minimumTunnelCover,
            terrain: terrain,
            configuration: configuration
        )
        return RoadEngineeringStructure(
            id: id,
            sourceRoadID: sourceRoadID,
            candidateID: candidateID,
            roadKind: roadKind,
            structure: structure,
            startChainageMeters: startChainageMeters,
            endChainageMeters: endChainageMeters,
            centerline: centerline,
            profile: profile,
            endpoints: endpoints,
            bridgePiers: piers,
            report: report
        )
    }

    private static func makeBridgePiers(
        structureID: String,
        sampler: EngineeringPolyline,
        lengthMeters: Double,
        startChainageMeters: Double,
        startElevation: Double,
        endElevation: Double,
        maximumSpanMeters: Double,
        terrain: TerrainLayout,
        mapScale: MapScale,
        configuration: RoadEngineeringConfiguration
    ) -> [BridgePier] {
        guard lengthMeters > maximumSpanMeters + 1e-9,
              maximumSpanMeters > 0
        else { return [] }
        let spanCount = max(1, Int(ceil(lengthMeters / maximumSpanMeters)))
        let pierCount = spanCount - 1
        return (1...pierCount).map { index in
            let fraction = Double(index) / Double(spanCount)
            let localMeters = lengthMeters * fraction
            let localCanvasDistance = mapScale.canvasDistance(forMeters: localMeters)
            let sampled = sampler.sample(at: localCanvasDistance)
            let deckElevation = startElevation
                + (endElevation - startElevation) * fraction
            return BridgePier(
                id: "\(structureID)-pier-\(index)",
                chainageMeters: startChainageMeters + localMeters,
                point: sampled.point,
                tangent: sampled.tangent,
                groundElevationMeters: surfaceElevation(
                    at: sampled.point,
                    terrain: terrain,
                    configuration: configuration
                ),
                deckElevationMeters: deckElevation
            )
        }
    }

    private static func minimumInteriorTunnelCover(
        _ profile: [RoadVerticalProfileSample]
    ) -> Double? {
        guard profile.count >= 3,
              let start = profile.first?.chainageMeters,
              let end = profile.last?.chainageMeters,
              end > start
        else { return nil }
        let lower = start + (end - start) * 0.2
        let upper = start + (end - start) * 0.8
        let interior = profile.filter {
            $0.chainageMeters >= lower - 1e-9
                && $0.chainageMeters <= upper + 1e-9
        }
        return interior.map {
            $0.surfaceElevationMeters - $0.structureElevationMeters
        }.min()
    }

    private static func makeReport(
        structure: RoadStructureType,
        roadKind: RoadKind,
        lengthMeters: Double,
        structureGrade: Double,
        entrance: RoadEngineeringEndpoint,
        exit: RoadEngineeringEndpoint,
        profile: [RoadVerticalProfileSample],
        minimumTunnelCover: Double?,
        terrain: TerrainLayout,
        configuration: RoadEngineeringConfiguration
    ) -> RoadEngineeringReport {
        let limits = configuration.limits(for: roadKind)
        let minimumLength = structure == .bridge
            ? limits.minimumBridgeLengthMeters
            : limits.minimumTunnelLengthMeters
        let maximumLength = structure == .bridge
            ? limits.maximumBridgeLengthMeters
            : nil
        var issues: [RoadEngineeringConstraintIssue] = []

        if lengthMeters + 1e-9 < minimumLength {
            issues.append(
                RoadEngineeringConstraintIssue(
                    kind: .belowMinimumLength,
                    location: .structure,
                    measuredValue: lengthMeters,
                    limitValue: minimumLength,
                    comparison: .atLeast,
                    unit: .meters
                )
            )
        }
        if let maximumLength, lengthMeters > maximumLength + 1e-9 {
            issues.append(
                RoadEngineeringConstraintIssue(
                    kind: .aboveMaximumBridgeLength,
                    location: .structure,
                    measuredValue: lengthMeters,
                    limitValue: maximumLength,
                    comparison: .atMost,
                    unit: .meters
                )
            )
        }
        if structureGrade > limits.maximumStructureGrade + 1e-12 {
            issues.append(
                RoadEngineeringConstraintIssue(
                    kind: .structureGradeTooSteep,
                    location: .structure,
                    measuredValue: structureGrade,
                    limitValue: limits.maximumStructureGrade,
                    comparison: .atMost,
                    unit: .grade
                )
            )
        }
        if let entranceGrade = entrance.approachGrade,
           abs(entranceGrade) > limits.maximumApproachGrade + 1e-12 {
            issues.append(
                RoadEngineeringConstraintIssue(
                    kind: .entranceApproachTooSteep,
                    location: .entrance,
                    measuredValue: abs(entranceGrade),
                    limitValue: limits.maximumApproachGrade,
                    comparison: .atMost,
                    unit: .grade
                )
            )
        }
        if let exitGrade = exit.approachGrade,
           abs(exitGrade) > limits.maximumApproachGrade + 1e-12 {
            issues.append(
                RoadEngineeringConstraintIssue(
                    kind: .exitApproachTooSteep,
                    location: .exit,
                    measuredValue: abs(exitGrade),
                    limitValue: limits.maximumApproachGrade,
                    comparison: .atMost,
                    unit: .grade
                )
            )
        }

        if structure == .bridge {
            for endpoint in [entrance, exit] {
                let normalizedElevation = terrain.normalizedElevation(at: endpoint.point)
                if normalizedElevation
                    <= terrain.waterLevel + configuration.waterTolerance {
                    issues.append(
                        RoadEngineeringConstraintIssue(
                            kind: .bridgeheadInWater,
                            location: endpoint.role == .entrance ? .entrance : .exit,
                            measuredValue: normalizedElevation
                                * configuration.elevationScaleMeters,
                            limitValue: (
                                terrain.waterLevel + configuration.waterTolerance
                            ) * configuration.elevationScaleMeters,
                            comparison: .atLeast,
                            unit: .meters
                        )
                    )
                }
            }
            let interior = interiorProfile(profile)
            if let minimumSeparation = interior.map(\.verticalSeparationMeters).min(),
               minimumSeparation < -1e-9 {
                issues.append(
                    RoadEngineeringConstraintIssue(
                        kind: .bridgeDeckBelowTerrain,
                        location: .span,
                        measuredValue: minimumSeparation,
                        limitValue: 0,
                        comparison: .atLeast,
                        unit: .meters
                    )
                )
            }
        }

        if structure == .tunnel {
            for endpoint in [entrance, exit] {
                let normalizedElevation = terrain.normalizedElevation(at: endpoint.point)
                if normalizedElevation
                    <= terrain.waterLevel + configuration.waterTolerance {
                    issues.append(
                        RoadEngineeringConstraintIssue(
                            kind: .tunnelPortalInWater,
                            location: endpoint.role == .entrance ? .entrance : .exit,
                            measuredValue: normalizedElevation
                                * configuration.elevationScaleMeters,
                            limitValue: (
                                terrain.waterLevel + configuration.waterTolerance
                            ) * configuration.elevationScaleMeters,
                            comparison: .atLeast,
                            unit: .meters
                        )
                    )
                }
            }
            if let minimumTunnelCover,
               minimumTunnelCover + 1e-9
                    < configuration.minimumTunnelCoverMeters {
                issues.append(
                    RoadEngineeringConstraintIssue(
                        kind: .insufficientTunnelCover,
                        location: .span,
                        measuredValue: minimumTunnelCover,
                        limitValue: configuration.minimumTunnelCoverMeters,
                        comparison: .atLeast,
                        unit: .meters
                    )
                )
            }
        }

        return RoadEngineeringReport(
            structureLengthMeters: lengthMeters,
            minimumLengthMeters: minimumLength,
            maximumLengthMeters: maximumLength,
            structureGrade: structureGrade,
            maximumStructureGrade: limits.maximumStructureGrade,
            maximumApproachGrade: limits.maximumApproachGrade,
            minimumTunnelCoverMeters: minimumTunnelCover,
            maximumBridgeSpanMeters: structure == .bridge
                ? limits.maximumBridgeSpanMeters
                : nil,
            issues: issues
        )
    }

    private static func interiorProfile(
        _ profile: [RoadVerticalProfileSample]
    ) -> [RoadVerticalProfileSample] {
        guard profile.count >= 3,
              let start = profile.first?.chainageMeters,
              let end = profile.last?.chainageMeters,
              end > start
        else { return [] }
        let lower = start + (end - start) * 0.15
        let upper = start + (end - start) * 0.85
        return profile.filter {
            $0.chainageMeters >= lower - 1e-9
                && $0.chainageMeters <= upper + 1e-9
        }
    }

    private static func surfaceElevation(
        at point: RoadPoint,
        terrain: TerrainLayout,
        configuration: RoadEngineeringConfiguration
    ) -> Double {
        terrain.normalizedElevation(at: point) * configuration.elevationScaleMeters
    }
}

private struct EngineeringPolyline {
    struct Sample {
        var point: RoadPoint
        var tangent: RoadPoint
    }

    var points: [RoadPoint]
    var cumulativeDistances: [Double]
    var totalLength: Double

    init(points: [RoadPoint]) {
        self.points = points
        var cumulative = [0.0]
        cumulative.reserveCapacity(max(1, points.count))
        for pair in zip(points, points.dropFirst()) {
            cumulative.append(cumulative.last! + pair.0.distance(to: pair.1))
        }
        cumulativeDistances = cumulative
        totalLength = cumulative.last ?? 0
    }

    func sample(at distance: Double) -> Sample {
        guard let first = points.first else {
            return Sample(
                point: RoadPoint(x: 0, y: 0),
                tangent: RoadPoint(x: 1, y: 0)
            )
        }
        guard points.count >= 2, totalLength > 1e-9 else {
            return Sample(point: first, tangent: RoadPoint(x: 1, y: 0))
        }
        let target = min(totalLength, max(0, distance))
        var fallbackTangent = RoadPoint(x: 1, y: 0)
        for index in 0..<(points.count - 1) {
            let start = points[index]
            let end = points[index + 1]
            let dx = end.x - start.x
            let dy = end.y - start.y
            let segmentLength = hypot(dx, dy)
            guard segmentLength > 1e-9 else { continue }
            fallbackTangent = RoadPoint(
                x: dx / segmentLength,
                y: dy / segmentLength
            )
            let segmentStart = cumulativeDistances[index]
            let segmentEnd = cumulativeDistances[index + 1]
            if target <= segmentEnd + 1e-9 {
                let fraction = min(
                    1,
                    max(0, (target - segmentStart) / segmentLength)
                )
                return Sample(
                    point: RoadPoint(
                        x: start.x + dx * fraction,
                        y: start.y + dy * fraction
                    ),
                    tangent: fallbackTangent
                )
            }
        }
        return Sample(point: points.last ?? first, tangent: fallbackTangent)
    }

    func slice(from start: Double, to end: Double) -> [RoadPoint] {
        guard !points.isEmpty else { return [] }
        let boundedStart = min(totalLength, max(0, start))
        let boundedEnd = min(totalLength, max(boundedStart, end))
        var result = [sample(at: boundedStart).point]
        for index in points.indices.dropFirst() {
            let distance = cumulativeDistances[index]
            if distance > boundedStart + 1e-9
                && distance < boundedEnd - 1e-9 {
                result.append(points[index])
            }
        }
        let finalPoint = sample(at: boundedEnd).point
        if result.last?.distance(to: finalPoint) ?? .infinity > 1e-9 {
            result.append(finalPoint)
        }
        return result
    }
}
