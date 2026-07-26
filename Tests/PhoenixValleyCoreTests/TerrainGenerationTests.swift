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
