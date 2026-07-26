import Foundation

public struct RoadEraseRequest: Hashable, Sendable {
    public var points: [RoadPoint]
    public var radius: Double
    public var eligibleRoadIDs: Set<UUID>

    public init(
        points: [RoadPoint],
        radius: Double,
        eligibleRoadIDs: Set<UUID>
    ) {
        self.points = points
        self.radius = max(0, radius)
        self.eligibleRoadIDs = eligibleRoadIDs
    }
}

public struct RoadNetworkEraseResult: Hashable, Sendable {
    public var network: RoadNetwork
    public var affectedSourceRoadIDs: Set<UUID>

    public init(
        network: RoadNetwork,
        affectedSourceRoadIDs: Set<UUID>
    ) {
        self.network = network
        self.affectedSourceRoadIDs = affectedSourceRoadIDs
    }
}

public extension RoadNetwork {
    static func erasing(
        _ request: RoadEraseRequest,
        from roads: [RoadSegment],
        interchanges: [RoadInterchange] = [],
        configuration: RoadTopologyConfiguration = .init()
    ) -> RoadNetworkEraseResult {
        guard !request.points.isEmpty,
              request.radius > 0,
              !request.eligibleRoadIDs.isEmpty
        else {
            return RoadNetworkEraseResult(
                network: rebuilding(
                    from: roads,
                    interchanges: interchanges,
                    configuration: configuration
                ).network,
                affectedSourceRoadIDs: []
            )
        }

        var retainedRoads: [RoadSegment] = []
        retainedRoads.reserveCapacity(roads.count)
        var affectedSourceRoadIDs: Set<UUID> = []

        for road in roads {
            let isEligible = request.eligibleRoadIDs.contains(road.id)
                || request.eligibleRoadIDs.contains(road.sourceRoadID)
            guard isEligible, road.points.count >= 2 else {
                retainedRoads.append(road)
                continue
            }

            let fragments = retainedFragments(
                of: road,
                outside: request.points,
                radius: request.radius,
                minimumEdgeLength: configuration.minimumEdgeLength
            )
            let originalLength = polylineLength(road.points)
            let retainedLength = fragments.reduce(0) {
                $0 + polylineLength($1)
            }
            let removedLength = max(0, originalLength - retainedLength)
            let minimumMeaningfulErase = max(
                configuration.minimumEdgeLength,
                request.radius * 0.12
            )
            let isFullyErased = fragments.isEmpty
                && originalLength > configuration.minimumEdgeLength

            guard isFullyErased || removedLength >= minimumMeaningfulErase else {
                retainedRoads.append(road)
                continue
            }

            affectedSourceRoadIDs.insert(road.sourceRoadID)
            for (fragmentIndex, points) in fragments.enumerated() {
                retainedRoads.append(
                    RoadSegment(
                        id: fragmentIndex == 0 ? road.id : UUID(),
                        kind: road.kind,
                        level: road.level,
                        structure: road.structure,
                        points: points,
                        direction: road.direction,
                        priority: road.priority,
                        sourceRoadID: road.sourceRoadID
                    )
                )
            }
        }

        guard !affectedSourceRoadIDs.isEmpty else {
            return RoadNetworkEraseResult(
                network: rebuilding(
                    from: roads,
                    interchanges: interchanges,
                    configuration: configuration
                ).network,
                affectedSourceRoadIDs: []
            )
        }

        return RoadNetworkEraseResult(
            network: rebuilding(
                from: retainedRoads,
                interchanges: interchanges,
                configuration: configuration
            ).network,
            affectedSourceRoadIDs: affectedSourceRoadIDs
        )
    }
}

private extension RoadNetwork {
    struct RetainedInterval {
        var start: Double
        var end: Double
    }

