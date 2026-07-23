import Testing
import Foundation
@testable import RoadSketchCore

@Test func removesDenseDuplicateSamples() {
    let points = [
        RoadPoint(x: 0, y: 0),
        RoadPoint(x: 0.2, y: 0.1),
        RoadPoint(x: 5, y: 0),
    ]

    let result = StrokeProcessor.removeNearDuplicates(points, minimumDistance: 1)

    #expect(result == [RoadPoint(x: 0, y: 0), RoadPoint(x: 5, y: 0)])
}

@Test func simplifiesAlmostStraightStroke() {
    let points = (0...20).map { index in
        RoadPoint(x: Double(index) * 10, y: index.isMultiple(of: 2) ? 0.8 : -0.8)
    }

    let result = StrokeProcessor.process(
        points,
        existingRoads: [],
        configuration: .init(
            minimumSampleDistance: 0,
            smoothingPasses: 1,
            simplificationTolerance: 2,
            endpointSnapRadius: 0,
            angleSnapTolerance: .pi / 36
        )
    )

    #expect(result.count == 2)
    #expect(abs(result[1].y - result[0].y) < 0.0001)
}

@Test func snapsNewRoadToExistingEndpoint() {
    let existing = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 100, y: 100), RoadPoint(x: 200, y: 100)]
    )
    let result = StrokeProcessor.process(
        [RoadPoint(x: 97, y: 97), RoadPoint(x: 120, y: 160)],
        existingRoads: [existing],
        configuration: .init(
            minimumSampleDistance: 0,
            smoothingPasses: 0,
            simplificationTolerance: 0,
            endpointSnapRadius: 8,
            angleSnapTolerance: 0
        )
    )

    #expect(result.first == RoadPoint(x: 100, y: 100))
}

@Test func snapsNewRoadToMiddleOfExistingSegment() {
    let existing = RoadSegment(
        kind: .arterial,
        points: [RoadPoint(x: 100, y: 100), RoadPoint(x: 200, y: 100)]
    )
    let result = StrokeProcessor.process(
        [RoadPoint(x: 151, y: 104), RoadPoint(x: 150, y: 180)],
        existingRoads: [existing],
        configuration: .init(
            minimumSampleDistance: 0,
            smoothingPasses: 0,
            simplificationTolerance: 0,
            endpointSnapRadius: 8,
            angleSnapTolerance: 0
        )
    )

    #expect(result.first == RoadPoint(x: 151, y: 100))
}

@Test func terrainGenerationIsDeterministic() {
    let first = TerrainGenerator.generate(seed: 42)
    let second = TerrainGenerator.generate(seed: 42)
    let other = TerrainGenerator.generate(seed: 43)

    #expect(first == second)
    #expect(first != other)
    #expect(first.hasElevationData)
    #expect(first.elevations.count == first.gridWidth * first.gridHeight)
    #expect(first.shoreline.count >= 72)

    let normalized = first.elevations.map { Double($0) / Double(UInt16.max) }
    let land = normalized.filter { $0 > first.waterLevel }
    #expect(land.contains(where: { $0 > 0.68 }))
    #expect(land.contains(where: { $0 >= 0.23 && $0 < 0.36 }))
    #expect(land.filter { $0 < 0.4 }.count > land.count / 3)
}

@Test func differentTerrainSeedsProduceClearlyDifferentCoastlines() {
    let first = TerrainGenerator.generate(seed: 42)
    let second = TerrainGenerator.generate(seed: 43)

    func bounds(of terrain: TerrainLayout) -> (width: Double, height: Double, centerX: Double, centerY: Double) {
        let xs = terrain.shoreline.map(\.x)
        let ys = terrain.shoreline.map(\.y)
        let minX = xs.min() ?? 0
        let maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0
        let maxY = ys.max() ?? 0
        return (maxX - minX, maxY - minY, (minX + maxX) / 2, (minY + maxY) / 2)
    }

    let a = bounds(of: first)
    let b = bounds(of: second)
    let visibleDifference = abs(a.width - b.width) + abs(a.height - b.height)
        + abs(a.centerX - b.centerX) + abs(a.centerY - b.centerY)

    #expect(visibleDifference > 100)
}

@Test func upgradesLegacyTerrainWithElevationData() {
    let legacy = TerrainLayout(
        seed: 42,
        shoreline: TerrainGenerator.generate(seed: 42).shoreline
    )

    let upgraded = TerrainGenerator.upgrading(legacy)

    #expect(upgraded.hasElevationData)
    #expect(upgraded.seed == legacy.seed)
}

@Test func projectGroupMembershipSurvivesPersistenceRoundTrip() throws {
    let groupID = UUID()
    let project = RoadProject(
        name: "分组测试",
        terrain: TerrainLayout(seed: 7, shoreline: []),
        groupID: groupID
    )

    let encoded = try JSONEncoder().encode(project)
    let decoded = try JSONDecoder().decode(RoadProject.self, from: encoded)

    #expect(decoded.groupID == groupID)
    #expect(decoded.name == project.name)
}
