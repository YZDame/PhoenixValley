import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func automaticStructureSamplingUsesFinalGeometryAtEqualDistances() {
    let road = RoadSegment(
        kind: .street,
        points: [
            RoadPoint(x: 100, y: 600),
            RoadPoint(x: 250, y: 600),
            RoadPoint(x: 1_300, y: 600),
        ]
    )
    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: fixtureTerrain { _ in 0.3 },
        existingRoads: [],
        configuration: testConfiguration(sampleSpacing: 130)
    )

    #expect(plan.samples.count == 11)
    let spacings = zip(plan.samples, plan.samples.dropFirst()).map {
        $1.distance - $0.distance
    }
    #expect(spacings.allSatisfy { abs($0 - 120) < 0.000_001 })
    #expect(plan.samples[2].point == RoadPoint(x: 340, y: 600))
    #expect(plan.candidates.isEmpty)
}

@Test func continuousWaterProducesOneExplicitBridgeAcrossLandWaterBoundaries() throws {
    let terrain = fixtureTerrain { point in
        (point.x >= 560 && point.x <= 1_020) ? 0.12 : 0.31
    }
    let road = horizontalRoad(kind: .arterial)
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.bridgeApproachLength = 20
    configuration.minimumBridgeLength = 40

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    let bridges = plan.candidates.filter { $0.structure == .bridge }

    #expect(bridges.count == 1)
    let bridge = try #require(bridges.first)
    #expect(bridge.startPoint.x < 560)
    #expect(bridge.endPoint.x > 1_020)
    #expect(bridge.evidence.triggers.contains(.water))
    #expect(bridge.evidence.metrics.waterSampleCount > 10)
    #expect(bridge.entrance.kind == .bridgehead)
    #expect(bridge.exit.kind == .bridgehead)
}

@Test func waterThresholdIsInclusiveAndCannotBeSuppressedAsShortGroundFragment() {
    let encodedWater = Double(UInt16((0.2 * Double(UInt16.max)).rounded()))
        / Double(UInt16.max)
    let terrain = fixtureTerrain(waterLevel: encodedWater) { _ in 0.2 }
    let road = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 700, y: 600), RoadPoint(x: 720, y: 600)]
    )
    var configuration = testConfiguration(sampleSpacing: 10)
    configuration.waterTolerance = 0
    configuration.minimumBridgeLength = 60
    configuration.bridgeApproachLength = 0

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )

    #expect(plan.samples.allSatisfy { $0.isWater })
    #expect(plan.candidates.count == 1)
    #expect(plan.candidates.first?.structure == .bridge)
    #expect(
        plan.candidates.first?.entrance.warnings.contains(
            .belowPreferredStructureLength
        ) == true
    )
}

@Test func tunnelLengthAdvantageThresholdIsInclusive() throws {
    let terrain = mountainTerrain()
    let road = horizontalRoad(kind: .arterial)
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.minimumTunnelLength = 40
    configuration.tunnelPortalSearchDistance = 20
    configuration.tunnelLengthAdvantageThreshold = 0

    let baseline = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    let baselineTunnel = try #require(
        baseline.candidates.first { $0.structure == .tunnel }
    )
    let measuredThreshold = baselineTunnel.evidence.metrics.lengthAdvantageRatio
    #expect(measuredThreshold > 0.01)

    configuration.tunnelLengthAdvantageThreshold = measuredThreshold
    let boundary = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    #expect(boundary.candidates.contains { $0.structure == .tunnel })

    configuration.tunnelLengthAdvantageThreshold = measuredThreshold + 0.000_001
    let aboveBoundary = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    #expect(!aboveBoundary.candidates.contains { $0.structure == .tunnel })
}

