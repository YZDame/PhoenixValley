import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func bridgePiersRespectMaximumSpanOnStraightAndCurvedCenterlines() throws {
    let terrain = engineeringTerrain { _ in 0.3 }
    let straight = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 0, y: 200),
            RoadPoint(x: 200, y: 200),
        ]
    )
    let straightStructure = try #require(
        RoadEngineeringPlanner.evaluate(
            road: straight,
            terrain: terrain,
            mapScale: .standard
        ).structures.first
    )

    #expect(straightStructure.bridgePiers.count == 2)
    let chainages = [0.0]
        + straightStructure.bridgePiers.map(\.chainageMeters)
        + [straightStructure.report.structureLengthMeters]
    let spans = zip(chainages, chainages.dropFirst()).map { $1 - $0 }
    #expect(spans.allSatisfy {
        $0 <= (straightStructure.report.maximumBridgeSpanMeters ?? 0) + 1e-9
    })
    #expect(abs(straightStructure.bridgePiers[0].point.x - 200 / 3) < 1e-6)

    let curved = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 0, y: 200),
            RoadPoint(x: 100, y: 200),
            RoadPoint(x: 100, y: 300),
        ]
    )
    let curvedStructure = try #require(
        RoadEngineeringPlanner.evaluate(
            road: curved,
            terrain: terrain,
            mapScale: .standard
        ).structures.first
    )
    #expect(curvedStructure.bridgePiers.count == 2)
    #expect(curvedStructure.bridgePiers[0].tangent == RoadPoint(x: 1, y: 0))
    #expect(curvedStructure.bridgePiers[1].tangent == RoadPoint(x: 0, y: 1))
    #expect(abs(curvedStructure.bridgePiers[1].point.y - (200 + 100 / 3)) < 1e-6)
}

@Test func bridgePierLayoutUsesPhysicalMetresAtEveryMapScale() throws {
    let terrain = engineeringTerrain { _ in 0.3 }
    for metersPerPoint in [0.5, 1, 2, 5] {
        let mapScale = MapScale(metersPerPoint: metersPerPoint)
        let road = RoadSegment(
            kind: .arterial,
            structure: .bridge,
            points: [
                RoadPoint(x: 0, y: 200),
                RoadPoint(x: 400 / metersPerPoint, y: 200),
            ]
        )
        let structure = try #require(
            RoadEngineeringPlanner.evaluate(
                road: road,
                terrain: terrain,
                mapScale: mapScale
            ).structures.first
        )

        #expect(abs(structure.report.structureLengthMeters - 400) < 1e-9)
        #expect(structure.bridgePiers.count == 4)
        #expect(structure.bridgePiers.map(\.chainageMeters) == [80, 160, 240, 320])
    }
}

@Test func bridgeLengthBoundsAreInclusive() throws {
    let terrain = engineeringTerrain { _ in 0.3 }
    let minimum = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 10, y: 200), RoadPoint(x: 40, y: 200)]
    )
    let short = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 10, y: 200), RoadPoint(x: 39.999, y: 200)]
    )
    let maximum = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 200), RoadPoint(x: 600, y: 200)]
    )
    let long = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 200), RoadPoint(x: 600.001, y: 200)]
    )

    let minimumReport = try engineeringReport(
        minimum,
        terrain: terrain,
        mapScale: .standard
    )
    let shortReport = try engineeringReport(
        short,
        terrain: terrain,
        mapScale: .standard
    )
    let maximumReport = try engineeringReport(
        maximum,
        terrain: terrain,
        mapScale: MapScale(metersPerPoint: 5)
    )
    let longReport = try engineeringReport(
        long,
        terrain: terrain,
        mapScale: MapScale(metersPerPoint: 5)
    )

    #expect(!minimumReport.issues.contains { $0.kind == .belowMinimumLength })
    #expect(shortReport.issues.contains { $0.kind == .belowMinimumLength })
    #expect(!maximumReport.issues.contains { $0.kind == .aboveMaximumBridgeLength })
    #expect(longReport.issues.contains { $0.kind == .aboveMaximumBridgeLength })
}

@Test func tunnelUsesModeledAxisGradeAndPersistsOrientedPortals() throws {
    let terrain = engineeringTerrain { point in
        guard point.x <= 200 else { return 0.3 }
        let ridge = 1 - abs(point.x - 100) / 100
        return 0.3 + max(0, ridge) * 0.3
    }
    let tunnel = RoadSegment(
        kind: .arterial,
        structure: .tunnel,
        points: [
            RoadPoint(x: 0, y: 300),
            RoadPoint(x: 100, y: 300),
            RoadPoint(x: 200, y: 300),
        ]
    )
    let structure = try #require(
        RoadEngineeringPlanner.evaluate(
            road: tunnel,
            terrain: terrain,
            mapScale: .standard
        ).structures.first
    )

    #expect(abs(structure.report.structureGrade) < 1e-9)
    #expect((structure.report.minimumTunnelCoverMeters ?? 0) > 20)
    #expect(structure.tunnelPortals.map(\.role) == [.entrance, .exit])
    #expect(structure.tunnelPortals.map(\.point) == [
        RoadPoint(x: 0, y: 300),
        RoadPoint(x: 200, y: 300),
    ])
    #expect(structure.tunnelPortals.allSatisfy {
        $0.tangent == RoadPoint(x: 1, y: 0)
    })
    #expect(!structure.report.hasErrors)
}

