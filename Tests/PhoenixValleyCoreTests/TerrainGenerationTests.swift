import Foundation
import Testing
@testable import PhoenixValleyCore

@Test func asynchronousTerrainGenerationMatchesSynchronousResult() async throws {
    let request = TerrainGenerationRequest(
        seed: 20260725,
        vertexCount: 80,
        gridWidth: 33,
        gridHeight: 25
    )
    let asynchronous = try await TerrainGenerator.generate(request: request) { _ in }
    let synchronous = TerrainGenerator.generate(
        seed: request.seed,
        vertexCount: request.vertexCount,
        gridWidth: request.gridWidth,
        gridHeight: request.gridHeight
    )

    #expect(asynchronous == synchronous)
}

@Test func terrainGenerationReportsMonotonicProgress() async throws {
    let recorder = TerrainProgressRecorder()
    let request = TerrainGenerationRequest(
        seed: 42,
        gridWidth: 33,
        gridHeight: 25
    )

    _ = try await TerrainGenerator.generate(request: request) {
        recorder.record($0)
    }

    let updates = recorder.updates
    #expect(updates.first?.phase == .shoreline)
    #expect(updates.first?.fractionCompleted == 0)
    #expect(updates.last?.phase == .finished)
    #expect(updates.last?.fractionCompleted == 1)
    #expect(
        zip(updates, updates.dropFirst()).allSatisfy {
            $0.fractionCompleted <= $1.fractionCompleted
        }
    )
}

@Test func terrainGenerationHonorsTaskCancellation() async {
    let request = TerrainGenerationRequest(
        seed: 7,
        gridWidth: 1_025,
        gridHeight: 769
    )
    let task = Task {
        try await TerrainGenerator.generate(request: request) { _ in }
    }
    task.cancel()

    do {
        _ = try await task.value
        Issue.record("Cancelled terrain generation unexpectedly completed")
    } catch is CancellationError {
        // Expected.
    } catch {
        Issue.record("Expected CancellationError, received \(error)")
    }
}

@Test func terrainCacheUsesRecentEntriesAndEvictsOldest() async {
    let cache = TerrainGenerationCache(capacity: 2)
    let first = TerrainGenerationRequest(seed: 1, gridWidth: 17, gridHeight: 13)
    let second = TerrainGenerationRequest(seed: 2, gridWidth: 17, gridHeight: 13)
    let third = TerrainGenerationRequest(seed: 3, gridWidth: 17, gridHeight: 13)

    await cache.insert(cachedTerrain(for: first), for: first)
    await cache.insert(cachedTerrain(for: second), for: second)
    _ = await cache.value(for: first)
    await cache.insert(cachedTerrain(for: third), for: third)

    let firstValue = await cache.value(for: first)
    let secondValue = await cache.value(for: second)
    let thirdValue = await cache.value(for: third)
    let count = await cache.count

    #expect(firstValue?.seed == first.seed)
    #expect(secondValue == nil)
    #expect(thirdValue?.seed == third.seed)
    #expect(count == 2)
}

@Test func terrainScenariosAreDeterministicAndVisiblyDistinct() {
    let seed: UInt64 = 20260726
    let terrains = TerrainScenario.allCases.map {
        TerrainGenerator.generate(
            seed: seed,
            vertexCount: 72,
            gridWidth: 33,
            gridHeight: 25,
            scenario: $0
        )
    }

    #expect(Set(terrains.map(\.scenario)) == Set(TerrainScenario.allCases))
    #expect(Set(terrains.map(\.elevations)).count >= 6)
    #expect(
        terrains.allSatisfy {
            $0 == TerrainGenerator.generate(
                seed: seed,
                vertexCount: 72,
                gridWidth: 33,
                gridHeight: 25,
                scenario: $0.scenario
            )
        }
    )

    let riverTerrain = terrains.first { $0.scenario == .riverAndLakes }!
    #expect(
        riverTerrain.elevations.contains {
            Double($0) / Double(UInt16.max) <= riverTerrain.waterLevel
        }
    )
}

