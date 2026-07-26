import Foundation

public struct TerrainGenerationRequest: Hashable, Sendable {
    public var seed: UInt64
    public var vertexCount: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var generationVersion: Int

    public init(
        seed: UInt64,
        vertexCount: Int = 96,
        gridWidth: Int = 129,
        gridHeight: Int = 97
    ) {
        self.seed = seed
        self.vertexCount = max(72, vertexCount)
        self.gridWidth = max(17, gridWidth)
        self.gridHeight = max(13, gridHeight)
        generationVersion = TerrainLayout.currentGenerationVersion
    }
}

public enum TerrainGenerationPhase: String, Hashable, Sendable {
    case shoreline
    case landforms
    case elevationGrid
    case finished
}

public struct TerrainGenerationProgress: Hashable, Sendable {
    public var phase: TerrainGenerationPhase
    public var fractionCompleted: Double

    public init(phase: TerrainGenerationPhase, fractionCompleted: Double) {
        self.phase = phase
        self.fractionCompleted = min(1, max(0, fractionCompleted))
    }
}

public actor TerrainGenerationCache {
    public static let shared = TerrainGenerationCache()

    private let capacity: Int
    private var entries: [TerrainGenerationRequest: TerrainLayout] = [:]
    private var recency: [TerrainGenerationRequest] = []

    public init(capacity: Int = 8) {
        self.capacity = max(1, capacity)
    }

    public func value(for request: TerrainGenerationRequest) -> TerrainLayout? {
        guard let terrain = entries[request] else { return nil }
        recency.removeAll { $0 == request }
        recency.append(request)
        return terrain
    }

    public func insert(_ terrain: TerrainLayout, for request: TerrainGenerationRequest) {
        entries[request] = terrain
        recency.removeAll { $0 == request }
        recency.append(request)

        while recency.count > capacity {
            let oldest = recency.removeFirst()
            entries.removeValue(forKey: oldest)
        }
    }

    public func removeAll() {
        entries.removeAll()
        recency.removeAll()
    }

    public var count: Int {
        entries.count
    }
}

public enum TerrainGenerator {
    private struct Ridge {
        let points: [RoadPoint]
        let width: Double
        let height: Double
    }

    private struct Basin {
        let center: RoadPoint
        let radius: Double
        let depth: Double
    }

    public static func generate(
        seed: UInt64,
        vertexCount: Int = 96,
        gridWidth: Int = 129,
        gridHeight: Int = 97
    ) -> TerrainLayout {
        let request = TerrainGenerationRequest(
            seed: seed,
            vertexCount: vertexCount,
            gridWidth: gridWidth,
            gridHeight: gridHeight
        )
        do {
            return try generate(
                request: request,
                progress: nil,
                cancellationCheck: nil
            )
        } catch {
            preconditionFailure("Synchronous terrain generation unexpectedly failed: \(error)")
        }
    }