@Test func valleyAndGentleSaddleRemainGround() {
    let valley = fixtureTerrain { point in
        let lateralDistance = abs(point.y - 600)
        return 0.28 + min(0.22, lateralDistance / 500)
    }
    let saddle = fixtureTerrain { point in
        let broadShoulder = 0.32 + 0.025 * cos((point.x - 800) / 260)
        let loweredPass = 0.04 * exp(-pow((point.y - 600) / 100, 2))
        return broadShoulder - loweredPass
    }
    let road = horizontalRoad(kind: .arterial)
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.mountainElevationThreshold = 0.4
    configuration.steepGradeThreshold = 0.09
    configuration.ridgeProminenceThreshold = 0.04

    let valleyPlan = AutoStructurePlanner.plan(
        for: road,
        terrain: valley,
        existingRoads: [],
        configuration: configuration
    )
    let saddlePlan = AutoStructurePlanner.plan(
        for: road,
        terrain: saddle,
        existingRoads: [],
        configuration: configuration
    )

    #expect(!valleyPlan.candidates.contains { $0.structure == .tunnel })
    #expect(!saddlePlan.candidates.contains { $0.structure == .tunnel })
    #expect(valleyPlan.samples.map(\.ridgeProminence).max() ?? 1 <= 0)
}

@Test func mixedTerrainPreservesBridgeAndTunnelContinuityOverCrossingAdvice() throws {
    let terrain = fixtureTerrain { point in
        if point.x >= 480 && point.x <= 700 {
            return 0.1
        }
        let mountain = max(0, 1 - abs(point.x - 1_020) / 210)
        return 0.3 + mountain * 0.48
    }
    let road = horizontalRoad(kind: .arterial)
    let existing = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 600, y: 250), RoadPoint(x: 600, y: 950)]
    )
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.tunnelLengthAdvantageThreshold = 0.02
    configuration.minimumTunnelLength = 40
    configuration.tunnelPortalSearchDistance = 20
    configuration.crossingApproachLength = 60

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [existing],
        configuration: configuration
    )
    let crossing = try #require(plan.crossingSuggestions.first)
    #expect(crossing.treatment == .deferToPrimaryStructure)
    #expect(crossing.protectedStructure == .bridge)
    #expect(plan.candidates.contains { $0.structure == .bridge })
    #expect(plan.candidates.contains { $0.structure == .tunnel })
    #expect(
        plan.candidates.contains {
            $0.structure == .bridge
                && crossing.sourceDistance >= $0.evidence.sampleRange.startDistance
                && crossing.sourceDistance <= $0.evidence.sampleRange.endDistance
        }
    )
    #expect(
        !plan.candidates.contains {
            $0.structure == .elevated
                && crossing.sourceDistance >= $0.evidence.sampleRange.startDistance
                && crossing.sourceDistance <= $0.evidence.sampleRange.endDistance
        }
    )
}

@Test func roadCrossingRulesUseKindAngleAndExistingVerticalLevel() throws {
    let terrain = fixtureTerrain { _ in 0.3 }
    let source = horizontalRoad(kind: .street)
    let motorway = RoadSegment(
        kind: .motorway,
        points: [RoadPoint(x: 800, y: 250), RoadPoint(x: 800, y: 950)]
    )
    let elevated = RoadSegment(
        kind: .arterial,
        level: .elevated,
        points: [RoadPoint(x: 1_000, y: 250), RoadPoint(x: 1_000, y: 950)]
    )
    let shallow = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 350, y: 570), RoadPoint(x: 1_250, y: 630)]
    )
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.crossingMinimumAngle = .pi / 6

    let plan = AutoStructurePlanner.plan(
        for: source,
        terrain: terrain,
        existingRoads: [motorway, elevated, shallow],
        configuration: configuration
    )
    let motorwayCrossing = try #require(
        plan.crossingSuggestions.first { $0.existingRoadID == motorway.id }
    )
    let elevatedCrossing = try #require(
        plan.crossingSuggestions.first { $0.existingRoadID == elevated.id }
    )
    let shallowCrossing = try #require(
        plan.crossingSuggestions.first { $0.existingRoadID == shallow.id }
    )

    #expect(motorwayCrossing.treatment == .elevated)
    #expect(elevatedCrossing.treatment == .preserveExistingSeparation)
    #expect(elevatedCrossing.triggers.contains(.existingVerticalSeparation))
    #expect(shallowCrossing.treatment == .atGrade)
}

