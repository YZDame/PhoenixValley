import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MapExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case pdf
    case svg
    case geoJSON

    public var id: String { rawValue }

    public var filenameExtension: String {
        switch self {
        case .png: "png"
        case .pdf: "pdf"
        case .svg: "svg"
        case .geoJSON: "geojson"
        }
    }

    public var mimeType: String {
        switch self {
        case .png: "image/png"
        case .pdf: "application/pdf"
        case .svg: "image/svg+xml"
        case .geoJSON: "application/geo+json"
        }
    }
}

public enum MapExporterError: Error, LocalizedError {
    case couldNotCreateGraphicsContext
    case couldNotEncodeImage
    case couldNotEncodeText

    public var errorDescription: String? {
        switch self {
        case .couldNotCreateGraphicsContext:
            "无法创建地图渲染环境。"
        case .couldNotEncodeImage:
            "无法编码地图图像。"
        case .couldNotEncodeText:
            "无法编码地图文本。"
        }
    }
}

public enum MapExporter {
    public static let canvasWidth = 1_600
    public static let canvasHeight = 1_200

    public static func data(
        for project: RoadProject,
        format: MapExportFormat
    ) throws -> Data {
        switch format {
        case .png:
            try pngData(for: project)
        case .pdf:
            try pdfData(for: project)
        case .svg:
            try svgData(for: project)
        case .geoJSON:
            try geoJSONData(for: project)
        }
    }

    private static func pngData(for project: RoadProject) throws -> Data {
        let width = canvasWidth
        let height = canvasHeight
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MapExporterError.couldNotCreateGraphicsContext
        }

