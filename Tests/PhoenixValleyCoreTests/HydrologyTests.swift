import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func riverScenarioBuildsSemanticHydrologyAndWatersheds() throws {
    let terrain = TerrainGenerator.generate(
        seed: 20260808,
        gridWidth: 257,
        gridHeight: 193,
        scenario: .riverAndLakes
    )
    let hydrology = terrain.hydrology

    #expect(hydrology.hasData)
    #expect(hydrology.cellCount(for: .river) > 0)
    #expect(hydrology.cellCount(for: .lake) > 0)
    #expect(hydrology.cellCount(for: .wetland) > 0)
    #expect(hydrology.outlets.count == 4)
    #expect(Set(hydrology.watershedIDs).subtracting([0]) == Set(1...4))
    #expect(hydrology.outlets.allSatisfy { $0.drainageCellCount > 0 })

    let decoded = try JSONDecoder().decode(
        TerrainLayout.self,
        from: JSONEncoder().encode(terrain)
    )
    #expect(decoded.hydrology == hydrology)
}

@Test func oceanAndDryScenariosReceiveCompatibleHydrologyDefaults() {
    let island = TerrainGenerator.generate(
        seed: 42,
        gridWidth: 65,
        gridHeight: 49,
        scenario: .island
    )
    let continent = TerrainGenerator.generate(
        seed: 42,
        gridWidth: 65,
        gridHeight: 49,
        scenario: .continent
    )

    #expect(island.hydrology.hasData)
    #expect(island.hydrology.cellCount(for: .ocean) > 0)
    #expect(continent.hydrology.hasData)
    #expect(continent.hydrology.cellCount(for: .ocean) == 0)
    #expect(!continent.hydrology.outlets.isEmpty)
    #expect(continent.hydrology.cellCount(for: .river) > 0)
}

@Test func hydrologyPointQueriesClampToCanvasAndReturnWatershed() {
    let terrain = TerrainGenerator.generate(
        seed: 8128,
        gridWidth: 65,
        gridHeight: 49,
        scenario: .riverAndLakes
    )
    let hydrology = terrain.hydrology

    #expect(hydrology.surface(at: RoadPoint(x: -10, y: -10)) != .ocean)
    #expect(hydrology.watershedID(at: RoadPoint(x: 800, y: 600)) != nil)
    #expect(hydrology.watershedID(at: RoadPoint(x: 2_000, y: 2_000)) != nil)
}

@Test func allScenariosHaveWaterAndDistributedRelief() {
    for scenario in TerrainScenario.allCases {
        let terrain = TerrainGenerator.generate(seed: 425, gridWidth: 129, gridHeight: 97, scenario: scenario)
        #expect(terrain.hydrology.cellCount(for: .river) > 0, "Missing rivers: \(scenario)")
        #expect(terrain.hydrology.cellCount(for: .lake) > 0, "Missing lakes: \(scenario)")
        #expect(terrain.elevations.max()! - terrain.elevations.min()! > 8000)
    }
}
