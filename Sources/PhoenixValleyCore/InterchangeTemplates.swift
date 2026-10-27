import Foundation

/// Pre-built interchange and junction templates that can be stamped directly onto the canvas.
public struct InterchangeTemplate: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let iconName: String
    public let category: Category

    public enum Category: String, CaseIterable, Sendable {
        case atGrade = "平面路口"
        case gradeSeparated = "立体交叉"
    }

    public init(
        id: String,
        name: String,
        summary: String,
        iconName: String,
        category: Category
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.iconName = iconName
        self.category = category
    }

    public static let allTemplates: [InterchangeTemplate] = [
        InterchangeTemplate(
            id: "t_junction",
            name: "T 字路口",
            summary: "标准三岔平交路口，主干道与分支垂直接入",
            iconName: "arrow.triangle.merge",
            category: .atGrade
        ),
        InterchangeTemplate(
            id: "cross_junction",
            name: "十字路口",
            summary: "经典四向平交路口，适用于城市网格路网",
            iconName: "plus",
            category: .atGrade
        ),
        InterchangeTemplate(
            id: "roundabout",
            name: "环岛 / 环形交叉",
            summary: "四向进出环形分流，消减左转冲突点",
            iconName: "circle",
            category: .atGrade
        ),
        InterchangeTemplate(
            id: "diamond",
            name: "菱形立交",
            summary: "主线高速上下分离，设四条匝道连接地面干道",
            iconName: "rhombus",
            category: .gradeSeparated
        ),
        InterchangeTemplate(
            id: "trumpet",
            name: "喇叭形立交",
            summary: "高速公路与终点立交首选，包含定向匝道与环形弯道",
            iconName: "tornado",
            category: .gradeSeparated
        ),
        InterchangeTemplate(
            id: "cloverleaf",
            name: "四叶草苜蓿叶立交",
            summary: "两条全互通高速公路上跨下穿，全方向顺畅连接",
            iconName: "clover",
            category: .gradeSeparated
        )
    ]

    /// Instantiates the road segments and relations for this template centered at the given coordinate.
    public func instantiate(
        center: RoadPoint,
        sizeScale: Double = 1.0
    ) -> (roads: [RoadSegment], interchanges: [RoadInterchange]) {
        let s = max(0.4, min(3.0, sizeScale))
        let cx = center.x
        let cy = center.y

        switch id {
        case "t_junction":
            let main = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [RoadPoint(x: cx - 180 * s, y: cy), RoadPoint(x: cx + 180 * s, y: cy)]
            )
            let branch = RoadSegment(
                kind: .street,
                level: .ground,
                points: [RoadPoint(x: cx, y: cy), RoadPoint(x: cx, y: cy + 180 * s)]
            )
            return ([main, branch], [])

        case "cross_junction":
            let horiz = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [RoadPoint(x: cx - 200 * s, y: cy), RoadPoint(x: cx + 200 * s, y: cy)]
            )
            let vert = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [RoadPoint(x: cx, y: cy - 200 * s), RoadPoint(x: cx, y: cy + 200 * s)]
            )
            return ([horiz, vert], [])

        case "roundabout":
            let radius = 65.0 * s
            let vertexCount = 12
            var ringPoints: [RoadPoint] = []
            for i in 0...vertexCount {
                let angle = Double(i % vertexCount) * 2 * .pi / Double(vertexCount)
                ringPoints.append(RoadPoint(x: cx + cos(angle) * radius, y: cy + sin(angle) * radius))
            }
            let ring = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: ringPoints
            )
            let west = RoadSegment(
                kind: .street,
                level: .ground,
                points: [RoadPoint(x: cx - 180 * s, y: cy), RoadPoint(x: cx - radius, y: cy)]
            )
            let east = RoadSegment(
                kind: .street,
                level: .ground,
                points: [RoadPoint(x: cx + radius, y: cy), RoadPoint(x: cx + 180 * s, y: cy)]
            )
            let north = RoadSegment(
                kind: .street,
                level: .ground,
                points: [RoadPoint(x: cx, y: cy - 180 * s), RoadPoint(x: cx, y: cy - radius)]
            )
            let south = RoadSegment(
                kind: .street,
                level: .ground,
                points: [RoadPoint(x: cx, y: cy + radius), RoadPoint(x: cx, y: cy + 180 * s)]
            )
            return ([ring, west, east, north, south], [])

        case "diamond":
            // Highway on elevated bridge, arterial on ground
            let highway = RoadSegment(
                kind: .motorway,
                level: .elevated,
                structure: .elevated,
                points: [RoadPoint(x: cx - 320 * s, y: cy), RoadPoint(x: cx + 320 * s, y: cy)]
            )
            let arterial = RoadSegment(
                kind: .arterial,
                level: .ground,
                structure: .ground,
                points: [RoadPoint(x: cx, y: cy - 260 * s), RoadPoint(x: cx, y: cy + 260 * s)]
            )
            // 4 ramps connecting the elevated highway to arterial
            let rampNW = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx - 220 * s, y: cy - 18 * s),
                    RoadPoint(x: cx - 120 * s, y: cy - 90 * s),
                    RoadPoint(x: cx - 18 * s, y: cy - 160 * s)
                ]
            )
            let rampNE = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx + 18 * s, y: cy - 160 * s),
                    RoadPoint(x: cx + 120 * s, y: cy - 90 * s),
                    RoadPoint(x: cx + 220 * s, y: cy - 18 * s)
                ]
            )
            let rampSW = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx - 220 * s, y: cy + 18 * s),
                    RoadPoint(x: cx - 120 * s, y: cy + 90 * s),
                    RoadPoint(x: cx - 18 * s, y: cy + 160 * s)
                ]
            )
            let rampSE = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx + 18 * s, y: cy + 160 * s),
                    RoadPoint(x: cx + 120 * s, y: cy + 90 * s),
                    RoadPoint(x: cx + 220 * s, y: cy + 18 * s)
                ]
            )
            return ([highway, arterial, rampNW, rampNE, rampSW, rampSE], [])

        case "trumpet":
            let highway = RoadSegment(
                kind: .motorway,
                level: .ground,
                points: [RoadPoint(x: cx - 350 * s, y: cy), RoadPoint(x: cx + 350 * s, y: cy)]
            )
            let branch = RoadSegment(
                kind: .arterial,
                level: .elevated,
                structure: .elevated,
                points: [RoadPoint(x: cx, y: cy - 280 * s), RoadPoint(x: cx, y: cy + 60 * s)]
            )
            let directRamp = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx - 20 * s, y: cy - 180 * s),
                    RoadPoint(x: cx - 120 * s, y: cy - 100 * s),
                    RoadPoint(x: cx - 220 * s, y: cy - 12 * s)
                ]
            )
            // Loop ramp
            let loopRamp = RoadSegment(
                kind: .arterial,
                level: .ground,
                points: [
                    RoadPoint(x: cx + 20 * s, y: cy - 180 * s),
                    RoadPoint(x: cx + 110 * s, y: cy - 80 * s),
                    RoadPoint(x: cx + 140 * s, y: cy + 30 * s),
                    RoadPoint(x: cx + 70 * s, y: cy + 80 * s),
                    RoadPoint(x: cx - 40 * s, y: cy + 30 * s),
                    RoadPoint(x: cx - 160 * s, y: cy + 12 * s)
                ]
            )
            return ([highway, branch, directRamp, loopRamp], [])

        case "cloverleaf":
            let highway1 = RoadSegment(
                kind: .motorway,
                level: .elevated,
                structure: .elevated,
                points: [RoadPoint(x: cx - 360 * s, y: cy), RoadPoint(x: cx + 360 * s, y: cy)]
            )
            let highway2 = RoadSegment(
                kind: .motorway,
                level: .ground,
                structure: .ground,
                points: [RoadPoint(x: cx, y: cy - 360 * s), RoadPoint(x: cx, y: cy + 360 * s)]
            )
            // 4 Outer ramps
            let outerNW = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx - 260 * s, y: cy - 24 * s), RoadPoint(x: cx - 160 * s, y: cy - 160 * s), RoadPoint(x: cx - 24 * s, y: cy - 260 * s)]
            )
            let outerNE = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx + 24 * s, y: cy - 260 * s), RoadPoint(x: cx + 160 * s, y: cy - 160 * s), RoadPoint(x: cx + 260 * s, y: cy - 24 * s)]
            )
            let outerSW = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx - 260 * s, y: cy + 24 * s), RoadPoint(x: cx - 160 * s, y: cy + 160 * s), RoadPoint(x: cx - 24 * s, y: cy + 260 * s)]
            )
            let outerSE = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx + 260 * s, y: cy + 24 * s), RoadPoint(x: cx + 160 * s, y: cy + 160 * s), RoadPoint(x: cx + 24 * s, y: cy + 260 * s)]
            )
            // 4 Inner loop ramps (270-degree loops)
            let loopNW = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx - 80 * s, y: cy - 15 * s), RoadPoint(x: cx - 120 * s, y: cy - 60 * s), RoadPoint(x: cx - 70 * s, y: cy - 110 * s), RoadPoint(x: cx - 15 * s, y: cy - 80 * s)]
            )
            let loopNE = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx + 15 * s, y: cy - 80 * s), RoadPoint(x: cx + 70 * s, y: cy - 110 * s), RoadPoint(x: cx + 120 * s, y: cy - 60 * s), RoadPoint(x: cx + 80 * s, y: cy - 15 * s)]
            )
            let loopSW = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx - 15 * s, y: cy + 80 * s), RoadPoint(x: cx - 70 * s, y: cy + 110 * s), RoadPoint(x: cx - 120 * s, y: cy + 60 * s), RoadPoint(x: cx - 80 * s, y: cy + 15 * s)]
            )
            let loopSE = RoadSegment(
                kind: .arterial, level: .ground,
                points: [RoadPoint(x: cx + 80 * s, y: cy + 15 * s), RoadPoint(x: cx + 120 * s, y: cy + 60 * s), RoadPoint(x: cx + 70 * s, y: cy + 110 * s), RoadPoint(x: cx + 15 * s, y: cy + 80 * s)]
            )
            return ([highway1, highway2, outerNW, outerNE, outerSW, outerSE, loopNW, loopNE, loopSW, loopSE], [])

        default:
            return ([], [])
        }
    }
}
