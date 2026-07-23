import Foundation

public struct RoadPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: RoadPoint) -> Double {
        hypot(other.x - x, other.y - y)
    }

    public static func +(lhs: RoadPoint, rhs: RoadPoint) -> RoadPoint {
        RoadPoint(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }

    public static func -(lhs: RoadPoint, rhs: RoadPoint) -> RoadPoint {
        RoadPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }

    public static func *(lhs: RoadPoint, rhs: Double) -> RoadPoint {
        RoadPoint(x: lhs.x * rhs, y: lhs.y * rhs)
    }
}