    public static func generate(
        request: TerrainGenerationRequest,
        progress: @escaping @Sendable (TerrainGenerationProgress) -> Void
    ) async throws -> TerrainLayout {
        let worker = Task.detached(priority: .userInitiated) {
            try generate(
                request: request,
                progress: progress,
                cancellationCheck: {
                    try Task.checkCancellation()
                }
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private static func generate(
        request: TerrainGenerationRequest,
        progress: (@Sendable (TerrainGenerationProgress) -> Void)?,
        cancellationCheck: (@Sendable () throws -> Void)?
    ) throws -> TerrainLayout {
        try cancellationCheck?()
        progress?(TerrainGenerationProgress(phase: .shoreline, fractionCompleted: 0))

        let seed = request.seed
        var generator = SeededGenerator(seed: seed)
        let center = RoadPoint(
            x: 735 + generator.nextUnit() * 130,
            y: 545 + generator.nextUnit() * 110
        )
        let horizontalBase = 500 + generator.nextUnit() * 175
        let verticalBase = 350 + generator.nextUnit() * 135
        let rotation = (generator.nextUnit() - 0.5) * 0.5
        let shoreline = makeShoreline(
            center: center,
            horizontalBase: horizontalBase,
            verticalBase: verticalBase,
            rotation: rotation,
            vertexCount: request.vertexCount,
            generator: &generator
        )
        try cancellationCheck?()
        progress?(TerrainGenerationProgress(phase: .landforms, fractionCompleted: 0.1))

        let primaryDirection = generator.nextUnit() * Double.pi
        var ridges = [makeRidge(
            center: offset(
                center,
                direction: primaryDirection + .pi / 2,
                distance: (generator.nextUnit() - 0.5) * verticalBase * 0.45
            ),
            direction: primaryDirection,
            length: horizontalBase * (1.05 + generator.nextUnit() * 0.35),
            bend: (generator.nextUnit() - 0.5) * 260,
            width: 78 + generator.nextUnit() * 72,
            height: 0.34 + generator.nextUnit() * 0.18
        )]

        if generator.nextUnit() > 0.28 {
            let branchDirection = primaryDirection
                + (generator.nextUnit() > 0.5 ? 1 : -1) * (0.55 + generator.nextUnit() * 0.45)
            ridges.append(
                makeRidge(
                    center: offset(
                        center,
                        direction: primaryDirection,
                        distance: (generator.nextUnit() - 0.35) * horizontalBase * 0.45
                    ),
                    direction: branchDirection,
                    length: horizontalBase * (0.55 + generator.nextUnit() * 0.35),
                    bend: (generator.nextUnit() - 0.5) * 180,
                    width: 60 + generator.nextUnit() * 58,
                    height: 0.22 + generator.nextUnit() * 0.16
                )
            )
        }

        var valleys: [Ridge] = []
        let valleyCount = 2 + Int(generator.next() % 3)
        for index in 0..<valleyCount {
            let side = index.isMultiple(of: 2) ? 1.0 : -1.0
            let direction = primaryDirection + side * (.pi / 2 + (generator.nextUnit() - 0.5) * 0.55)
            valleys.append(
                makeRidge(
                    center: offset(
                        center,
                        direction: primaryDirection,
                        distance: (generator.nextUnit() - 0.5) * horizontalBase * 0.55
                    ),
                    direction: direction,
                    length: verticalBase * (0.75 + generator.nextUnit() * 0.55),
                    bend: (generator.nextUnit() - 0.5) * 140,
                    width: 34 + generator.nextUnit() * 34,
                    height: 0.055 + generator.nextUnit() * 0.045
                )
            )
        }

        var basins: [Basin] = []
        for _ in 0..<(1 + Int(generator.next() % 3)) {
            basins.append(
                Basin(
                    center: RoadPoint(
                        x: center.x + (generator.nextUnit() - 0.5) * horizontalBase * 0.9,
                        y: center.y + (generator.nextUnit() - 0.5) * verticalBase * 0.9
                    ),
                    radius: 90 + generator.nextUnit() * 130,
                    depth: 0.025 + generator.nextUnit() * 0.04
                )
            )
        }

        try cancellationCheck?()
        progress?(TerrainGenerationProgress(phase: .elevationGrid, fractionCompleted: 0.2))

        let width = request.gridWidth
        let height = request.gridHeight
        var elevations: [UInt16] = []
        elevations.reserveCapacity(width * height)

        for row in 0..<height {
            try cancellationCheck?()
            for column in 0..<width {
                let point = RoadPoint(
                    x: Double(column) / Double(width - 1) * 1600,
                    y: Double(row) / Double(height - 1) * 1200
                )
                guard contains(point, in: shoreline) else {
                    elevations.append(0)
                    continue
                }

                let coastDistance = distance(from: point, to: shoreline, closed: true)
                var elevation = 0.215 + min(1, coastDistance / 230) * 0.095

                for (index, ridge) in ridges.enumerated() {
                    let ridgeDistance = distance(from: point, to: ridge.points, closed: false)
                    let profile = exp(-pow(ridgeDistance / ridge.width, 2) * 0.5)
                    let brokenCrest = 0.72 + 0.28 * ridgedNoise(
                        x: point.x,
                        y: point.y,
                        frequency: 0.006,
                        seed: seed &+ (UInt64(index + 11) &* 0x9E3779B97F4A7C15)
                    )
                    elevation += profile * ridge.height * brokenCrest
                }

                for valley in valleys {
                    let valleyDistance = distance(from: point, to: valley.points, closed: false)
                    elevation -= exp(-pow(valleyDistance / valley.width, 2) * 0.5) * valley.height
                }

                for basin in basins {
                    let basinDistance = hypot(point.x - basin.center.x, point.y - basin.center.y)
                    elevation -= exp(-pow(basinDistance / basin.radius, 2) * 0.5) * basin.depth
                }

                let broadRelief = fractalNoise(
                    x: point.x,
                    y: point.y,
                    frequency: 0.0018,
                    octaves: 4,
                    seed: seed &+ 0xA0761D6478BD642F
                )
                let localRelief = ridgedNoise(
                    x: point.x,
                    y: point.y,
                    frequency: 0.009,
                    seed: seed &+ 0xE7037ED1A0B428DB
                )
                elevation += (broadRelief - 0.5) * 0.12
                elevation += (localRelief - 0.5) * 0.045

                // Keep a narrow, low coastal shelf while preserving inland plains.
                let coastalCeiling = 0.27 + min(1, coastDistance / 120) * 0.73
                elevation = min(elevation, coastalCeiling)
                elevation = min(0.96, max(0.205, elevation))
                elevations.append(UInt16((elevation * Double(UInt16.max)).rounded()))
            }

            if row.isMultiple(of: 2) || row == height - 1 {
                let fraction = 0.2 + 0.8 * Double(row + 1) / Double(height)
                progress?(
                    TerrainGenerationProgress(
                        phase: row == height - 1 ? .finished : .elevationGrid,
                        fractionCompleted: fraction
                    )
                )
            }
        }

        return TerrainLayout(
            seed: seed,
            shoreline: shoreline,
            generationVersion: TerrainLayout.currentGenerationVersion,
            gridWidth: width,
            gridHeight: height,
            elevations: elevations,
            waterLevel: 0.2
        )
    }

    public static func upgrading(_ terrain: TerrainLayout) -> TerrainLayout {
        guard !terrain.hasElevationData
            || terrain.generationVersion < TerrainLayout.currentGenerationVersion
        else { return terrain }
        return generate(seed: terrain.seed)
    }

    private static func makeShoreline(
        center: RoadPoint,
        horizontalBase: Double,
        verticalBase: Double,
        rotation: Double,
        vertexCount: Int,
        generator: inout SeededGenerator
    ) -> [RoadPoint] {
        var harmonics: [(frequency: Int, amplitude: Double, phase: Double)] = []
        for frequency in [2, 3, 5, 7, 11] {
            let falloff = 1 / pow(Double(frequency), 0.78)
            harmonics.append(
                (
                    frequency,
                    (0.055 + generator.nextUnit() * 0.11) * falloff * 2.2,
                    generator.nextUnit() * 2 * .pi
                )
            )
        }

        var coastalFeatures: [(angle: Double, width: Double, strength: Double)] = []
        for _ in 0..<(2 + Int(generator.next() % 4)) {
            coastalFeatures.append(
                (
                    generator.nextUnit() * 2 * .pi,
                    0.12 + generator.nextUnit() * 0.32,
                    (generator.nextUnit() - 0.58) * 0.24
                )
            )
        }

        return (0..<vertexCount).map { index in
            let angle = Double(index) / Double(vertexCount) * 2 * .pi
            var radius = 1.0
            for harmonic in harmonics {
                radius += sin(Double(harmonic.frequency) * angle + harmonic.phase) * harmonic.amplitude
            }
            for feature in coastalFeatures {
                let delta = circularDistance(angle, feature.angle)
                radius += exp(-pow(delta / feature.width, 2) * 0.5) * feature.strength
            }
            radius = min(1.22, max(0.72, radius))

            let localX = cos(angle) * horizontalBase * radius
            let localY = sin(angle) * verticalBase * radius
            return RoadPoint(
                x: center.x + localX * cos(rotation) - localY * sin(rotation),
                y: center.y + localX * sin(rotation) + localY * cos(rotation)
            )
        }
    }

    private static func makeRidge(
        center: RoadPoint,
        direction: Double,
        length: Double,
        bend: Double,
        width: Double,
        height: Double
    ) -> Ridge {
        let directionX = cos(direction)
        let directionY = sin(direction)
        let normalX = -directionY
        let normalY = directionX
        let start = RoadPoint(
            x: center.x - directionX * length / 2,
            y: center.y - directionY * length / 2
        )
        let control = RoadPoint(
            x: center.x + normalX * bend,
            y: center.y + normalY * bend
        )
        let end = RoadPoint(
            x: center.x + directionX * length / 2,
            y: center.y + directionY * length / 2
        )
        let points = (0...24).map { index in
            let t = Double(index) / 24
            let oneMinusT = 1 - t
            return RoadPoint(
                x: oneMinusT * oneMinusT * start.x + 2 * oneMinusT * t * control.x + t * t * end.x,
                y: oneMinusT * oneMinusT * start.y + 2 * oneMinusT * t * control.y + t * t * end.y
            )
        }
        return Ridge(points: points, width: width, height: height)
    }

    private static func offset(_ point: RoadPoint, direction: Double, distance: Double) -> RoadPoint {
        RoadPoint(
            x: point.x + cos(direction) * distance,
            y: point.y + sin(direction) * distance
        )
    }

    private static func circularDistance(_ first: Double, _ second: Double) -> Double {
        let difference = abs(first - second).truncatingRemainder(dividingBy: 2 * .pi)
        return min(difference, 2 * .pi - difference)
    }

    private static func contains(_ point: RoadPoint, in polygon: [RoadPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var isInside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            let crosses = (current.y > point.y) != (previous.y > point.y)
                && point.x < (previous.x - current.x) * (point.y - current.y)
                    / (previous.y - current.y) + current.x
            if crosses { isInside.toggle() }
            previous = current
        }
        return isInside
    }

    private static func distance(from point: RoadPoint, to polyline: [RoadPoint], closed: Bool) -> Double {
        guard polyline.count >= 2 else { return .infinity }
        let segmentCount = closed ? polyline.count : polyline.count - 1
        var closest = Double.infinity
        for index in 0..<segmentCount {
            let start = polyline[index]
            let end = polyline[(index + 1) % polyline.count]
            closest = min(closest, distance(from: point, toSegmentFrom: start, to: end))
        }
        return closest
    }

    private static func distance(from point: RoadPoint, toSegmentFrom start: RoadPoint, to end: RoadPoint) -> Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared
        let amount = min(1, max(0, projection))
        return hypot(
            point.x - (start.x + deltaX * amount),
            point.y - (start.y + deltaY * amount)
        )
    }

    private static func fractalNoise(
        x: Double,
        y: Double,
        frequency: Double,
        octaves: Int,
        seed: UInt64
    ) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var totalAmplitude = 0.0
        var currentFrequency = frequency
        for octave in 0..<octaves {
            total += valueNoise(
                x: x * currentFrequency,
                y: y * currentFrequency,
                seed: seed &+ (UInt64(octave) &* 0x9E3779B97F4A7C15)
            ) * amplitude
            totalAmplitude += amplitude
            amplitude *= 0.5
            currentFrequency *= 2.03
        }
        return total / totalAmplitude
    }

    private static func ridgedNoise(x: Double, y: Double, frequency: Double, seed: UInt64) -> Double {
        let noise = fractalNoise(x: x, y: y, frequency: frequency, octaves: 3, seed: seed)
        return 1 - abs(noise * 2 - 1)
    }

    private static func valueNoise(x: Double, y: Double, seed: UInt64) -> Double {
        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = x0 + 1
        let y1 = y0 + 1
        let tx = smoothstep(x - Double(x0))
        let ty = smoothstep(y - Double(y0))
        let top = mix(hashNoise(x: x0, y: y0, seed: seed), hashNoise(x: x1, y: y0, seed: seed), tx)
        let bottom = mix(hashNoise(x: x0, y: y1, seed: seed), hashNoise(x: x1, y: y1, seed: seed), tx)
        return mix(top, bottom, ty)
    }

    private static func hashNoise(x: Int, y: Int, seed: UInt64) -> Double {
        var value = UInt64(bitPattern: Int64(x)) &* 0x9E3779B185EBCA87
        value ^= UInt64(bitPattern: Int64(y)) &* 0xC2B2AE3D27D4EB4F
        value ^= seed
        value ^= value >> 30
        value &*= 0xBF58476D1CE4E5B9
        value ^= value >> 27
        value &*= 0x94D049BB133111EB
        value ^= value >> 31
        return Double(value >> 11) / Double(1 << 53)
    }

    private static func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }

    private static func mix(_ first: Double, _ second: Double, _ amount: Double) -> Double {
        first + (second - first) * amount
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }

    mutating func nextUnit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