        prepareTopLeftCoordinateSystem(context)
        draw(project, in: context)
        guard let image = context.makeImage() else {
            throw MapExporterError.couldNotEncodeImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw MapExporterError.couldNotEncodeImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw MapExporterError.couldNotEncodeImage
        }
        return data as Data
    }

    private static func pdfData(for project: RoadProject) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw MapExporterError.couldNotCreateGraphicsContext
        }
        var mediaBox = CGRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: canvasHeight
        )
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: &mediaBox,
            nil
        ) else {
            throw MapExporterError.couldNotCreateGraphicsContext
        }

        context.beginPDFPage(nil)
        prepareTopLeftCoordinateSystem(context)
        draw(project, in: context)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private static func prepareTopLeftCoordinateSystem(_ context: CGContext) {
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
    }

    private static func draw(_ project: RoadProject, in context: CGContext) {
        let palette = ExportPalette(theme: project.theme)
        let fullCanvas = CGRect(
            x: 0,
            y: 0,
            width: canvasWidth,
            height: canvasHeight
        )
        let background = project.layerVisibility.showsTerrain
            ? palette.water
            : palette.plain
        background.setFill(in: context)
        context.fill(fullCanvas)

        if project.layerVisibility.showsTerrain,
           let shoreline = shorelinePath(project.terrain.shoreline) {
            palette.plain.setFill(in: context)
            context.addPath(shoreline)
            context.fillPath()

            context.saveGState()
            context.addPath(shoreline)
            context.clip()
            drawElevation(project.terrain, palette: palette, in: context)
            if project.showsGrid {
                drawGrid(color: palette.grid, in: context)
            }
            if project.showsContours {
                drawContours(project.terrain, color: palette.contour, in: context)
            }
            context.restoreGState()

            palette.shoreline.setStroke(in: context)
            context.setLineWidth(1.5)
            context.addPath(shoreline)
            context.strokePath()
        }

        let engineeringStructures = visibleEngineeringStructures(in: project)
        drawBridgePiers(
            engineeringStructures,
            palette: palette,
            in: context
        )
        drawRoads(project, palette: palette, in: context)
        drawTunnelPortals(
            engineeringStructures,
            palette: palette,
            in: context
        )
        drawScaleBar(project.mapScale, in: context)
    }

    private static func shorelinePath(_ points: [RoadPoint]) -> CGPath? {
        guard let first = points.first, points.count >= 3 else { return nil }
        let path = CGMutablePath()
        path.move(to: CGPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        path.closeSubpath()
        return path
    }

    private static func drawElevation(
        _ terrain: TerrainLayout,
        palette: ExportPalette,
        in context: CGContext
    ) {
        guard let image = elevationImage(terrain, palette: palette) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high

        // Quartz images use a bottom-left drawing origin. The map renderer uses
        // top-left coordinates, so temporarily cancel the outer vertical flip.
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
        context.draw(
            image,
            in: CGRect(
                x: 0,
                y: 0,
                width: canvasWidth,
                height: canvasHeight
            )
        )
    }

    private static func elevationImage(
        _ terrain: TerrainLayout,
        palette: ExportPalette
    ) -> CGImage? {
        guard terrain.hasElevationData else { return nil }
        var pixels = [UInt8](
            repeating: 0,
            count: terrain.gridWidth * terrain.gridHeight * 4
        )
        for row in 0..<terrain.gridHeight {
            for column in 0..<terrain.gridWidth {
                let elevation = Double(
                    terrain.elevations[row * terrain.gridWidth + column]
                ) / Double(UInt16.max)
                let color = palette.landColor(for: elevation)
                let index = (row * terrain.gridWidth + column) * 4
                pixels[index] = color.redByte
                pixels[index + 1] = color.greenByte
                pixels[index + 2] = color.blueByte
                pixels[index + 3] = color.alphaByte
            }
        }

        guard let provider = CGDataProvider(
            data: Data(pixels) as CFData
        ) else { return nil }
        return CGImage(
            width: terrain.gridWidth,
            height: terrain.gridHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: terrain.gridWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            ),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }

    private static func drawGrid(color: ExportColor, in context: CGContext) {
        color.setStroke(in: context)
        context.setLineWidth(0.8)
        context.beginPath()
        for x in stride(from: 80.0, through: 1_520.0, by: 80.0) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: 1_200))
        }
        for y in stride(from: 40.0, through: 1_160.0, by: 80.0) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: 1_600, y: y))
        }
        context.strokePath()
    }

    private static func drawContours(
        _ terrain: TerrainLayout,
        color: ExportColor,
        in context: CGContext
    ) {
        guard terrain.hasElevationData else { return }
        let cellWidth = Double(canvasWidth) / Double(terrain.gridWidth - 1)
        let cellHeight = Double(canvasHeight) / Double(terrain.gridHeight - 1)
        color.setStroke(in: context)
        context.setLineWidth(0.9)

        for threshold in [0.4, 0.52, 0.64, 0.76, 0.88] {
            context.beginPath()
            for row in 0..<(terrain.gridHeight - 1) {
                for column in 0..<(terrain.gridWidth - 1) {
                    let x = Double(column) * cellWidth
                    let y = Double(row) * cellHeight
                    let corners = [
                        RoadPoint(x: x, y: y),
                        RoadPoint(x: x + cellWidth, y: y),
                        RoadPoint(x: x + cellWidth, y: y + cellHeight),
                        RoadPoint(x: x, y: y + cellHeight),
                    ]
                    let values = corners.map(terrain.normalizedElevation)
                    var intersections: [CGPoint] = []

                    for edge in 0..<4 {
                        let next = (edge + 1) % 4
                        let firstValue = values[edge]
                        let secondValue = values[next]
                        guard (firstValue < threshold) != (secondValue < threshold) else {
                            continue
                        }
                        let amount = (threshold - firstValue)
                            / (secondValue - firstValue)
                        let start = corners[edge]
                        let end = corners[next]
                        intersections.append(
                            CGPoint(
                                x: start.x + (end.x - start.x) * amount,
                                y: start.y + (end.y - start.y) * amount
                            )
                        )
                    }

                    for index in stride(
                        from: 0,
                        to: intersections.count - 1,
                        by: 2
                    ) {
                        context.move(to: intersections[index])
                        context.addLine(to: intersections[index + 1])
                    }
                }
            }
            context.strokePath()
        }
    }

    private static func drawRoads(
        _ project: RoadProject,
        palette: ExportPalette,
        in context: CGContext
    ) {
        let roads = project.roads.filter {
            project.layerVisibility.isVisible($0.kind)
        }
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
                drawRoad(road, casing: true, palette: palette, in: context)
            }
        }
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
                drawRoad(road, casing: false, palette: palette, in: context)
            }
        }
    }

    private static func drawBridgePiers(
        _ structures: [RoadEngineeringStructure],
        palette: ExportPalette,
        in context: CGContext
    ) {
        for structure in structures where structure.structure == .bridge {
            let halfLength = (
                structure.roadKind.exportWidth + 10
            ) / 2
            for pier in structure.bridgePiers {
                let normal = RoadPoint(
                    x: -pier.tangent.y,
                    y: pier.tangent.x
                )
                let start = pier.point - normal * halfLength
                let end = pier.point + normal * halfLength

                context.saveGState()
                context.setLineCap(.round)
                palette.roadCasing.setStroke(in: context)
                context.setLineWidth(4)
                context.move(to: CGPoint(x: start.x, y: start.y))
                context.addLine(to: CGPoint(x: end.x, y: end.y))
                context.strokePath()
                palette.bridge.setStroke(in: context)
                context.setLineWidth(1.6)
                context.move(to: CGPoint(x: start.x, y: start.y))
                context.addLine(to: CGPoint(x: end.x, y: end.y))
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private static func drawTunnelPortals(
        _ structures: [RoadEngineeringStructure],
        palette: ExportPalette,
        in context: CGContext
    ) {
        let portalColor = ExportColor(
            red: 0.48,
            green: 0.3,
            blue: 0.72,
            alpha: 0.92
        )
        for structure in structures where structure.structure == .tunnel {
            let halfWidth = (
                structure.roadKind.exportWidth + 10
            ) / 2
            for portal in structure.tunnelPortals {
                let path = tunnelPortalPath(
                    portal,
                    halfWidth: halfWidth,
                    depth: 6
                )
                context.saveGState()
                context.setLineCap(.round)
                context.setLineJoin(.round)
                palette.roadCasing.setStroke(in: context)
                context.setLineWidth(5)
                context.addPath(path)
                context.strokePath()
                portalColor.setStroke(in: context)
                context.setLineWidth(2)
                context.addPath(path)
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private static func tunnelPortalPath(
        _ portal: RoadEngineeringEndpoint,
        halfWidth: Double,
        depth: Double
    ) -> CGPath {
        let normal = RoadPoint(
            x: -portal.tangent.y,
            y: portal.tangent.x
        )
        let outwardSign = portal.role == .entrance ? -1.0 : 1.0
        let outward = RoadPoint(
            x: portal.tangent.x * outwardSign,
            y: portal.tangent.y * outwardSign
        )
        let mouthLeft = portal.point + normal * halfWidth
        let mouthRight = portal.point - normal * halfWidth
        let outerLeft = mouthLeft + outward * depth
        let outerRight = mouthRight + outward * depth
        let path = CGMutablePath()
        path.move(to: CGPoint(x: mouthLeft.x, y: mouthLeft.y))
        path.addLine(to: CGPoint(x: outerLeft.x, y: outerLeft.y))
        path.addLine(to: CGPoint(x: outerRight.x, y: outerRight.y))
        path.addLine(to: CGPoint(x: mouthRight.x, y: mouthRight.y))
        return path
    }

    private static func drawRoad(
        _ road: RoadSegment,
        casing: Bool,
        palette: ExportPalette,
        in context: CGContext
    ) {
        guard let first = road.points.first else { return }
        context.saveGState()
        defer { context.restoreGState() }

        context.setLineCap(.round)
        context.setLineJoin(.round)
        let baseWidth = road.kind.exportWidth
        context.setLineWidth(casing ? baseWidth + 2.4 : baseWidth)
        let color: ExportColor
        if casing {
            color = road.structure == .bridge ? palette.bridge : palette.roadCasing
        } else {
            color = palette.roadColor(for: road)
        }
        color.setStroke(in: context)

        if road.kind == .railway || road.structure == .tunnel {
            context.setLineDash(phase: 0, lengths: [8, 5])
        }
        context.beginPath()
        context.move(to: CGPoint(x: first.x, y: first.y))
        for point in road.points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x, y: point.y))
        }
        context.strokePath()

        if !casing, road.structure == .bridge {
            ExportColor(red: 1, green: 1, blue: 1, alpha: 0.72)
                .setStroke(in: context)
            context.setLineWidth(1.2)
            context.setLineDash(phase: 0, lengths: [2, 7])
            context.beginPath()
            context.move(to: CGPoint(x: first.x, y: first.y))
            for point in road.points.dropFirst() {
                context.addLine(to: CGPoint(x: point.x, y: point.y))
            }
            context.strokePath()
        }
    }

    private static func drawScaleBar(
        _ mapScale: MapScale,
        in context: CGContext
    ) {
        let targetWidth = 220.0
        let distance = niceScaleDistance(
            atMost: targetWidth * mapScale.metersPerPoint
        )
        guard distance > 0 else { return }

        let barWidth = distance / mapScale.metersPerPoint
        let container = CGRect(
            x: 60,
            y: 60,
            width: barWidth + 48,
            height: 70
        )
        context.saveGState()
        context.addPath(
            CGPath(
                roundedRect: container,
                cornerWidth: 13,
                cornerHeight: 13,
                transform: nil
            )
        )
        context.setFillColor(
            red: 1,
            green: 1,
            blue: 1,
            alpha: 0.82
        )
        context.fillPath()

        let startX = container.minX + 24
        let endX = startX + barWidth
        let barY = container.maxY - 18
        context.setStrokeColor(
            red: 0.08,
            green: 0.09,
            blue: 0.1,
            alpha: 0.86
        )
        context.setLineWidth(3)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: CGPoint(x: startX, y: barY))
        context.addLine(to: CGPoint(x: endX, y: barY))
        context.move(to: CGPoint(x: startX, y: barY - 8))
        context.addLine(to: CGPoint(x: startX, y: barY + 4))
        context.move(to: CGPoint(x: endX, y: barY - 8))
        context.addLine(to: CGPoint(x: endX, y: barY + 4))
        context.strokePath()
        context.restoreGState()

        drawScaleLabel(
            formattedScaleDistance(distance),
            at: CGPoint(x: container.minX + 24, y: container.minY + 11),
            in: context
        )
    }

    private static func drawScaleLabel(
        _ label: String,
        at origin: CGPoint,
        in context: CGContext
    ) {
        let font = CTFontCreateWithName(
            "SFMono-Semibold" as CFString,
            22,
            nil
        )
        let color = CGColor(
            red: 0.08,
            green: 0.09,
            blue: 0.1,
            alpha: 0.9
        )
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: label, attributes: attributes)
        )
        let baselineFromTop = origin.y + 22

        context.saveGState()
        context.textMatrix = .identity
        // The map context has a top-left origin. Cancel that flip while
        // CoreText draws, then express the baseline from the bottom edge.
        context.translateBy(x: 0, y: CGFloat(canvasHeight))
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(
            x: origin.x,
            y: CGFloat(canvasHeight) - baselineFromTop
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private static func svgData(for project: RoadProject) throws -> Data {
        let palette = ExportPalette(theme: project.theme)
        var body: [String] = []
        let background = project.layerVisibility.showsTerrain
            ? palette.water
            : palette.plain
        body.append(
            #"<rect width="1600" height="1200" fill="\#(background.hex)"\#(background.opacityAttribute("fill"))/>"#
        )

        let shoreData = svgPathData(project.terrain.shoreline, closes: true)
        if project.layerVisibility.showsTerrain, !shoreData.isEmpty {
            body.append(
                """
                <defs>
                  <clipPath id="island"><path d="\(shoreData)"/></clipPath>
                  <filter id="terrain-smooth" x="-2%" y="-2%" width="104%" height="104%">
                    <feGaussianBlur stdDeviation="7.5"/>
                  </filter>
                </defs>
                """
            )
            body.append(
                #"<path d="\#(shoreData)" fill="\#(palette.plain.hex)"\#(palette.plain.opacityAttribute("fill"))/>"#
            )
            body.append(#"<g clip-path="url(#island)">"#)
            body.append(#"<g filter="url(#terrain-smooth)">"#)
            appendSVGElevation(
                project.terrain,
                palette: palette,
                to: &body
            )
            body.append("</g>")
            if project.showsGrid {
                appendSVGGrid(color: palette.grid, to: &body)
            }
            body.append("</g>")
            body.append(
                #"<path d="\#(shoreData)" fill="none" stroke="\#(palette.shoreline.hex)" stroke-width="1.5"\#(palette.shoreline.opacityAttribute("stroke"))/>"#
            )
        }

        let engineeringStructures = visibleEngineeringStructures(in: project)
        appendSVGBridgePiers(
            engineeringStructures,
            palette: palette,
            to: &body
        )
        appendSVGRoads(project, palette: palette, to: &body)
        appendSVGTunnelPortals(
            engineeringStructures,
            palette: palette,
            to: &body
        )
        appendSVGScaleBar(project.mapScale, to: &body)
        let title = xmlEscaped(project.name)
        let svg = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1200" viewBox="0 0 1600 1200" data-meters-per-point="\(svgNumber(project.mapScale.metersPerPoint))">
          <title>\(title)</title>
          <desc>PhoenixValley map covering \(svgNumber(project.mapScale.widthMeters)) by \(svgNumber(project.mapScale.heightMeters)) metres, origin at top left.</desc>
          \(body.joined(separator: "\n  "))
        </svg>
        """
        guard let data = svg.data(using: .utf8) else {
            throw MapExporterError.couldNotEncodeText
        }
        return data
    }

    private static func appendSVGElevation(
        _ terrain: TerrainLayout,
        palette: ExportPalette,
        to body: inout [String]
    ) {
        guard terrain.hasElevationData else { return }
        // Keep the SVG terrain fully vector while retaining enough samples to
        // avoid visible tile blocks at normal viewing sizes.
        let columns = 80
        let rows = 60
        let cellWidth = Double(canvasWidth) / Double(columns)
        let cellHeight = Double(canvasHeight) / Double(rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let point = RoadPoint(
                    x: (Double(column) + 0.5) * cellWidth,
                    y: (Double(row) + 0.5) * cellHeight
                )
                let color = palette.landColor(
                    for: terrain.normalizedElevation(at: point)
                )
                body.append(
                    #"<rect x="\#(svgNumber(Double(column) * cellWidth))" y="\#(svgNumber(Double(row) * cellHeight))" width="\#(svgNumber(cellWidth + 0.5))" height="\#(svgNumber(cellHeight + 0.5))" fill="\#(color.hex)"\#(color.opacityAttribute("fill"))/>"#
                )
            }
        }
    }

    private static func appendSVGGrid(
        color: ExportColor,
        to body: inout [String]
    ) {
        var path = ""
        for x in stride(from: 80.0, through: 1_520.0, by: 80.0) {
            path += "M\(svgNumber(x)) 0V1200"
        }
        for y in stride(from: 40.0, through: 1_160.0, by: 80.0) {
            path += "M0 \(svgNumber(y))H1600"
        }
        body.append(
            #"<path d="\#(path)" fill="none" stroke="\#(color.hex)" stroke-width="0.8"\#(color.opacityAttribute("stroke"))/>"#
        )
    }

    private static func appendSVGRoads(
        _ project: RoadProject,
        palette: ExportPalette,
        to body: inout [String]
    ) {
        let roads = project.roads.filter {
            project.layerVisibility.isVisible($0.kind)
        }
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
                appendSVGRoad(road, casing: true, palette: palette, to: &body)
            }
        }
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
                appendSVGRoad(road, casing: false, palette: palette, to: &body)
            }
        }
    }

    private static func appendSVGRoad(
        _ road: RoadSegment,
        casing: Bool,
        palette: ExportPalette,
        to body: inout [String]
    ) {
        let data = svgPathData(road.points, closes: false)
        guard !data.isEmpty else { return }
        let baseWidth = road.kind.exportWidth
        let width = casing ? baseWidth + 2.4 : baseWidth
        let color = casing
            ? (road.structure == .bridge ? palette.bridge : palette.roadCasing)
            : palette.roadColor(for: road)
        let dash = road.kind == .railway || road.structure == .tunnel
            ? #" stroke-dasharray="8 5""#
            : ""
        body.append(
            #"<path d="\#(data)" fill="none" stroke="\#(color.hex)" stroke-width="\#(svgNumber(width))" stroke-linecap="round" stroke-linejoin="round"\#(dash)\#(color.opacityAttribute("stroke"))/>"#
        )
    }

    private static func appendSVGBridgePiers(
        _ structures: [RoadEngineeringStructure],
        palette: ExportPalette,
        to body: inout [String]
    ) {
        let bridges = structures.filter {
            $0.structure == .bridge && !$0.bridgePiers.isEmpty
        }
        guard !bridges.isEmpty else { return }
        body.append(#"<g id="bridge-piers">"#)
        for structure in bridges {
            let halfLength = (structure.roadKind.exportWidth + 10) / 2
            for pier in structure.bridgePiers {
                let normal = RoadPoint(
                    x: -pier.tangent.y,
                    y: pier.tangent.x
                )
                let start = pier.point - normal * halfLength
                let end = pier.point + normal * halfLength
                body.append(
                    #"<path data-structure-id="\#(xmlEscaped(structure.id))" d="M\#(svgNumber(start.x)) \#(svgNumber(start.y))L\#(svgNumber(end.x)) \#(svgNumber(end.y))" fill="none" stroke="\#(palette.roadCasing.hex)" stroke-width="4" stroke-linecap="round"\#(palette.roadCasing.opacityAttribute("stroke"))/>"#
                )
                body.append(
                    #"<path d="M\#(svgNumber(start.x)) \#(svgNumber(start.y))L\#(svgNumber(end.x)) \#(svgNumber(end.y))" fill="none" stroke="\#(palette.bridge.hex)" stroke-width="1.6" stroke-linecap="round"\#(palette.bridge.opacityAttribute("stroke"))/>"#
                )
            }
        }
        body.append("</g>")
    }

    private static func appendSVGTunnelPortals(
        _ structures: [RoadEngineeringStructure],
        palette: ExportPalette,
        to body: inout [String]
    ) {
        let tunnels = structures.filter {
            $0.structure == .tunnel && !$0.tunnelPortals.isEmpty
        }
        guard !tunnels.isEmpty else { return }
        let portalColor = ExportColor(
            red: 0.48,
            green: 0.3,
            blue: 0.72,
            alpha: 0.92
        )
        body.append(#"<g id="tunnel-portals">"#)
        for structure in tunnels {
            let halfWidth = (structure.roadKind.exportWidth + 10) / 2
            for portal in structure.tunnelPortals {
                let path = svgTunnelPortalPath(
                    portal,
                    halfWidth: halfWidth,
                    depth: 6
                )
                body.append(
                    #"<path data-structure-id="\#(xmlEscaped(structure.id))" data-role="\#(portal.role.rawValue)" d="\#(path)" fill="none" stroke="\#(palette.roadCasing.hex)" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"\#(palette.roadCasing.opacityAttribute("stroke"))/>"#
                )
                body.append(
                    #"<path d="\#(path)" fill="none" stroke="\#(portalColor.hex)" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"\#(portalColor.opacityAttribute("stroke"))/>"#
                )
            }
        }
        body.append("</g>")
    }

    private static func svgTunnelPortalPath(
        _ portal: RoadEngineeringEndpoint,
        halfWidth: Double,
        depth: Double
    ) -> String {
        let normal = RoadPoint(
            x: -portal.tangent.y,
            y: portal.tangent.x
        )
        let outwardSign = portal.role == .entrance ? -1.0 : 1.0
        let outward = RoadPoint(
            x: portal.tangent.x * outwardSign,
            y: portal.tangent.y * outwardSign
        )
        let mouthLeft = portal.point + normal * halfWidth
        let mouthRight = portal.point - normal * halfWidth
        let outerLeft = mouthLeft + outward * depth
        let outerRight = mouthRight + outward * depth
        return "M\(svgNumber(mouthLeft.x)) \(svgNumber(mouthLeft.y))"
            + "L\(svgNumber(outerLeft.x)) \(svgNumber(outerLeft.y))"
            + "L\(svgNumber(outerRight.x)) \(svgNumber(outerRight.y))"
            + "L\(svgNumber(mouthRight.x)) \(svgNumber(mouthRight.y))"
    }

    private static func appendSVGScaleBar(
        _ mapScale: MapScale,
        to body: inout [String]
    ) {
        let distance = niceScaleDistance(
            atMost: 220 * mapScale.metersPerPoint
        )
        guard distance > 0 else { return }
        let width = distance / mapScale.metersPerPoint
        let endX = 84 + width
        body.append(
            """
            <g id="map-scale" aria-label="\(xmlEscaped(formattedScaleDistance(distance)))">
              <rect x="60" y="60" width="\(svgNumber(width + 48))" height="70" rx="13" fill="#FFFFFF" fill-opacity="0.82"/>
              <text x="84" y="93" fill="#14171A" fill-opacity="0.9" font-family="SFMono-Semibold, ui-monospace, monospace" font-size="22" font-weight="600">\(xmlEscaped(formattedScaleDistance(distance)))</text>
              <path d="M84 112H\(svgNumber(endX))M84 104V116M\(svgNumber(endX)) 104V116" fill="none" stroke="#14171A" stroke-opacity="0.86" stroke-width="3" stroke-linecap="round"/>
            </g>
            """
        )
    }

    private static func svgPathData(
        _ points: [RoadPoint],
        closes: Bool
    ) -> String {
        guard let first = points.first else { return "" }
        var data = "M\(svgNumber(first.x)) \(svgNumber(first.y))"
        for point in points.dropFirst() {
            data += "L\(svgNumber(point.x)) \(svgNumber(point.y))"
        }
        if closes { data += "Z" }
        return data
    }

    fileprivate static func svgNumber(_ value: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private static func xmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    private static func niceScaleDistance(atMost distance: Double) -> Double {
        guard distance > 0 else { return 0 }
        let magnitude = pow(10, floor(log10(distance)))
        for multiplier in [5.0, 2.0, 1.0] {
            let candidate = multiplier * magnitude
            if candidate <= distance + 1e-9 {
                return candidate
            }
        }
        return magnitude / 2
    }

    private static func formattedScaleDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            if kilometers.rounded() == kilometers {
                return "\(Int(kilometers)) km"
            }
            return "\(svgNumber(kilometers)) km"
        }
        return "\(Int(meters.rounded())) m"
    }

    private static func visibleEngineeringStructures(
        in project: RoadProject
    ) -> [RoadEngineeringStructure] {
        let visibleRoads = project.roads.filter {
            project.layerVisibility.isVisible($0.kind)
        }
        let visibleSourceRoadIDs = Set(visibleRoads.map(\.sourceRoadID))
        var structures = project.engineeringStructures.filter {
            visibleSourceRoadIDs.contains($0.sourceRoadID)
                && project.layerVisibility.isVisible($0.roadKind)
        }
        var representedSourceRoadIDs = Set(structures.map(\.sourceRoadID))
        for road in visibleRoads
        where (road.structure == .bridge || road.structure == .tunnel)
            && !representedSourceRoadIDs.contains(road.sourceRoadID) {
            structures.append(
                contentsOf: RoadEngineeringPlanner.evaluate(
                    road: road,
                    terrain: project.terrain,
                    mapScale: project.mapScale
                ).structures
            )
            representedSourceRoadIDs.insert(road.sourceRoadID)
        }
        return structures
    }

    private static func geoJSONData(for project: RoadProject) throws -> Data {
        let metersPerPoint = project.mapScale.metersPerPoint
        var features: [[String: Any]] = []
        if project.layerVisibility.showsTerrain,
           let first = project.terrain.shoreline.first {
            var coordinates = project.terrain.shoreline.map {
                [$0.x * metersPerPoint, $0.y * metersPerPoint]
            }
            coordinates.append([
                first.x * metersPerPoint,
                first.y * metersPerPoint,
            ])
            features.append([
                "type": "Feature",
                "id": "terrain-shoreline",
                "properties": [
                    "featureType": "shoreline",
                    "seed": String(project.terrain.seed),
                ],
                "geometry": [
                    "type": "Polygon",
                    "coordinates": [coordinates],
                ],
            ])
        }

        for road in project.roads
        where project.layerVisibility.isVisible(road.kind) {
            features.append([
                "type": "Feature",
                "id": road.id.uuidString,
                "properties": [
                    "featureType": "road",
                    "sourceRoadID": road.sourceRoadID.uuidString,
                    "kind": road.kind.rawValue,
                    "level": road.level.rawValue,
                    "structure": road.structure.rawValue,
                    "direction": road.direction.rawValue,
                    "priority": road.priority.rawValue,
                ],
                "geometry": [
                    "type": "LineString",
                    "coordinates": road.points.map {
                        [$0.x * metersPerPoint, $0.y * metersPerPoint]
                    },
                ],
            ])
        }

        for structure in visibleEngineeringStructures(in: project) {
            for pier in structure.bridgePiers {
                features.append([
                    "type": "Feature",
                    "id": pier.id,
                    "properties": [
                        "featureType": "bridgePier",
                        "engineeringStructureID": structure.id,
                        "sourceRoadID": structure.sourceRoadID.uuidString,
                        "chainageMeters": pier.chainageMeters,
                        "groundElevationMeters": pier.groundElevationMeters,
                        "deckElevationMeters": pier.deckElevationMeters,
                        "heightMeters": pier.heightMeters,
                    ],
                    "geometry": [
                        "type": "Point",
                        "coordinates": [
                            pier.point.x * metersPerPoint,
                            pier.point.y * metersPerPoint,
                        ],
                    ],
                ])
            }
            for portal in structure.tunnelPortals {
                var properties: [String: Any] = [
                    "featureType": "tunnelPortal",
                    "engineeringStructureID": structure.id,
                    "sourceRoadID": structure.sourceRoadID.uuidString,
                    "role": portal.role.rawValue,
                    "chainageMeters": portal.chainageMeters,
                    "groundElevationMeters": portal.groundElevationMeters,
                    "axisElevationMeters": portal.structureElevationMeters,
                    "tangent": [portal.tangent.x, portal.tangent.y],
                ]
                if let approachGrade = portal.approachGrade {
                    properties["approachGrade"] = approachGrade
                }
                features.append([
                    "type": "Feature",
                    "id": portal.id,
                    "properties": properties,
                    "geometry": [
                        "type": "Point",
                        "coordinates": [
                            portal.point.x * metersPerPoint,
                            portal.point.y * metersPerPoint,
                        ],
                    ],
                ])
            }
        }

        let object: [String: Any] = [
            "type": "FeatureCollection",
            "name": project.name,
            "coordinateSystem": "PhoenixValley local Cartesian metres; origin top-left",
            "metersPerCanvasPoint": metersPerPoint,
            "bbox": [
                0.0,
                0.0,
                project.mapScale.widthMeters,
                project.mapScale.heightMeters,
            ],
            "features": features,
        ]
        return try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
    }
}

private struct ExportColor: Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double = 1

    func setFill(in context: CGContext) {
        context.setFillColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    func setStroke(in context: CGContext) {
        context.setStrokeColor(
            red: red,
            green: green,
            blue: blue,
            alpha: alpha
        )
    }

    var hex: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    var redByte: UInt8 { componentByte(red) }
    var greenByte: UInt8 { componentByte(green) }
    var blueByte: UInt8 { componentByte(blue) }
    var alphaByte: UInt8 { componentByte(alpha) }

    func mixed(with other: ExportColor, amount: Double) -> ExportColor {
        let t = min(1, max(0, amount))
        return ExportColor(
            red: red + (other.red - red) * t,
            green: green + (other.green - green) * t,
            blue: blue + (other.blue - blue) * t,
            alpha: alpha + (other.alpha - alpha) * t
        )
    }

    private func componentByte(_ value: Double) -> UInt8 {
        UInt8(clamping: Int((min(1, max(0, value)) * 255).rounded()))
    }

    func opacityAttribute(_ name: String) -> String {
        guard alpha < 0.999 else { return "" }
        return #" \#(name)-opacity="\#(MapExporter.svgNumber(alpha))""#
    }
}

private struct ExportPalette: Sendable {
    let water: ExportColor
    let plain: ExportColor
    let lowland: ExportColor
    let hill: ExportColor
    let mountain: ExportColor
    let grid: ExportColor
    let contour: ExportColor
    let shoreline: ExportColor
    let roadCasing: ExportColor
    let motorway: ExportColor
    let arterial: ExportColor
    let street: ExportColor
    let railway: ExportColor
    let bridge = ExportColor(red: 0.2, green: 0.72, blue: 0.83, alpha: 0.82)

    init(theme: MapTheme) {
        switch theme {
        case .topographic:
            self.init(
                water: .init(red: 0.69, green: 0.84, blue: 0.9),
                plain: .init(red: 0.82, green: 0.88, blue: 0.67),
                lowland: .init(red: 0.67, green: 0.8, blue: 0.53),
                hill: .init(red: 0.77, green: 0.69, blue: 0.47),
                mountain: .init(red: 0.61, green: 0.5, blue: 0.37),
                grid: .init(red: 0, green: 0, blue: 0, alpha: 0.045),
                contour: .init(red: 0.36, green: 0.27, blue: 0.18, alpha: 0.28),
                shoreline: .init(red: 0.23, green: 0.38, blue: 0.42, alpha: 0.5),
                roadCasing: .init(red: 0.18, green: 0.25, blue: 0.22),
                motorway: .init(red: 1, green: 1, blue: 1),
                arterial: .init(red: 0.96, green: 0.83, blue: 0.28),
                street: .init(red: 0.86, green: 0.93, blue: 0.82),
                railway: .init(red: 0.28, green: 0.2, blue: 0.16)
            )
        case .planning:
            self.init(
                water: .init(red: 0.86, green: 0.92, blue: 0.94),
                plain: .init(red: 0.96, green: 0.95, blue: 0.89),
                lowland: .init(red: 0.9, green: 0.91, blue: 0.8),
                hill: .init(red: 0.87, green: 0.82, blue: 0.68),
                mountain: .init(red: 0.76, green: 0.7, blue: 0.62),
                grid: .init(red: 0, green: 0, blue: 0, alpha: 0.05),
                contour: .init(red: 0.38, green: 0.31, blue: 0.23, alpha: 0.22),
                shoreline: .init(red: 0, green: 0, blue: 0, alpha: 0.2),
                roadCasing: .init(red: 1, green: 1, blue: 1),
                motorway: .init(red: 0.18, green: 0.2, blue: 0.21),
                arterial: .init(red: 0.32, green: 0.36, blue: 0.37),
                street: .init(red: 0.72, green: 0.75, blue: 0.73),
                railway: .init(red: 0.35, green: 0.25, blue: 0.2)
            )
        case .ink:
            self.init(
                water: .init(red: 0.93, green: 0.93, blue: 0.93),
                plain: .init(red: 0.985, green: 0.985, blue: 0.985),
                lowland: .init(red: 0.955, green: 0.955, blue: 0.955),
                hill: .init(red: 0.92, green: 0.92, blue: 0.92),
                mountain: .init(red: 0.86, green: 0.86, blue: 0.86),
                grid: .init(red: 0, green: 0, blue: 0, alpha: 0.04),
                contour: .init(red: 0, green: 0, blue: 0, alpha: 0.16),
                shoreline: .init(red: 0, green: 0, blue: 0, alpha: 0.28),
                roadCasing: .init(red: 1, green: 1, blue: 1),
                motorway: .init(red: 0.08, green: 0.08, blue: 0.08),
                arterial: .init(red: 0.2, green: 0.2, blue: 0.2),
                street: .init(red: 0.48, green: 0.48, blue: 0.48),
                railway: .init(red: 0, green: 0, blue: 0)
            )
        case .coastal:
            self.init(
                water: .init(red: 0.49, green: 0.77, blue: 0.86),
                plain: .init(red: 0.96, green: 0.91, blue: 0.76),
                lowland: .init(red: 0.84, green: 0.87, blue: 0.67),
                hill: .init(red: 0.78, green: 0.72, blue: 0.54),
                mountain: .init(red: 0.57, green: 0.48, blue: 0.4),
                grid: .init(red: 1, green: 1, blue: 1, alpha: 0.14),
                contour: .init(red: 0.22, green: 0.38, blue: 0.4, alpha: 0.25),
                shoreline: .init(red: 0.12, green: 0.34, blue: 0.42, alpha: 0.55),
                roadCasing: .init(red: 0.95, green: 0.92, blue: 0.78),
                motorway: .init(red: 0.16, green: 0.3, blue: 0.36),
                arterial: .init(red: 0.93, green: 0.52, blue: 0.22),
                street: .init(red: 0.96, green: 0.88, blue: 0.62),
                railway: .init(red: 0.35, green: 0.22, blue: 0.17)
            )
        case .midnight:
            self.init(
                water: .init(red: 0.05, green: 0.1, blue: 0.17),
                plain: .init(red: 0.11, green: 0.16, blue: 0.2),
                lowland: .init(red: 0.14, green: 0.22, blue: 0.23),
                hill: .init(red: 0.2, green: 0.27, blue: 0.25),
                mountain: .init(red: 0.3, green: 0.32, blue: 0.28),
                grid: .init(red: 1, green: 1, blue: 1, alpha: 0.08),
                contour: .init(red: 0.54, green: 0.72, blue: 0.68, alpha: 0.28),
                shoreline: .init(red: 0.48, green: 0.7, blue: 0.78, alpha: 0.45),
                roadCasing: .init(red: 0.04, green: 0.08, blue: 0.13),
                motorway: .init(red: 0.68, green: 0.84, blue: 0.95),
                arterial: .init(red: 0.98, green: 0.7, blue: 0.31),
                street: .init(red: 0.55, green: 0.72, blue: 0.72),
                railway: .init(red: 0.78, green: 0.55, blue: 0.84)
            )
        case .forest:
            self.init(
                water: .init(red: 0.43, green: 0.68, blue: 0.69),
                plain: .init(red: 0.78, green: 0.84, blue: 0.69),
                lowland: .init(red: 0.58, green: 0.72, blue: 0.5),
                hill: .init(red: 0.42, green: 0.58, blue: 0.38),
                mountain: .init(red: 0.3, green: 0.4, blue: 0.31),
                grid: .init(red: 0, green: 0, blue: 0, alpha: 0.05),
                contour: .init(red: 0.16, green: 0.3, blue: 0.18, alpha: 0.3),
                shoreline: .init(red: 0.12, green: 0.3, blue: 0.28, alpha: 0.5),
                roadCasing: .init(red: 0.7, green: 0.78, blue: 0.58),
                motorway: .init(red: 0.23, green: 0.3, blue: 0.25),
                arterial: .init(red: 0.77, green: 0.55, blue: 0.21),
                street: .init(red: 0.87, green: 0.82, blue: 0.58),
                railway: .init(red: 0.3, green: 0.19, blue: 0.14)
            )
        }
    }

    private init(
        water: ExportColor,
        plain: ExportColor,
        lowland: ExportColor,
        hill: ExportColor,
        mountain: ExportColor,
        grid: ExportColor,
        contour: ExportColor,
        shoreline: ExportColor,
        roadCasing: ExportColor,
        motorway: ExportColor,
        arterial: ExportColor,
        street: ExportColor,
        railway: ExportColor
    ) {
        self.water = water
        self.plain = plain
        self.lowland = lowland
        self.hill = hill
        self.mountain = mountain
        self.grid = grid
        self.contour = contour
        self.shoreline = shoreline
        self.roadCasing = roadCasing
        self.motorway = motorway
        self.arterial = arterial
        self.street = street
        self.railway = railway
    }

    func landColor(for elevation: Double) -> ExportColor {
        switch elevation {
        case ..<0.3:
            plain
        case ..<0.46:
            plain.mixed(
                with: lowland,
                amount: (elevation - 0.3) / 0.16
            )
        case ..<0.62:
            lowland.mixed(
                with: hill,
                amount: (elevation - 0.46) / 0.16
            )
        case ..<0.8:
            hill.mixed(
                with: mountain,
                amount: (elevation - 0.62) / 0.18
            )
        default:
            mountain
        }
    }

    func roadColor(for road: RoadSegment) -> ExportColor {
        if road.structure == .bridge { return bridge }
        let color: ExportColor = switch road.kind {
        case .motorway: motorway
        case .arterial: arterial
        case .street: street
        case .railway: railway
        }
        if road.structure == .tunnel {
            return ExportColor(
                red: color.red,
                green: color.green,
                blue: color.blue,
                alpha: color.alpha * 0.58
            )
        }
        return color
    }
}

private extension RoadKind {
    var exportWidth: Double {
        switch self {
        case .motorway: 10
        case .arterial: 7
        case .street: 3.5
        case .railway: 4
        }
    }
}
