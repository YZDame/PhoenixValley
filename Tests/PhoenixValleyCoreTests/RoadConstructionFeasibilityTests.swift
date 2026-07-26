import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func gentleAndLimitGradeGroundRoadsAreFeasible() {
    let gentleTerrain = feasibilityTerrain { point in
        120 + point.x * 0.04
    }
    let limitTerrain = feasibilityTerrain { point in
        120 + point.x * 0.08
    }
    let road = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!,
        kind: .arterial,
        points: [
            RoadPoint(x: 100, y: 600),
            RoadPoint(x: 500, y: 600),
        ]
    )

    let gentle = RoadConstructionFeasibilityAnalyzer.evaluate(
        road: road,
        terrain: gentleTerrain,
        mapScale: .standard
    )
    let atLimit = RoadConstructionFeasibilityAnalyzer.evaluate(
        road: road,
        terrain: limitTerrain,
        mapScale: .standard
    )

    #expect(gentle.strategy == .groundLocalTerrainProfile)
    #expect(gentle.maximumPermittedGrade == 0.08)
    #expect(gentle.sampleCount == 81)
    #expect(gentle.isFeasible)
    #expect(atLimit.isFeasible)
    #expect(atLimit.issues.isEmpty)
}

@Test func steepLocalGradeMergesIntoCurvedCenterlineInterval() throws {
    let terrain = feasibilityTerrain(gridWidth: 161, gridHeight: 121) { point in
        120 + 0.10 * ((point.x - 100) + (point.y - 100))
    }
    let road = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!,
        kind: .arterial,
        points: [
            RoadPoint(x: 100, y: 100),
            RoadPoint(x: 300, y: 100),
            RoadPoint(x: 300, y: 300),
        ]
    )

    let report = RoadConstructionFeasibilityAnalyzer.evaluate(
        road: road,
        terrain: terrain,
        mapScale: .standard
    )
    let issue = try #require(
        report.issues.first { $0.kind == .localGradeAboveLimit }
    )

    #expect(!report.isFeasible)
    #expect(report.issues.filter { $0.kind == .localGradeAboveLimit }.count == 1)
    #expect(issue.measuredValue > 0.09)
    #expect(issue.limitValue == 0.08)
    #expect(issue.endChainageMeters - issue.startChainageMeters > 300)
    #expect(issue.centerline.count >= 3)
    #expect(issue.centerline.contains(RoadPoint(x: 300, y: 100)))
    #expect(issue.startPoint == issue.centerline.first)
    #expect(issue.endPoint == issue.centerline.last)
}

@Test func shortTerrainSpikeIsRemovedByPhysicalMedianWindow() {
    let terrain = feasibilityTerrain(gridWidth: 1_601, gridHeight: 2) { point in
        if abs(point.x - 150) <= 2 {
            return 180
        }
        return 120
    }
    let road = RoadSegment(
        kind: .arterial,
        points: [
            RoadPoint(x: 0, y: 600),
            RoadPoint(x: 300, y: 600),
        ]
    )

    let report = RoadConstructionFeasibilityAnalyzer.evaluate(
        road: road,
        terrain: terrain,
        mapScale: .standard
    )

    #expect(report.issues.allSatisfy { $0.kind != .localGradeAboveLimit })
}

@Test func groundRoadWaterIntervalsAreReportedInMetres() throws {
    let terrain = feasibilityTerrain(
        gridWidth: 1_601,
        gridHeight: 2,
        waterLevel: 0.2
    ) { point in
        point.x >= 80 && point.x <= 160 ? 42 : 126
    }
    let roadID = UUID(uuidString: "10000000-0000-0000-0000-000000000003")!
    let sourceID = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
    let road = RoadSegment(
        id: roadID,
        kind: .street,
        points: [
            RoadPoint(x: 0, y: 600),
            RoadPoint(x: 240, y: 600),
        ],
        sourceRoadID: sourceID
    )

    let report = RoadConstructionFeasibilityAnalyzer.evaluate(
        road: road,
        terrain: terrain,
        mapScale: .standard
    )
    let issue = try #require(
        report.issues.first { $0.kind == .groundRoadInWater }
    )

    #expect(issue.roadID == roadID)
    #expect(issue.sourceRoadID == sourceID)
    #expect(issue.roadKind == .street)
    #expect(issue.structure == .ground)
    #expect(issue.unit == .meters)
    #expect(issue.comparison == .greaterThan)
    #expect(issue.measuredValue < issue.limitValue)
    #expect(issue.startChainageMeters <= 85)
    #expect(issue.endChainageMeters >= 155)
    #expect(issue.centerline.count >= 2)
}

