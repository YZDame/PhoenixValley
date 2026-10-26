import Foundation
import PhoenixValleyCore
import SwiftUI

struct MapContentThumbnail: View {
    let project: RoadProject
    let size: CGSize

    var body: some View {
        Canvas(
            opaque: true,
            colorMode: .nonLinear,
            rendersAsynchronously: true
        ) { context, canvasSize in
            drawThumbnail(in: &context, size: canvasSize)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.primary.opacity(0.12))
        }
        .accessibilityHidden(true)
    }

    private func drawThumbnail(
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let palette = project.theme.thumbnailPalette
        context.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .color(
                project.layerVisibility.showsTerrain
                    ? palette.water
                    : palette.plain
            )
        )

        if let map = project.realWorldMap {
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(palette.plain))
            if project.layerVisibility.showsTerrain {
                for feature in map.features {
                    if feature.kind == .water && !project.layerVisibility.showsHydrology { continue }
                    let outline = path(for: feature.points, size: size, closes: true)
                    context.fill(outline, with: .color(Color(cgColor: CartographicRenderer.featureColor(feature.kind, dark: project.theme == .midnight))))
                }
            }
            drawRoads(in: &context, size: size, palette: palette)
            return
        }
        if project.layerVisibility.showsTerrain {
            let shoreline = path(
                for: project.terrain.shoreline,
                size: size,
                closes: true
            )
            if !shoreline.isEmpty {
                context.fill(shoreline, with: .color(palette.plain))
                var landContext = context
                landContext.clip(to: shoreline)
                drawElevationSamples(
                    in: &landContext,
                    size: size,
                    palette: palette
                )

                context.stroke(
                    shoreline,
                    with: .color(palette.shoreline),
                    lineWidth: 0.7
                )
            }
        }
        drawRoads(in: &context, size: size, palette: palette)
    }

    private func drawElevationSamples(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: ThumbnailPalette
    ) {
        let columns = 10
        let rows = 8
        let cellWidth = size.width / CGFloat(columns)
        let cellHeight = size.height / CGFloat(rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let point = RoadPoint(
                    x: (Double(column) + 0.5) / Double(columns) * 1_600,
                    y: (Double(row) + 0.5) / Double(rows) * 1_200
                )
                let elevation = project.terrain.normalizedElevation(at: point)
                let rect = CGRect(
                    x: CGFloat(column) * cellWidth,
                    y: CGFloat(row) * cellHeight,
                    width: cellWidth + 0.5,
                    height: cellHeight + 0.5
                )
                context.fill(
                    Path(rect),
                    with: .color(palette.landColor(for: elevation))
                )
            }
        }
    }

    private func drawRoads(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: ThumbnailPalette
    ) {
        drawBridgePiers(
            in: &context,
            size: size,
            palette: palette
        )
        for road in project.roads
        where project.layerVisibility.isVisible(road.kind) {
            let roadPath = path(for: road.points, size: size, closes: false)
            guard !roadPath.isEmpty else { continue }
            let width = road.kind.thumbnailWidth
            let style = StrokeStyle(
                lineWidth: width,
                lineCap: .round,
                lineJoin: .round,
                dash: road.structure == .tunnel ? [2, 1.4] : []
            )

            context.stroke(
                roadPath,
                with: .color(palette.roadCasing),
                style: StrokeStyle(
                    lineWidth: width + 0.8,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
            context.stroke(
                roadPath,
                with: .color(palette.roadColor(for: road)),
                style: style
            )
        }
        drawTunnelPortals(
            in: &context,
            size: size,
            palette: palette
        )
    }

    private func drawBridgePiers(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: ThumbnailPalette
    ) {
        for structure in project.engineeringStructures
        where structure.structure == .bridge
            && project.layerVisibility.isVisible(structure.roadKind) {
            for pier in structure.bridgePiers {
                let normal = RoadPoint(
                    x: -pier.tangent.y,
                    y: pier.tangent.x
                )
                let halfLength = 8.0
                var path = Path()
                path.move(to: scaled(pier.point - normal * halfLength, size: size))
                path.addLine(to: scaled(pier.point + normal * halfLength, size: size))
                context.stroke(
                    path,
                    with: .color(palette.roadCasing.opacity(0.8)),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
    }

    private func drawTunnelPortals(
        in context: inout GraphicsContext,
        size: CGSize,
        palette: ThumbnailPalette
    ) {
        for structure in project.engineeringStructures
        where structure.structure == .tunnel
            && project.layerVisibility.isVisible(structure.roadKind) {
            for portal in structure.tunnelPortals {
                let normal = RoadPoint(
                    x: -portal.tangent.y,
                    y: portal.tangent.x
                )
                let outwardSign = portal.role == .entrance ? -1.0 : 1.0
                let outward = RoadPoint(
                    x: portal.tangent.x * outwardSign,
                    y: portal.tangent.y * outwardSign
                )
                let halfWidth = 8.0
                let depth = 6.0
                let mouthLeft = portal.point + normal * halfWidth
                let mouthRight = portal.point - normal * halfWidth
                var path = Path()
                path.move(to: scaled(mouthLeft, size: size))
                path.addLine(to: scaled(mouthLeft + outward * depth, size: size))
                path.addLine(to: scaled(mouthRight + outward * depth, size: size))
                path.addLine(to: scaled(mouthRight, size: size))
                context.stroke(
                    path,
                    with: .color(.purple.opacity(0.8)),
                    style: StrokeStyle(
                        lineWidth: 0.9,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
    }

    private func path(
        for points: [RoadPoint],
        size: CGSize,
        closes: Bool
    ) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: scaled(first, size: size))
        for point in points.dropFirst() {
            path.addLine(to: scaled(point, size: size))
        }
        if closes { path.closeSubpath() }
        return path
    }

    private func scaled(_ point: RoadPoint, size: CGSize) -> CGPoint {
        CGPoint(
            x: point.x / 1_600 * size.width,
            y: point.y / 1_200 * size.height
        )
    }
}

private extension MapTheme {
    var thumbnailPalette: ThumbnailPalette {
        let p = palette
        return ThumbnailPalette(
            water: Color(cgColor: p.water.cgColor),
            plain: Color(cgColor: p.plain.cgColor),
            lowland: Color(cgColor: p.lowland.cgColor),
            hill: Color(cgColor: p.hill.cgColor),
            mountain: Color(cgColor: p.mountain.cgColor),
            shoreline: Color(cgColor: p.shoreline.cgColor),
            roadCasing: Color(cgColor: p.roadCasing.cgColor),
            motorway: Color(cgColor: p.motorway.cgColor),
            arterial: Color(cgColor: p.arterial.cgColor),
            street: Color(cgColor: p.street.cgColor),
            railway: Color(cgColor: p.railway.cgColor)
        )
    }
}

private struct ThumbnailPalette {
    let water: Color
    let plain: Color
    let lowland: Color
    let hill: Color
    let mountain: Color
    let shoreline: Color
    let roadCasing: Color
    let motorway: Color
    let arterial: Color
    let street: Color
    let railway: Color

    func landColor(for elevation: Double) -> Color {
        switch elevation {
        case ..<0.34: plain
        case ..<0.52: lowland
        case ..<0.72: hill
        default: mountain
        }
    }

    func roadColor(for road: RoadSegment) -> Color {
        if road.structure == .bridge {
            return Color(red: 0.2, green: 0.72, blue: 0.83)
        }

        let color: Color = switch road.kind {
        case .motorway: motorway
        case .arterial: arterial
        case .street: street
        case .railway: railway
        }
        return road.structure == .tunnel ? color.opacity(0.58) : color
    }
}

private extension RoadKind {
    var thumbnailWidth: CGFloat {
        switch self {
        case .motorway: 1.8
        case .arterial: 1.45
        case .street: 0.9
        case .railway: 1.1
        }
    }
}