@Test func riverAndLakeWaterStaysScaleAwareAndVariesBySeed() {
    let terrains = (100...105).map {
        TerrainGenerator.generate(
            seed: UInt64($0),
            gridWidth: 257,
            gridHeight: 193,
            scenario: .riverAndLakes
        )
    }

    let waterFractions = terrains.map { terrain in
        Double(terrain.elevations.filter {
            $0 > 0 && Double($0) / Double(UInt16.max) <= terrain.waterLevel
        }.count) / Double(terrain.elevations.count)
    }

    // A local river and one or two small lakes should occupy well under 5% of
    // this 1.92 km² map; the previous fixed geometry occupied roughly 10%.
    #expect(
        waterFractions.allSatisfy { $0 > 0.003 && $0 < 0.05 },
        "water fractions: \(waterFractions)"
    )
    #expect(Set(terrains.map(\.elevations)).count == terrains.count)
}

@Test func onlyOceanScenariosGenerateAnOuterCoastline() {
    let seed: UInt64 = 91_827
    let continent = TerrainGenerator.generate(seed: seed, scenario: .continent)
    let river = TerrainGenerator.generate(seed: seed, scenario: .riverAndLakes)
    let valley = TerrainGenerator.generate(seed: seed, scenario: .valley)
    let island = TerrainGenerator.generate(seed: seed, scenario: .island)
    let coastalCity = TerrainGenerator.generate(seed: seed, scenario: .coastalCity)

    let fullCanvasBoundary = [
        RoadPoint(x: 0, y: 0),
        RoadPoint(x: 1_600, y: 0),
        RoadPoint(x: 1_600, y: 1_200),
        RoadPoint(x: 0, y: 1_200),
    ]
    #expect(continent.shoreline == fullCanvasBoundary)
    #expect(river.shoreline == fullCanvasBoundary)
    #expect(valley.shoreline == fullCanvasBoundary)
    #expect(island.shoreline.count > 20)
    #expect(coastalCity.shoreline.count > 20)
    #expect(island.shoreline != coastalCity.shoreline)
}

@Test func drainageNetworkContainsMultipleConnectedHeadwaterBranches() {
    let terrain = TerrainGenerator.generate(
        seed: 2026072602,
        gridWidth: 257,
        gridHeight: 193,
        scenario: .riverAndLakes
    )
    let water = terrain.elevations.map {
        $0 > 0 && Double($0) / Double(UInt16.max) <= terrain.waterLevel
    }
    var branchLikeRows = 0
    for row in 1..<(terrain.gridHeight - 1) {
        var runs = 0
        var insideRun = false
        for column in 1..<(terrain.gridWidth - 1) {
            let isWater = water[row * terrain.gridWidth + column]
            if isWater, !insideRun {
                runs += 1
            }
            insideRun = isWater
        }
        if runs >= 2 {
            branchLikeRows += 1
        }
    }

    #expect(branchLikeRows >= 3)
}

private final class TerrainProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedUpdates: [TerrainGenerationProgress] = []

    var updates: [TerrainGenerationProgress] {
        lock.withLock { storedUpdates }
    }

    func record(_ progress: TerrainGenerationProgress) {
        lock.withLock {
            storedUpdates.append(progress)
        }
    }
}

private func cachedTerrain(for request: TerrainGenerationRequest) -> TerrainLayout {
    TerrainLayout(
        seed: request.seed,
        shoreline: [
            RoadPoint(x: 0, y: 0),
            RoadPoint(x: 1, y: 0),
            RoadPoint(x: 0, y: 1),
        ],
        gridWidth: request.gridWidth,
        gridHeight: request.gridHeight,
        elevations: Array(
            repeating: UInt16.max / 2,
            count: request.gridWidth * request.gridHeight
        )
    )
}