@Test func bridgeAndTunnelSkipDuplicateChecksWhileElevatedUsesAxis() {
    let terrain = feasibilityTerrain { point in
        120 + point.x * 0.10
    }
    let sourceID = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
    let points = [
        RoadPoint(x: 100, y: 600),
        RoadPoint(x: 300, y: 600),
    ]
    let ground = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000004")!,
        kind: .arterial,
        structure: .ground,
        points: points,
        sourceRoadID: sourceID
    )
    let bridge = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000005")!,
        kind: .arterial,
        structure: .bridge,
        points: points,
        sourceRoadID: sourceID
    )
    let tunnel = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000006")!,
        kind: .arterial,
        structure: .tunnel,
        points: points,
        sourceRoadID: sourceID
    )
    let elevated = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000007")!,
        kind: .arterial,
        structure: .elevated,
        points: points,
        sourceRoadID: sourceID
    )

    let report = RoadConstructionFeasibilityAnalyzer.evaluate(
        roads: [ground, bridge, tunnel, elevated],
        terrain: terrain,
        mapScale: .standard
    )
    let bridgeReport = report.report(forRoadID: bridge.id)
    let tunnelReport = report.report(forRoadID: tunnel.id)
    let elevatedReport = report.report(forRoadID: elevated.id)

    #expect(report.report(forRoadID: ground.id)?.issues.contains {
        $0.kind == .localGradeAboveLimit
    } == true)
    #expect(bridgeReport?.strategy == .handledByStructureEngineering)
    #expect(bridgeReport?.issues.isEmpty == true)
    #expect(tunnelReport?.strategy == .handledByStructureEngineering)
    #expect(tunnelReport?.issues.isEmpty == true)
    #expect(
        elevatedReport?.strategy == .elevatedStraightAxisBetweenEndpoints
    )
    #expect(elevatedReport?.issues.contains {
        $0.kind == .elevatedAxisGradeAboveLimit
    } == true)
}

@Test func issueIdentityAndCodableRoundTripAreStable() throws {
    let terrain = feasibilityTerrain { point in
        120 + point.x * 0.10
    }
    let road = RoadSegment(
        id: UUID(uuidString: "10000000-0000-0000-0000-000000000008")!,
        kind: .motorway,
        points: [
            RoadPoint(x: 100, y: 600),
            RoadPoint(x: 500, y: 600),
        ],
        sourceRoadID: UUID(
            uuidString: "20000000-0000-0000-0000-000000000008"
        )!
    )

    let first = RoadConstructionFeasibilityAnalyzer.evaluate(
        roads: [road],
        terrain: terrain,
        mapScale: .standard
    )
    let second = RoadConstructionFeasibilityAnalyzer.evaluate(
        roads: [road],
        terrain: terrain,
        mapScale: .standard
    )
    let firstIssue = try #require(first.issues.first)
    let secondIssue = try #require(second.issues.first)
    let encoded = try JSONEncoder().encode(first)
    let decoded = try JSONDecoder().decode(
        RoadConstructionFeasibilityReport.self,
        from: encoded
    )

    #expect(firstIssue.id == secondIssue.id)
    #expect(first == second)
    #expect(decoded == first)
    #expect(
        try JSONDecoder().decode(
            RoadConstructionFeasibilityConfiguration.self,
            from: JSONEncoder().encode(
                RoadConstructionFeasibilityConfiguration.standard
            )
        ) == .standard
    )
}

@Test func physicalResultsAreEquivalentAtEverySupportedMapScale() throws {
    let roadID = UUID(uuidString: "10000000-0000-0000-0000-000000000009")!
    let sourceID = UUID(uuidString: "20000000-0000-0000-0000-000000000009")!
    var issues: [RoadConstructionIssue] = []

    for metersPerPoint in [0.5, 1, 2, 5] {
        let scale = MapScale(metersPerPoint: metersPerPoint)
        let terrain = feasibilityTerrain(
            metersPerPoint: metersPerPoint
        ) { point in
            120 + point.x * 0.10
        }
        let road = RoadSegment(
            id: roadID,
            kind: .arterial,
            points: [
                RoadPoint(x: 20 / metersPerPoint, y: 600),
                RoadPoint(x: 420 / metersPerPoint, y: 600),
            ],
            sourceRoadID: sourceID
        )
        let report = RoadConstructionFeasibilityAnalyzer.evaluate(
            road: road,
            terrain: terrain,
            mapScale: scale
        )
        issues.append(
            try #require(
                report.issues.first { $0.kind == .localGradeAboveLimit }
            )
        )
    }

    #expect(issues.allSatisfy { abs($0.measuredValue - 0.10) < 0.001 })
    #expect(Set(issues.map(\.id)).count == 1)
    #expect(
        issues.dropFirst().allSatisfy {
            abs($0.startChainageMeters - issues[0].startChainageMeters) < 1e-9
                && abs(
                    $0.endChainageMeters - issues[0].endChainageMeters
                ) < 1e-9
        }
    )
}

private func feasibilityTerrain(
    metersPerPoint: Double = 1,
    elevationScaleMeters: Double = 420,
    gridWidth: Int = 1_601,
    gridHeight: Int = 2,
    waterLevel: Double = 0.2,
    elevationMeters: (RoadPoint) -> Double
) -> TerrainLayout {
    var values: [UInt16] = []
    values.reserveCapacity(gridWidth * gridHeight)
    for row in 0..<gridHeight {
        for column in 0..<gridWidth {
            let canvasPoint = RoadPoint(
                x: Double(column) / Double(gridWidth - 1) * 1_600,
                y: Double(row) / Double(gridHeight - 1) * 1_200
            )
            let physicalPoint = RoadPoint(
                x: canvasPoint.x * metersPerPoint,
                y: canvasPoint.y * metersPerPoint
            )
            let normalized = min(
                1,
                max(0, elevationMeters(physicalPoint) / elevationScaleMeters)
            )
            values.append(UInt16((normalized * Double(UInt16.max)).rounded()))
        }
    }
    return TerrainLayout(
        seed: 99,
        shoreline: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 1_600, y: 0),
            RoadPoint(x: 1_600, y: 1_200),
            RoadPoint(x: 0, y: 1_200),
        ],
        gridWidth: gridWidth,
        gridHeight: gridHeight,
        elevations: values,
        waterLevel: waterLevel
    )
}