@Test func nearbyWaterFragmentsMergeAndAcceptedPlanSplitsFinalGeometry() throws {
    let terrain = fixtureTerrain { point in
        if (point.x >= 520 && point.x <= 650)
            || (point.x >= 665 && point.x <= 790) {
            return 0.1
        }
        return 0.3
    }
    let road = horizontalRoad(kind: .street)
    var configuration = testConfiguration(sampleSpacing: 10)
    configuration.bridgeApproachLength = 0
    configuration.maximumMergeableGroundGap = 25
    configuration.minimumBridgeLength = 20

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    let bridge = try #require(
        plan.candidates.first { $0.structure == .bridge }
    )

    #expect(plan.candidates.filter { $0.structure == .bridge }.count == 1)
    #expect(bridge.evidence.sampleRange.startDistance < 500)
    #expect(bridge.evidence.sampleRange.endDistance > 580)

    let accepted = plan.acceptingAllCandidates()
    #expect(accepted.map(\.structure) == [.ground, .bridge, .ground])
    #expect(accepted[1].points.first == bridge.startPoint)
    #expect(accepted[1].points.last == bridge.endPoint)

    let rejected = plan.resolving([
        AutoStructureDecision(candidateID: bridge.id, resolution: .reject),
    ])
    #expect(rejected.map(\.structure) == [.ground, .bridge, .ground])

    let replacedWithGround = plan.resolving([
        AutoStructureDecision(
            candidateID: bridge.id,
            resolution: .replace(with: .ground)
        ),
    ])
    #expect(replacedWithGround.map(\.structure) == [.ground, .bridge, .ground])
}

@Test func topologySourceIdentifiersStayStableAndSiblingEdgesAreIgnored() throws {
    let sourceRoadID = UUID()
    let externalRoadID = UUID()
    let firstEdge = RoadSegment(
        id: UUID(),
        kind: .street,
        points: [RoadPoint(x: 200, y: 600), RoadPoint(x: 1_400, y: 600)],
        sourceRoadID: sourceRoadID
    )
    let rebuiltEdge = RoadSegment(
        id: UUID(),
        kind: .street,
        points: firstEdge.points,
        sourceRoadID: sourceRoadID
    )
    let siblingEdge = RoadSegment(
        id: UUID(),
        kind: .motorway,
        points: [RoadPoint(x: 600, y: 250), RoadPoint(x: 600, y: 950)],
        sourceRoadID: sourceRoadID
    )
    let externalEdge = RoadSegment(
        id: UUID(),
        kind: .motorway,
        points: [RoadPoint(x: 1_000, y: 250), RoadPoint(x: 1_000, y: 950)],
        sourceRoadID: externalRoadID
    )
    let terrain = fixtureTerrain { point in
        (point.x >= 480 && point.x <= 700) ? 0.1 : 0.3
    }
    let configuration = testConfiguration(sampleSpacing: 20)

    let first = AutoStructurePlanner.plan(
        for: firstEdge,
        terrain: terrain,
        existingRoads: [siblingEdge, externalEdge],
        configuration: configuration
    )
    let rebuilt = AutoStructurePlanner.plan(
        for: rebuiltEdge,
        terrain: terrain,
        existingRoads: [siblingEdge, externalEdge],
        configuration: configuration
    )
    let firstBridge = try #require(
        first.candidates.first { $0.structure == .bridge }
    )
    let rebuiltBridge = try #require(
        rebuilt.candidates.first { $0.structure == .bridge }
    )

    #expect(first.sourceRoadID == sourceRoadID)
    #expect(first.sourceEdgeID == firstEdge.id)
    #expect(firstBridge.sourceRoadID == sourceRoadID)
    #expect(firstBridge.id == rebuiltBridge.id)
    #expect(first.crossingSuggestions.count == 1)
    #expect(first.crossingSuggestions.first?.existingRoadID == externalRoadID)
    #expect(first.crossingSuggestions.first?.existingEdgeID == externalEdge.id)
}

