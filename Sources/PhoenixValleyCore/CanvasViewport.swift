import Foundation

/// A similarity transform from map points to view points; heading is clockwise radians.
public struct CanvasViewport: Equatable, Sendable {
    public private(set) var scale: Double
    public private(set) var rotation: Double
    public private(set) var translation: RoadPoint

    public init(scale: Double = 1, rotation: Double = 0, translation: RoadPoint = .init(x: 0, y: 0)) {
        self.scale = scale.isFinite && scale > 0 ? scale : 1
        self.rotation = Self.normalized(rotation)
        self.translation = translation
    }

    public var isNorthUp: Bool { abs(rotation) < 0.0001 }

    public func screenPoint(for point: RoadPoint) -> RoadPoint {
        RoadPoint(x: scale * (cos(rotation) * point.x - sin(rotation) * point.y) + translation.x,
                  y: scale * (sin(rotation) * point.x + cos(rotation) * point.y) + translation.y)
    }

    public func worldPoint(for point: RoadPoint) -> RoadPoint {
        let x = (point.x - translation.x) / scale
        let y = (point.y - translation.y) / scale
        return RoadPoint(x: cos(rotation) * x + sin(rotation) * y,
                         y: -sin(rotation) * x + cos(rotation) * y)
    }

    public mutating func navigate(scaleFactor: Double = 1, rotationDelta: Double = 0,
                                  anchor: RoadPoint, minimumScale: Double = 0.1, maximumScale: Double = 4) {
        guard scaleFactor.isFinite, scaleFactor > 0, rotationDelta.isFinite else { return }
        let worldAnchor = worldPoint(for: anchor)
        scale = min(maximumScale, max(minimumScale, scale * scaleFactor))
        rotation = Self.normalized(rotation + rotationDelta)
        let mapped = screenPoint(for: worldAnchor)
        pan(by: anchor - mapped)
    }

    /// Settles incidental two-finger rotation when navigation finishes near north.
    public mutating func snapToNorthIfClose(anchor: RoadPoint) {
        guard abs(rotation) <= 2 * .pi / 180 else { return }
        navigate(rotationDelta: -rotation, anchor: anchor, minimumScale: scale, maximumScale: scale)
    }

    public mutating func pan(by delta: RoadPoint) {
        guard delta.x.isFinite, delta.y.isFinite else { return }
        translation = translation + delta
    }

    /// Keeps the rotated map's bounding box reachable without an unbounded empty pan.
    public mutating func constrain(to size: RoadPoint, overscroll: Double = 36) {
        let corners = [RoadPoint(x: 0, y: 0), RoadPoint(x: 1600, y: 0),
                       RoadPoint(x: 0, y: 1200), RoadPoint(x: 1600, y: 1200)].map(screenPoint)
        let minX = corners.map(\.x).min()!
        let maxX = corners.map(\.x).max()!
        let minY = corners.map(\.y).min()!
        let maxY = corners.map(\.y).max()!
        func correction(_ minimum: Double, _ maximum: Double, _ extent: Double) -> Double {
            if maximum - minimum <= extent { return (extent - minimum - maximum) / 2 }
            if minimum > overscroll { return overscroll - minimum }
            if maximum < extent - overscroll { return extent - overscroll - maximum }
            return 0
        }
        pan(by: RoadPoint(x: correction(minX, maxX, size.x), y: correction(minY, maxY, size.y)))
    }

    public static func normalized(_ angle: Double) -> Double {
        guard angle.isFinite else { return 0 }
        let wrapped = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if wrapped >= .pi { return wrapped - 2 * .pi }
        if wrapped < -.pi { return wrapped + 2 * .pi }
        return wrapped
    }
}
