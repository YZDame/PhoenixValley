import Foundation

public struct TerrainGenerationRequest: Hashable, Sendable {
    public var seed: UInt64
    public var vertexCount: Int
    public var gridWidth: Int
    public var gridHeight: Int
    public var generationVersion: Int
    public var scenario: TerrainScenario

    public init(
        seed: UInt64,
        vertexCount: Int = 96,
        gridWidth: Int = 257,
        gridHeight: Int = 193,
        scenario: TerrainScenario = .island
    ) {
        self.seed = seed
        self.vertexCount = max(72, vertexCount)
        self.gridWidth = max(17, gridWidth)
        self.gridHeight = max(13, gridHeight)
        self.scenario = scenario
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
        gridWidth: Int = 257,
        gridHeight: Int = 193,
        scenario: TerrainScenario = .island
    ) -> TerrainLayout {
        let request = TerrainGenerationRequest(
            seed: seed,
            vertexCount: vertexCount,
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            scenario: scenario
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
        let shoreline: [RoadPoint]
        switch request.scenario {
        case .island:
            shoreline = makeShoreline(
                center: center,
                horizontalBase: horizontalBase,
                verticalBase: verticalBase,
                rotation: rotation,
                vertexCount: request.vertexCount,
                generator: &generator
            )
        case .coastalCity:
            shoreline = makeCoastalShoreline(
                vertexCount: request.vertexCount,
                generator: &generator
            )
        case .continent:
            let coastOnLeft = generator.nextUnit() > 0.5
            shoreline = makeShoreline(
                center: RoadPoint(
                    x: coastOnLeft ? 1_720 : -120,
                    y: 520 + generator.nextUnit() * 160
                ),
                horizontalBase: 1_380 + generator.nextUnit() * 260,
                verticalBase: 760 + generator.nextUnit() * 180,
                rotation: (generator.nextUnit() - 0.5) * 0.26,
                vertexCount: request.vertexCount,
                generator: &generator
            )
        case .riverAndLakes:
            shoreline = makeShoreline(
                center: RoadPoint(
                    x: 720 + generator.nextUnit() * 160,
                    y: 520 + generator.nextUnit() * 150
                ),
                horizontalBase: 810 + generator.nextUnit() * 190,
                verticalBase: 590 + generator.nextUnit() * 145,
                rotation: (generator.nextUnit() - 0.5) * 0.34,
                vertexCount: request.vertexCount,
                generator: &generator
            )
        default:
            shoreline = [
                RoadPoint(x: -80, y: -80),
                RoadPoint(x: 1680, y: -80),
                RoadPoint(x: 1680, y: 1280),
                RoadPoint(x: -80, y: 1280),
            ]
        }
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

        if request.scenario == .valley {
            ridges = [
                makeRidge(
                    center: RoadPoint(x: 800, y: 260),
                    direction: 0,
                    length: 1_850,
                    bend: 120,
                    width: 150,
                    height: 0.42
                ),
                makeRidge(
                    center: RoadPoint(x: 800, y: 940),
                    direction: 0,
                    length: 1_850,
                    bend: -120,
                    width: 150,
                    height: 0.42
                ),
            ]
        } else if request.scenario == .mountains {
            ridges.append(
                makeRidge(
                    center: RoadPoint(x: 820, y: 620),
                    direction: primaryDirection + .pi / 2,
                    length: 1_350,
                    bend: 240,
                    width: 115,
                    height: 0.44
                )
            )
        } else if request.scenario == .hills {
            ridges = ridges.map {
                Ridge(points: $0.points, width: $0.width * 1.65, height: $0.height * 0.48)
            }
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
        let drainageSeed = hashNoise(x: 31, y: 47, seed: seed)
        let drainageRunsHorizontally = drainageSeed > 0.5
        let drainageReversed = hashNoise(x: 53, y: 71, seed: seed) > 0.5

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
                let hasVisibleCoast = request.scenario == .island
                    || request.scenario == .coastalCity
                    || request.scenario == .continent
                    || request.scenario == .riverAndLakes
                var elevation = hasVisibleCoast
                    ? 0.215 + min(1, coastDistance / 230) * 0.095
                    : 0.33

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

                if request.scenario == .basin {
                    let basinDistance = hypot(point.x - 800, point.y - 600)
                    elevation += min(0.22, abs(basinDistance - 420) / 900)
                    elevation -= exp(-pow(basinDistance / 310, 2) * 0.5) * 0.12
                }

                let warpX = (fractalNoise(
                    x: point.x,
                    y: point.y,
                    frequency: 0.00125,
                    octaves: 3,
                    seed: seed &+ 0x8EBC6AF09C88C6E3
                ) - 0.5) * 210
                let warpY = (fractalNoise(
                    x: point.x,
                    y: point.y,
                    frequency: 0.00125,
                    octaves: 3,
                    seed: seed &+ 0x589965CC75374CC3
                ) - 0.5) * 210
                let broadRelief = fractalNoise(
                    x: point.x + warpX,
                    y: point.y + warpY,
                    frequency: 0.0018,
                    octaves: 5,
                    seed: seed &+ 0xA0761D6478BD642F
                )
                let localRelief = ridgedNoise(
                    x: point.x + warpX * 0.45,
                    y: point.y + warpY * 0.45,
                    frequency: 0.009,
                    seed: seed &+ 0xE7037ED1A0B428DB
                )
                let reliefScale = request.scenario == .hills ? 0.55 : 1
                elevation += (broadRelief - 0.5) * 0.12 * reliefScale
                elevation += (localRelief - 0.5) * 0.045 * reliefScale

                if request.scenario == .riverAndLakes {
                    let progress = drainageRunsHorizontally
                        ? point.x / 1_600
                        : point.y / 1_200
                    let downstreamProgress = drainageReversed ? 1 - progress : progress
                    elevation += (1 - downstreamProgress) * 0.115
                }

                // Keep a narrow, low coastal shelf while preserving inland plains.
                if hasVisibleCoast {
                    let coastalCeiling = 0.27 + min(1, coastDistance / 120) * 0.73
                    elevation = min(elevation, coastalCeiling)
                }
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

        if request.scenario == .riverAndLakes {
            carveDrainageNetwork(
                into: &elevations,
                width: width,
                height: height,
                waterLevel: 0.2,
                seed: seed,
                runsHorizontally: drainageRunsHorizontally,
                reversed: drainageReversed
            )
        }

        return TerrainLayout(
            seed: seed,
            shoreline: shoreline,
            generationVersion: TerrainLayout.currentGenerationVersion,
            gridWidth: width,
            gridHeight: height,
            elevations: elevations,
            waterLevel: 0.2,
            scenario: request.scenario
        )
    }

    public static func upgrading(_ terrain: TerrainLayout) -> TerrainLayout {
        guard !terrain.hasElevationData
            || terrain.generationVersion < TerrainLayout.currentGenerationVersion
        else { return terrain }
        return generate(seed: terrain.seed, scenario: terrain.scenario)
    }

    private static func makeCoastalShoreline(
        vertexCount: Int,
        generator: inout SeededGenerator
    ) -> [RoadPoint] {
        let samples = max(36, vertexCount / 2)
        let seaOnLeft = generator.nextUnit() > 0.5
        var coast: [RoadPoint] = []
        coast.reserveCapacity(samples + 3)
        for index in 0..<samples {
            let amount = Double(index) / Double(samples - 1)
            let y = -60 + amount * 1_320
            let baseX = 350
                + sin(amount * .pi * 2.2 + generator.nextUnit() * 0.08) * 120
                + sin(amount * .pi * 6.5) * 38
            coast.append(
                RoadPoint(
                    x: seaOnLeft ? baseX : 1_600 - baseX,
                    y: y
                )
            )
        }
        if seaOnLeft {
            coast.append(RoadPoint(x: 1_680, y: 1_280))
            coast.append(RoadPoint(x: 1_680, y: -80))
        } else {
            coast.append(RoadPoint(x: -80, y: 1_280))
            coast.append(RoadPoint(x: -80, y: -80))
        }
        return coast
    }

    /// Builds a scale-aware dendritic water network on top of the height field.
    ///
    /// Every land cell contributes seeded rainfall to its lowest downstream
    /// neighbour. Accumulated flow decides which branches become visible and
    /// how wide they are. This is a directed D8-style approximation tailored to
    /// the small canvas: it preserves drainage connectivity without running a
    /// full hydraulic erosion simulation.
    private static func carveDrainageNetwork(
        into elevations: inout [UInt16],
        width: Int,
        height: Int,
        waterLevel: Double,
        seed: UInt64,
        runsHorizontally: Bool,
        reversed: Bool
    ) {
        guard width >= 3, height >= 3, elevations.count == width * height else { return }

        let majorCount = runsHorizontally ? width : height
        let lateralCount = runsHorizontally ? height : width
        let cellWidth = 1_600 / Double(width - 1)
        let cellHeight = 1_200 / Double(height - 1)
        let cellCount = width * height
        let waterValue = UInt16((waterLevel * Double(UInt16.max)).rounded())
        var generator = SeededGenerator(seed: seed &+ 0xD1B54A32D192ED03)
        var receiver = Array(repeating: -1, count: cellCount)
        var accumulation = (0..<cellCount).map { index in
            0.72 + hashNoise(
                x: index % width,
                y: index / width,
                seed: seed &+ 0xDB4F0B9175AE2165
            ) * 0.56
        }

        func coordinates(major: Int, lateral: Int) -> (column: Int, row: Int) {
            let directedMajor = reversed ? majorCount - 1 - major : major
            return runsHorizontally
                ? (directedMajor, lateral)
                : (lateral, directedMajor)
        }

        // Choose one downstream receiver per cell. Constraining receivers to
        // the next major slice guarantees an acyclic graph while still allowing
        // bends, confluences, and several tributary orders.
        for major in 0..<(majorCount - 1) {
            for lateral in 1..<(lateralCount - 1) {
                let current = coordinates(major: major, lateral: lateral)
                let currentIndex = current.row * width + current.column
                guard elevations[currentIndex] > waterValue else { continue }
                let currentElevation = Double(elevations[currentIndex]) / Double(UInt16.max)
                var bestIndex = -1
                var bestScore = Double.infinity
                for delta in -2...2 {
                    let candidate = min(lateralCount - 2, max(1, lateral + delta))
                    let coordinate = coordinates(major: major + 1, lateral: candidate)
                    let index = coordinate.row * width + coordinate.column
                    let elevation = Double(elevations[index])
                        / Double(UInt16.max)
                    let uphillPenalty = max(0, elevation - currentElevation) * 5.2
                    let diagonalPenalty = Double(abs(delta)) * 0.0014
                    let terrainJitter = hashNoise(
                        x: coordinate.column,
                        y: coordinate.row,
                        seed: seed &+ 0x94D049BB133111EB
                    ) * 0.018
                    let score = elevation + uphillPenalty + diagonalPenalty + terrainJitter
                    if score < bestScore {
                        bestScore = score
                        bestIndex = index
                    }
                }
                receiver[currentIndex] = bestIndex
            }
        }

        // Upstream-to-downstream traversal accumulates rainfall at confluences.
        for major in 0..<(majorCount - 1) {
            for lateral in 1..<(lateralCount - 1) {
                let current = coordinates(major: major, lateral: lateral)
                let currentIndex = current.row * width + current.column
                let downstream = receiver[currentIndex]
                if downstream >= 0 {
                    accumulation[downstream] += accumulation[currentIndex]
                }
            }
        }

        let streamThreshold = max(8, Double(cellCount) * 0.0062)
        var lakeCandidates: [Int] = []
        for major in 1..<(majorCount - 1) {
            let progress = Double(major) / Double(max(1, majorCount - 1))
            for lateral in 1..<(lateralCount - 1) {
                let center = coordinates(major: major, lateral: lateral)
                let centerIndex = center.row * width + center.column
                let flow = accumulation[centerIndex]
                guard flow >= streamThreshold, elevations[centerIndex] > waterValue else { continue }

                let order = sqrt(flow / streamThreshold)
                let channelRadius = min(9.2, 2.4 + order * 1.55)
                if progress > 0.28, progress < 0.76, flow >= streamThreshold * 2.4 {
                    lakeCandidates.append(centerIndex)
                }

            let columnRadius = max(1, Int(ceil(channelRadius / cellWidth)))
            let rowRadius = max(1, Int(ceil(channelRadius / cellHeight)))
            for rowOffset in -rowRadius...rowRadius {
                for columnOffset in -columnRadius...columnRadius {
                    let column = center.column + columnOffset
                    let row = center.row + rowOffset
                    guard column >= 0, column < width, row >= 0, row < height else { continue }
                    let distance = hypot(
                        Double(columnOffset) * cellWidth,
                        Double(rowOffset) * cellHeight
                    )
                    guard distance <= channelRadius else { continue }
                    let bankAmount = min(1, distance / max(channelRadius, 0.1))
                    let carved = Double(waterValue) * (0.965 + bankAmount * 0.028)
                    elevations[row * width + column] = min(
                        elevations[row * width + column],
                        UInt16(carved.rounded())
                    )
                }
            }
            }
        }

        let lakeCount = 1 + Int(generator.next() % 2)
        for lakeIndex in 0..<min(lakeCount, lakeCandidates.count) {
            let slot = min(
                lakeCandidates.count - 1,
                (lakeIndex * lakeCandidates.count / lakeCount)
                    + Int(generator.next() % UInt64(max(1, lakeCandidates.count / lakeCount)))
            )
            let centerIndex = lakeCandidates[slot]
            let center = (column: centerIndex % width, row: centerIndex / width)
            let radiusX = 18 + generator.nextUnit() * 24
            let radiusY = 14 + generator.nextUnit() * 20
            let columnRadius = max(1, Int(ceil(radiusX / cellWidth)))
            let rowRadius = max(1, Int(ceil(radiusY / cellHeight)))

            for rowOffset in -rowRadius...rowRadius {
                for columnOffset in -columnRadius...columnRadius {
                    let column = center.column + columnOffset
                    let row = center.row + rowOffset
                    guard column >= 0, column < width, row >= 0, row < height else { continue }
                    let normalizedDistance = hypot(
                        Double(columnOffset) * cellWidth / radiusX,
                        Double(rowOffset) * cellHeight / radiusY
                    )
                    let edgeVariation = 0.88 + hashNoise(
                        x: column,
                        y: row,
                        seed: seed &+ UInt64(lakeIndex + 1) &* 0x9E3779B97F4A7C15
                    ) * 0.18
                    guard normalizedDistance <= edgeVariation else { continue }
                    elevations[row * width + column] = min(
                        elevations[row * width + column],
                        UInt16(Double(waterValue) * 0.955)
                    )
                }
            }
        }
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