@Test func crossingUsesStoredPriorityAndEqualNonGroundLevelsRemainSameLayer() throws {
    let terrain = fixtureTerrain { _ in 0.3 }
    let source = RoadSegment(
        kind: .street,
        level: .elevated,
        points: [RoadPoint(x: 200, y: 600), RoadPoint(x: 1_400, y: 600)],
        priority: .motorway
    )
    let sameLevel = RoadSegment(
        kind: .street,
        level: .elevated,
        points: [RoadPoint(x: 800, y: 250), RoadPoint(x: 800, y: 950)],
        priority: .motorway
    )
    let demotedMotorway = RoadSegment(
        kind: .motorway,
        points: [RoadPoint(x: 200, y: 500), RoadPoint(x: 1_400, y: 500)],
        priority: .local
    )
    let localStreet = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 900, y: 250), RoadPoint(x: 900, y: 950)],
        priority: .local
    )

    let sameLevelPlan = AutoStructurePlanner.plan(
        for: source,
        terrain: terrain,
        existingRoads: [sameLevel],
        configuration: testConfiguration(sampleSpacing: 20)
    )
    let sameLevelCrossing = try #require(sameLevelPlan.crossingSuggestions.first)
    #expect(sameLevelCrossing.treatment == .elevated)
    #expect(!sameLevelCrossing.triggers.contains(.existingVerticalSeparation))
    #expect(sameLevelCrossing.sourcePriority == .motorway)

    let demotedPlan = AutoStructurePlanner.plan(
        for: demotedMotorway,
        terrain: terrain,
        existingRoads: [localStreet],
        configuration: testConfiguration(sampleSpacing: 20)
    )
    #expect(demotedPlan.crossingSuggestions.first?.treatment == .atGrade)
    #expect(demotedPlan.crossingSuggestions.first?.sourcePriority == .local)
}

@Test func acceptedTunnelUsesTheDirectGeometryMeasuredByItsEvidence() throws {
    let road = RoadSegment(
        kind: .arterial,
        points: [
            RoadPoint(x: 200, y: 600),
            RoadPoint(x: 800, y: 300),
            RoadPoint(x: 1_400, y: 600),
        ]
    )
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.tunnelLengthAdvantageThreshold = 0.01
    configuration.minimumTunnelLength = 40
    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: mountainTerrain(),
        existingRoads: [],
        configuration: configuration
    )
    let tunnel = try #require(
        plan.candidates.first { $0.structure == .tunnel }
    )
    let resolvedTunnel = try #require(
        plan.acceptingAllCandidates().first { $0.structure == .tunnel }
    )

    #expect(resolvedTunnel.points.count == 2)
    #expect(resolvedTunnel.points.first == tunnel.startPoint)
    #expect(resolvedTunnel.points.last == tunnel.endPoint)
    #expect(
        tunnel.evidence.metrics.surfaceLength + 1e-9
            >= tunnel.evidence.sampleRange.length
    )
    #expect(
        tunnel.evidence.metrics.directStructureLength
            < tunnel.evidence.metrics.surfaceLength
    )
}

@Test func bridgeSplitTunnelFragmentsAreRevalidatedIndividually() throws {
    let terrain = splitMountainTerrain()
    let road = horizontalRoad(kind: .arterial)
    var configuration = testConfiguration(sampleSpacing: 10)
    configuration.bridgeApproachLength = 0
    configuration.minimumBridgeLength = 20
    configuration.tunnelPortalSearchDistance = 40
    configuration.minimumTunnelLength = 80
    configuration.tunnelLengthAdvantageThreshold = 0.05

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )

    #expect(plan.candidates.contains { $0.structure == .bridge })
    #expect(!plan.candidates.contains { $0.structure == .tunnel })
}

@Test func expandingShortBridgeCannotBeUndoneByStaleTunnelRuns() throws {
    let terrain = splitMountainTerrain()
    let road = horizontalRoad(kind: .arterial)
    var configuration = testConfiguration(sampleSpacing: 10)
    configuration.bridgeApproachLength = 0
    configuration.minimumBridgeLength = 240
    configuration.tunnelPortalSearchDistance = 40
    configuration.minimumTunnelLength = 350
    configuration.tunnelLengthAdvantageThreshold = 0

    let plan = AutoStructurePlanner.plan(
        for: road,
        terrain: terrain,
        existingRoads: [],
        configuration: configuration
    )
    let bridge = try #require(
        plan.candidates.first { $0.structure == .bridge }
    )

    #expect(
        bridge.evidence.sampleRange.length + 1e-9
            >= configuration.minimumBridgeLength
    )
    #expect(!plan.candidates.contains { $0.structure == .tunnel })
    #expect(bridge.evidence.metrics.waterSampleCount > 0)
}