@Test func automaticCurvedTunnelEngineeringUsesResolvedDirectGeometry() throws {
    let sourceRoadID = UUID()
    let sourcePoints = [
        RoadPoint(x: 0, y: 300),
        RoadPoint(x: 100, y: 100),
        RoadPoint(x: 200, y: 300),
    ]
    let curvedLength = hypot(100.0, 200.0) * 2
    let candidateID = "curved-tunnel"
    let transitionMetrics = AutoStructureMetrics(
        minimumElevation: 0.3,
        maximumElevation: 0.6,
        maximumAbsoluteGrade: 0.1,
        maximumRidgeProminence: 0.2,
        surfaceLength: curvedLength,
        directStructureLength: 200,
        lengthAdvantageRatio: 0.2,
        waterSampleCount: 0
    )
    let sampleRange = StructureSampleRange(
        startSampleIndex: 0,
        endSampleIndex: 2,
        startDistance: 0,
        endDistance: curvedLength
    )
    let entrance = StructureTransitionHint(
        role: .entrance,
        kind: .tunnelPortal,
        point: sourcePoints[0],
        distance: 0,
        terrainElevation: 0.3,
        approachGrade: 0,
        recommendedApproachLength: 20
    )
    let exit = StructureTransitionHint(
        role: .exit,
        kind: .tunnelPortal,
        point: sourcePoints[2],
        distance: curvedLength,
        terrainElevation: 0.3,
        approachGrade: 0,
        recommendedApproachLength: 20
    )
    let candidate = AutoStructureCandidate(
        id: candidateID,
        sourceRoadID: sourceRoadID,
        sourceEdgeID: sourceRoadID,
        structure: .tunnel,
        startPoint: sourcePoints[0],
        endPoint: sourcePoints[2],
        evidence: AutoStructureEvidence(
            triggers: [.mountainRelief, .tunnelLengthAdvantage],
            sampleRange: sampleRange,
            metrics: transitionMetrics
        ),
        entrance: entrance,
        exit: exit
    )
    let plan = AutoStructurePlan(
        sourceRoadID: sourceRoadID,
        sourceEdgeID: sourceRoadID,
        roadKind: .arterial,
        sourceLevel: .ground,
        sourcePoints: sourcePoints,
        totalLength: curvedLength,
        samples: [],
        candidates: [candidate],
        crossingSuggestions: []
    )
    let decisions = [
        AutoStructureDecision(candidateID: candidateID, resolution: .accept),
    ]
    let resolvedTunnel = try #require(
        plan.resolving(decisions).first {
            $0.structure == RoadStructureType.tunnel
        }
    )
    let terrain = engineeringTerrain { point in
        let ridge = max(0, 1 - abs(point.x - 100) / 100)
        return 0.3 + ridge * 0.3
    }
    let structure = try #require(
        RoadEngineeringPlanner.evaluate(
            plan: plan,
            decisions: decisions,
            terrain: terrain,
            mapScale: .standard
        ).structures.first
    )

    #expect(resolvedTunnel.points == [
        RoadPoint(x: 0, y: 300),
        RoadPoint(x: 200, y: 300),
    ])
    #expect(structure.centerline == resolvedTunnel.points)
    #expect(abs(structure.report.structureLengthMeters - 200) < 1e-9)
    #expect(abs(structure.endChainageMeters - 200) < 1e-9)
    #expect(structure.profile.allSatisfy { abs($0.point.y - 300) < 1e-9 })
    #expect(structure.tunnelPortals.allSatisfy {
        $0.tangent == RoadPoint(x: 1, y: 0)
    })
}

@Test func sameSourceManualFragmentsHaveDistinctEngineeringStructureIDs() {
    let sourceRoadID = UUID()
    let first = RoadSegment(
        id: UUID(),
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 0, y: 200),
            RoadPoint(x: 120, y: 200),
        ],
        sourceRoadID: sourceRoadID
    )
    let second = RoadSegment(
        id: UUID(),
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 240, y: 200),
            RoadPoint(x: 360, y: 200),
        ],
        sourceRoadID: sourceRoadID
    )
    let evaluation = RoadEngineeringPlanner.evaluate(
        roads: [first, second],
        terrain: engineeringTerrain { _ in 0.3 },
        mapScale: .standard
    )

    #expect(evaluation.structures.count == 2)
    #expect(Set(evaluation.structures.map(\.id)).count == 2)
    #expect(evaluation.structures.allSatisfy { $0.sourceRoadID == sourceRoadID })
    #expect(evaluation.structures.contains {
        $0.id.contains(first.id.uuidString)
    })
    #expect(evaluation.structures.contains {
        $0.id.contains(second.id.uuidString)
    })
}