    static func retainedFragments(
        of road: RoadSegment,
        outside eraserPath: [RoadPoint],
        radius: Double,
        minimumEdgeLength: Double
    ) -> [[RoadPoint]] {
        let samplingDistance = max(0.5, min(3, radius / 3))
        let minimumRetainedLength = max(minimumEdgeLength, radius * 0.35)
        var fragments: [[RoadPoint]] = []
        var current: [RoadPoint] = []

        func appendPoint(_ point: RoadPoint) {
            if let last = current.last,
               last.distance(to: point) <= minimumEdgeLength {
                return
            }
            current.append(point)
        }

        func finishCurrentFragment() {
            guard current.count >= 2,
                  polylineLength(current) >= minimumRetainedLength
            else {
                current.removeAll(keepingCapacity: true)
                return
            }
            fragments.append(current)
            current.removeAll(keepingCapacity: true)
        }

        for index in 0..<(road.points.count - 1) {
            let start = road.points[index]
            let end = road.points[index + 1]
            let intervals = retainedIntervals(
                from: start,
                to: end,
                outside: eraserPath,
                radius: radius,
                samplingDistance: samplingDistance
            )

            guard !intervals.isEmpty else {
                finishCurrentFragment()
                continue
            }

            for interval in intervals {
                let retainedStart = interpolated(
                    from: start,
                    to: end,
                    amount: interval.start
                )
                let retainedEnd = interpolated(
                    from: start,
                    to: end,
                    amount: interval.end
                )
                let continuesPreviousSegment = interval.start <= 1e-9
                    && (current.last?.distance(to: retainedStart) ?? .infinity)
                        <= minimumEdgeLength

                if !continuesPreviousSegment {
                    finishCurrentFragment()
                }
                appendPoint(retainedStart)
                appendPoint(retainedEnd)

                if interval.end < 1 - 1e-9 {
                    finishCurrentFragment()
                }
            }
        }

        finishCurrentFragment()
        return fragments
    }

    static func retainedIntervals(
        from start: RoadPoint,
        to end: RoadPoint,
        outside eraserPath: [RoadPoint],
        radius: Double,
        samplingDistance: Double
    ) -> [RetainedInterval] {
        let length = start.distance(to: end)
        guard length > 1e-12 else { return [] }
        let stepCount = max(1, Int(ceil(length / samplingDistance)))

        func isErased(at amount: Double) -> Bool {
            distance(
                from: interpolated(from: start, to: end, amount: amount),
                to: eraserPath
            ) <= radius
        }

        func transition(
            from lower: Double,
            to upper: Double,
            lowerIsErased: Bool
        ) -> Double {
            var low = lower
            var high = upper
            for _ in 0..<24 {
                let middle = (low + high) / 2
                if isErased(at: middle) == lowerIsErased {
                    low = middle
                } else {
                    high = middle
                }
            }
            return (low + high) / 2
        }

        var intervals: [RetainedInterval] = []
        var previousAmount = 0.0
        var previousIsErased = isErased(at: 0)
        var retainedStart: Double? = previousIsErased ? nil : 0

        for step in 1...stepCount {
            let amount = Double(step) / Double(stepCount)
            let erased = isErased(at: amount)
            if erased != previousIsErased {
                let boundary = transition(
                    from: previousAmount,
                    to: amount,
                    lowerIsErased: previousIsErased
                )
                if previousIsErased {
                    retainedStart = boundary
                } else if let startOfRetained = retainedStart {
                    intervals.append(
                        RetainedInterval(start: startOfRetained, end: boundary)
                    )
                    retainedStart = nil
                }
            }
            previousAmount = amount
            previousIsErased = erased
        }

        if let retainedStart {
            intervals.append(RetainedInterval(start: retainedStart, end: 1))
        }
        return intervals
    }

    static func distance(
        from point: RoadPoint,
        to polyline: [RoadPoint]
    ) -> Double {
        guard let first = polyline.first else { return .infinity }
        guard polyline.count >= 2 else { return point.distance(to: first) }

        var minimumDistance = Double.infinity
        for index in 0..<(polyline.count - 1) {
            minimumDistance = min(
                minimumDistance,
                distance(
                    from: point,
                    toSegmentFrom: polyline[index],
                    to: polyline[index + 1]
                )
            )
        }
        return minimumDistance
    }

    static func distance(
        from point: RoadPoint,
        toSegmentFrom start: RoadPoint,
        to end: RoadPoint
    ) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let squaredLength = dx * dx + dy * dy
        guard squaredLength > 1e-12 else { return point.distance(to: start) }
        let amount = min(
            1,
            max(
                0,
                ((point.x - start.x) * dx + (point.y - start.y) * dy)
                    / squaredLength
            )
        )
        return point.distance(
            to: RoadPoint(
                x: start.x + dx * amount,
                y: start.y + dy * amount
            )
        )
    }

    static func interpolated(
        from start: RoadPoint,
        to end: RoadPoint,
        amount: Double
    ) -> RoadPoint {
        RoadPoint(
            x: start.x + (end.x - start.x) * amount,
            y: start.y + (end.y - start.y) * amount
        )
    }

    static func polylineLength(_ points: [RoadPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) {
            $0 + $1.0.distance(to: $1.1)
        }
    }
}