@Test func exactCrossingApproachStartDoesNotConsumePreviousInterval() throws {
    let source = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 200, y: 600), RoadPoint(x: 1_400, y: 600)],
        priority: .motorway
    )
    let existing = RoadSegment(
        kind: .street,
        points: [RoadPoint(x: 800, y: 250), RoadPoint(x: 800, y: 950)],
        priority: .motorway
    )
    var configuration = testConfiguration(sampleSpacing: 20)
    configuration.crossingApproachLength = 40
    configuration.minimumElevatedLength = 20

    let plan = AutoStructurePlanner.plan(
        for: source,
        terrain: fixtureTerrain { _ in 0.3 },
        existingRoads: [existing],
        configuration: configuration
    )
    let elevated = try #require(
        plan.candidates.first { $0.structure == .elevated }
    )

    #expect(abs(elevated.evidence.sampleRange.startDistance - 560) < 0.000_001)
    #expect(abs(elevated.evidence.sampleRange.endDistance - 640) < 0.000_001)
    #expect(elevated.startPoint == RoadPoint(x: 760, y: 600))
    #expect(elevated.endPoint == RoadPoint(x: 840, y: 600))
}

private func horizontalRoad(kind: RoadKind) -> RoadSegment {
    RoadSegment(
        kind: kind,
        points: [RoadPoint(x: 200, y: 600), RoadPoint(x: 1_400, y: 600)]
    )
}

private func mountainTerrain() -> TerrainLayout {
    fixtureTerrain { point in
        let along = max(0, 1 - abs(point.x - 800) / 250)
        let across = max(0.72, 1 - abs(point.y - 600) / 900)
        return 0.3 + along * across * 0.52
    }
}

private func splitMountainTerrain() -> TerrainLayout {
    fixtureTerrain { point in
        if point.x >= 780 && point.x <= 820 {
            return 0.1
        }
        let mountain = max(0, 1 - abs(point.x - 800) / 300)
        return 0.3 + mountain * 0.5
    }
}

private func testConfiguration(
    sampleSpacing: Double
) -> AutoStructurePlannerConfiguration {
    var configuration = AutoStructurePlannerConfiguration.standard
    configuration.sampleSpacing = sampleSpacing
    configuration.elevationScale = 400
    configuration.waterTolerance = 0.000_1
    configuration.steepGradeThreshold = 0.08
    configuration.mountainElevationThreshold = 0.42
    configuration.ridgeProminenceThreshold = 0.05
    configuration.crossSectionProbeDistance = 50
    configuration.tunnelLengthAdvantageThreshold = 0.04
    configuration.tunnelPortalSearchDistance = 20
    configuration.bridgeApproachLength = 10
    configuration.crossingApproachLength = 30
    configuration.minimumBridgeLength = 20
    configuration.minimumTunnelLength = 40
    configuration.minimumElevatedLength = 30
    configuration.maximumMergeableGroundGap = 15
    return configuration
}

private func fixtureTerrain(
    waterLevel: Double = 0.2,
    elevation: (RoadPoint) -> Double
) -> TerrainLayout {
    let width = 161
    let height = 121
    var elevations: [UInt16] = []
    elevations.reserveCapacity(width * height)
    for row in 0..<height {
        for column in 0..<width {
            let point = RoadPoint(
                x: Double(column) / Double(width - 1) * 1_600,
                y: Double(row) / Double(height - 1) * 1_200
            )
            let value = min(1, max(0, elevation(point)))
            elevations.append(UInt16((value * Double(UInt16.max)).rounded()))
        }
    }
    return TerrainLayout(
        seed: 1,
        shoreline: [],
        gridWidth: width,
        gridHeight: height,
        elevations: elevations,
        waterLevel: waterLevel
    )
}