@Test func erasedBridgeFragmentsCanBeReevaluatedWithoutLosingConstraints() {
    let sourceRoadID = UUID()
    let bridge = RoadSegment(
        id: sourceRoadID,
        kind: .arterial,
        structure: .bridge,
        points: [
            RoadPoint(x: 0, y: 200),
            RoadPoint(x: 100, y: 200),
        ],
        sourceRoadID: sourceRoadID
    )
    let eraseResult = RoadNetwork.erasing(
        RoadEraseRequest(
            points: [RoadPoint(x: 50, y: 200)],
            radius: 36,
            eligibleRoadIDs: [sourceRoadID]
        ),
        from: [bridge]
    )
    let remaining = eraseResult.network.roadSegments.filter {
        $0.sourceRoadID == sourceRoadID && $0.structure == .bridge
    }
    let evaluation = RoadEngineeringPlanner.evaluate(
        roads: remaining,
        terrain: engineeringTerrain { _ in 0.3 },
        mapScale: .standard
    )

    #expect(remaining.count == 2)
    #expect(evaluation.structures.count == 2)
    #expect(Set(evaluation.structures.map(\.id)).count == 2)
    #expect(evaluation.structures.allSatisfy {
        $0.report.issues.contains { $0.kind == .belowMinimumLength }
    })
}

@Test func replacingWaterBridgeWithTunnelIsRevalidated() throws {
    let terrain = engineeringTerrain(waterLevel: 0.2) { point in
        point.x > 40 && point.x < 160 ? 0.1 : 0.3
    }
    let road = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 0, y: 300), RoadPoint(x: 200, y: 300)]
    )
    var configuration = AutoStructurePlannerConfiguration.standard
    configuration.sampleSpacing = 10
    configuration.bridgeApproachLength = 0
    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    let bridge = try #require(
        plan.candidates.first { $0.structure == .bridge }
    )
    let evaluation = RoadEngineeringPlanner.evaluate(
        plan: plan,
        decisions: [
            AutoStructureDecision(
                candidateID: bridge.id,
                resolution: .replace(with: .tunnel)
            ),
        ],
        terrain: terrain,
        mapScale: .standard
    )

    #expect(evaluation.hasErrors)
    #expect(evaluation.issues.contains {
        $0.kind == .insufficientTunnelCover
            || $0.kind == .tunnelPortalInWater
    })
}

@Test func engineeringStructuresRoundTripWithRoadProject() throws {
    let terrain = engineeringTerrain { _ in 0.3 }
    let road = RoadSegment(
        kind: .arterial,
        structure: .bridge,
        points: [RoadPoint(x: 0, y: 200), RoadPoint(x: 200, y: 200)]
    )
    let structure = try #require(
        RoadEngineeringPlanner.evaluate(
            road: road,
            terrain: terrain,
            mapScale: .standard
        ).structures.first
    )
    let project = RoadProject(
        name: "Engineering",
        terrain: terrain,
        roads: [road],
        engineeringStructures: [structure]
    )

    let data = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(RoadProject.self, from: data)

    #expect(decoded.formatVersion == RoadProject.currentFormatVersion)
    #expect(decoded.engineeringStructures == [structure])
    #expect(decoded.engineeringStructures[0].bridgePiers.count == 2)
}

private func engineeringReport(
    _ road: RoadSegment,
    terrain: TerrainLayout,
    mapScale: MapScale
) throws -> RoadEngineeringReport {
    try #require(
        RoadEngineeringPlanner.evaluate(
            road: road,
            terrain: terrain,
            mapScale: mapScale
        ).structures.first
    ).report
}

private func engineeringTerrain(
    waterLevel: Double = 0.2,
    elevation: (RoadPoint) -> Double
) -> TerrainLayout {
    let width = 161
    let height = 121
    var values: [UInt16] = []
    values.reserveCapacity(width * height)
    for row in 0..<height {
        for column in 0..<width {
            let point = RoadPoint(
                x: Double(column) / Double(width - 1) * 1_600,
                y: Double(row) / Double(height - 1) * 1_200
            )
            let value = min(1, max(0, elevation(point)))
            values.append(UInt16((value * Double(UInt16.max)).rounded()))
        }
    }
    return TerrainLayout(
        seed: 1,
        shoreline: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 1_600, y: 0),
            RoadPoint(x: 1_600, y: 1_200),
            RoadPoint(x: 0, y: 1_200),
        ],
        gridWidth: width,
        gridHeight: height,
        elevations: values,
        waterLevel: waterLevel
    )
}
