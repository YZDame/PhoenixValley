import Foundation
import PhoenixValleyCore

@main
enum PhoenixValleyCoreSmokeTests {
    static func main() {
        testDenseSamples()
        testStraightening()
        testEndpointSnapping()
        testSegmentSnapping()
        testTerrainDeterminism()
        print("PhoenixValleyCore smoke tests passed")
    }

    private static func testDenseSamples() {
        let result = StrokeProcessor.removeNearDuplicates(
            [
                RoadPoint(x: 0, y: 0),
                RoadPoint(x: 0.2, y: 0.1),
                RoadPoint(x: 5, y: 0),
            ],
            minimumDistance: 1
        )
        precondition(result == [RoadPoint(x: 0, y: 0), RoadPoint(x: 5, y: 0)])
    }

    private static func testStraightening() {
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
        precondition(result.count == 2)
        precondition(abs(result[1].y - result[0].y) < 0.0001)
    }

    private static func testEndpointSnapping() {
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
        precondition(result.first == RoadPoint(x: 100, y: 100))
    }

    private static func testTerrainDeterminism() {
        let terrain = TerrainGenerator.generate(seed: 42)
        precondition(terrain == TerrainGenerator.generate(seed: 42))
        precondition(terrain != TerrainGenerator.generate(seed: 43))
        precondition(terrain.hasElevationData)
        precondition(terrain.elevations.count == terrain.gridWidth * terrain.gridHeight)
        precondition(terrain.normalizedElevation(at: RoadPoint(x: 800, y: 600)) > 0.45)
    }

    private static func testSegmentSnapping() {
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
        precondition(result.first == RoadPoint(x: 151, y: 100))
    }
}
