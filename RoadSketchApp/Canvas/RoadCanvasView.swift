import RoadSketchCore
import SwiftUI
import UIKit

struct RoadCanvasRepresentable: UIViewRepresentable {
    let project: RoadProject
    let selectedKind: RoadKind
    let selectedLevel: RoadLevel
    let isErasing: Bool
    let onStrokeFinished: ([RoadPoint]) -> Void
    let onEraseFinished: (Set<UUID>) -> Void

    func makeUIView(context: Context) -> RoadCanvasView {
        let view = RoadCanvasView()
        view.onStrokeFinished = onStrokeFinished
        view.onEraseFinished = onEraseFinished
        return view
    }

    func updateUIView(_ view: RoadCanvasView, context: Context) {
        view.terrain = project.terrain
        view.roads = project.roads
        view.theme = project.theme
        view.showsContours = project.showsContours
        view.showsGrid = project.showsGrid
        view.selectedKind = selectedKind
        view.selectedLevel = selectedLevel
        view.isErasing = isErasing
        view.onStrokeFinished = onStrokeFinished
        view.onEraseFinished = onEraseFinished
        view.setNeedsDisplay()
    }
}

final class RoadCanvasView: UIView, UIGestureRecognizerDelegate {
    var terrain = TerrainGenerator.generate(seed: 1) {
        didSet { if oldValue != terrain { terrainImage = nil } }
    }
    var roads: [RoadSegment] = []
    var selectedKind: RoadKind = .arterial
    var selectedLevel: RoadLevel = .ground
    var isErasing = false
    var theme: MapTheme = .planning {
        didSet { if oldValue != theme { terrainImage = nil } }
    }
    var showsContours = true {
        didSet { if oldValue != showsContours { terrainImage = nil } }
    }
    var showsGrid = true {
        didSet { if oldValue != showsGrid { terrainImage = nil } }
    }
    var onStrokeFinished: (([RoadPoint]) -> Void)?
    var onEraseFinished: ((Set<UUID>) -> Void)?

    private var activeStroke: [RoadPoint] = []
    private var activeEraseIDs: Set<UUID> = []
    private var zoomScale: CGFloat = 1
    private var translation: CGPoint = .zero
    private var hasPositionedInitialMap = false
    private var terrainImage: UIImage?

    #if targetEnvironment(simulator)
    private let allowsFingerDrawing = true
    #else
    private let allowsFingerDrawing = false
    #endif

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .systemBackground

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.minimumNumberOfTouches = allowsFingerDrawing ? 2 : 1
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = false
        pan.delegate = self
        addGestureRecognizer(pan)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.cancelsTouchesInView = false
        pinch.delegate = self
        addGestureRecognizer(pinch)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !hasPositionedInitialMap, bounds.width > 0, bounds.height > 0 else { return }
        zoomScale = min(bounds.width / 1600, bounds.height / 1200) * 0.92
        translation = CGPoint(
            x: bounds.midX - 800 * zoomScale,
            y: bounds.midY - 600 * zoomScale
        )
        hasPositionedInitialMap = true
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let palette = theme.terrainPalette
        context.setFillColor(palette.water.cgColor)
        context.fill(bounds)

        context.saveGState()
        context.translateBy(x: translation.x, y: translation.y)
        context.scaleBy(x: zoomScale, y: zoomScale)
        drawTerrain(in: context)
        drawRoads(in: context)
        drawActiveStroke(in: context)
        context.restoreGState()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, shouldDraw(with: touch, touches: touches) else { return }
        activeStroke = [worldPoint(for: touch.location(in: self))]
        if isErasing, let point = activeStroke.first {
            collectRoadsToErase(near: point)
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, shouldDraw(with: touch, touches: touches) else { return }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        activeStroke.append(contentsOf: samples.map { worldPoint(for: $0.location(in: self)) })
        if isErasing {
            for sample in activeStroke.suffix(samples.count) {
                collectRoadsToErase(near: sample)
            }
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, shouldDraw(with: touch, touches: touches) else { return }
        activeStroke.append(worldPoint(for: touch.location(in: self)))
        let completedStroke = activeStroke
        activeStroke.removeAll(keepingCapacity: true)
        setNeedsDisplay()
        if isErasing {
            let erased = activeEraseIDs
            activeEraseIDs.removeAll(keepingCapacity: true)
            onEraseFinished?(erased)
        } else {
            onStrokeFinished?(completedStroke)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeStroke.removeAll(keepingCapacity: true)
        activeEraseIDs.removeAll(keepingCapacity: true)
        setNeedsDisplay()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let delta = recognizer.translation(in: self)
        translation.x += delta.x
        translation.y += delta.y
        recognizer.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard recognizer.numberOfTouches >= 2 else { return }
        let anchor = recognizer.location(in: self)
        let worldAtAnchor = worldPoint(for: anchor)
        let nextScale = min(4, max(0.2, zoomScale * recognizer.scale))
        zoomScale = nextScale
        translation = CGPoint(
            x: anchor.x - worldAtAnchor.x * nextScale,
            y: anchor.y - worldAtAnchor.y * nextScale
        )
        recognizer.scale = 1
        setNeedsDisplay()
    }

    private func shouldDraw(with touch: UITouch, touches: Set<UITouch>) -> Bool {
        touch.type == .pencil || (allowsFingerDrawing && touch.type == .direct && touches.count == 1)
    }

    private func worldPoint(for screenPoint: CGPoint) -> RoadPoint {
        RoadPoint(
            x: Double((screenPoint.x - translation.x) / zoomScale),
            y: Double((screenPoint.y - translation.y) / zoomScale)
        )
    }

    private func drawTerrain(in context: CGContext) {
        let image: UIImage
        if let cached = terrainImage {
            image = cached
        } else {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            image = UIGraphicsImageRenderer(
                size: CGSize(width: 1600, height: 1200),
                format: format
            ).image { renderer in
                drawTerrainContent(in: renderer.cgContext)
            }
            terrainImage = image
        }
        image.draw(in: CGRect(x: 0, y: 0, width: 1600, height: 1200))
    }

    private func drawTerrainContent(in context: CGContext) {
        let palette = theme.terrainPalette
        context.setFillColor(palette.water.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))

        guard let first = terrain.shoreline.first else { return }
        let shorePath = CGMutablePath()
        let last = terrain.shoreline[terrain.shoreline.count - 1]
        shorePath.move(to: midpoint(last, first))
        for index in terrain.shoreline.indices {
            let current = terrain.shoreline[index]
            let next = terrain.shoreline[(index + 1) % terrain.shoreline.count]
            shorePath.addQuadCurve(to: midpoint(current, next), control: current.cgPoint)
        }
        shorePath.closeSubpath()

        context.setFillColor(palette.plain.cgColor)
        context.addPath(shorePath)
        context.fillPath()

        context.saveGState()
        context.addPath(shorePath)
        context.clip()
        drawElevationBands(in: context, palette: palette)
        if showsGrid {
            drawGrid(in: context, color: palette.grid)
        }
        if showsContours {
            drawContours(in: context, color: palette.contour)
        }
        context.restoreGState()

        context.setStrokeColor(palette.shoreline.cgColor)
        context.setLineWidth(1.2)
        context.addPath(shorePath)
        context.strokePath()
    }

    private func drawElevationBands(in context: CGContext, palette: TerrainPalette) {
        guard terrain.hasElevationData else { return }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let elevationImage = UIGraphicsImageRenderer(
            size: CGSize(width: terrain.gridWidth, height: terrain.gridHeight),
            format: format
        ).image { renderer in
            for row in 0..<terrain.gridHeight {
                for column in 0..<terrain.gridWidth {
                    let value = Double(terrain.elevations[row * terrain.gridWidth + column])
                        / Double(UInt16.max)
                    renderer.cgContext.setFillColor(palette.color(for: value).cgColor)
                    renderer.cgContext.fill(CGRect(x: column, y: row, width: 1, height: 1))
                }
            }
        }

        context.saveGState()
        context.interpolationQuality = .high
        elevationImage.draw(in: CGRect(x: 0, y: 0, width: 1600, height: 1200))
        context.restoreGState()
    }

    private func drawGrid(in context: CGContext, color: UIColor) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.8)
        for x in stride(from: 80.0, through: 1520.0, by: 80.0) {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: 1200))
        }
        for y in stride(from: 40.0, through: 1160.0, by: 80.0) {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: 1600, y: y))
        }
        context.strokePath()
    }

    private func drawContours(in context: CGContext, color: UIColor) {
        guard terrain.hasElevationData else { return }
        let cellWidth = 1600 / Double(terrain.gridWidth - 1)
        let cellHeight = 1200 / Double(terrain.gridHeight - 1)
        context.setStrokeColor(color.cgColor)
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
                        RoadPoint(x: x, y: y + cellHeight)
                    ]
                    let values = corners.map { terrain.normalizedElevation(at: $0) }
                    var intersections: [CGPoint] = []

                    for edge in 0..<4 {
                        let next = (edge + 1) % 4
                        let firstValue = values[edge]
                        let secondValue = values[next]
                        guard (firstValue < threshold) != (secondValue < threshold) else { continue }
                        let amount = (threshold - firstValue) / (secondValue - firstValue)
                        let start = corners[edge]
                        let end = corners[next]
                        intersections.append(
                            CGPoint(
                                x: start.x + (end.x - start.x) * amount,
                                y: start.y + (end.y - start.y) * amount
                            )
                        )
                    }

                    for pairStart in stride(from: 0, to: intersections.count - 1, by: 2) {
                        context.move(to: intersections[pairStart])
                        context.addLine(to: intersections[pairStart + 1])
                    }
                }
            }
            context.strokePath()
        }
    }

    private func drawRoads(in context: CGContext) {
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
                draw(road: road, in: context)
            }
        }
    }

    private func draw(road: RoadSegment, in context: CGContext) {
        guard let first = road.points.first else { return }
        let path = CGMutablePath()
        path.move(to: first.cgPoint)
        for point in road.points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let roadColor = activeEraseIDs.contains(road.id)
            ? UIColor.systemRed.withAlphaComponent(0.78)
            : road.kind.uiColor(for: road.level)
        context.setStrokeColor(roadColor.cgColor)
        context.setLineWidth(road.kind.screenWidth / zoomScale)
        if road.kind == .railway || road.level == .tunnel {
            context.setLineDash(phase: 0, lengths: [8 / zoomScale, 5 / zoomScale])
        }
        if road.level == .elevated {
            context.setShadow(
                offset: CGSize(width: 0, height: 2 / zoomScale),
                blur: 2 / zoomScale,
                color: UIColor.black.withAlphaComponent(0.22).cgColor
            )
        }
        context.addPath(path)
        context.strokePath()
        context.restoreGState()
    }

    private func drawActiveStroke(in context: CGContext) {
        guard let first = activeStroke.first else { return }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(
            isErasing
                ? UIColor.systemRed.withAlphaComponent(0.35).cgColor
                : selectedKind.uiColor(for: selectedLevel).withAlphaComponent(0.55).cgColor
        )
        context.setLineWidth((isErasing ? 22 : selectedKind.screenWidth) / zoomScale)
        context.move(to: first.cgPoint)
        for point in activeStroke.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()
        context.restoreGState()
    }

    private func collectRoadsToErase(near point: RoadPoint) {
        let hitRadius = Double(18 / zoomScale)
        for road in roads where !activeEraseIDs.contains(road.id) {
            guard road.points.count >= 2 else { continue }
            for index in 0..<(road.points.count - 1) {
                if distance(from: point, toSegmentFrom: road.points[index], to: road.points[index + 1]) <= hitRadius {
                    activeEraseIDs.insert(road.id)
                    break
                }
            }
        }
    }

    private func distance(from point: RoadPoint, toSegmentFrom start: RoadPoint, to end: RoadPoint) -> Double {
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        let lengthSquared = deltaX * deltaX + deltaY * deltaY
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let projection = ((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) / lengthSquared
        let amount = min(1, max(0, projection))
        let closestX = start.x + deltaX * amount
        let closestY = start.y + deltaY * amount
        return hypot(point.x - closestX, point.y - closestY)
    }

    private func midpoint(_ first: RoadPoint, _ second: RoadPoint) -> CGPoint {
        CGPoint(x: (first.x + second.x) / 2, y: (first.y + second.y) / 2)
    }
}

private struct TerrainPalette {
    let water: UIColor
    let plain: UIColor
    let lowland: UIColor
    let hill: UIColor
    let mountain: UIColor
    let grid: UIColor
    let contour: UIColor
    let shoreline: UIColor

    func color(for elevation: Double) -> UIColor {
        switch elevation {
        case ..<0.3:
            plain
        case ..<0.46:
            plain.mixed(with: lowland, amount: (elevation - 0.3) / 0.16)
        case ..<0.62:
            lowland.mixed(with: hill, amount: (elevation - 0.46) / 0.16)
        case ..<0.8:
            hill.mixed(with: mountain, amount: (elevation - 0.62) / 0.18)
        default:
            mountain
        }
    }
}

private extension UIColor {
    func mixed(with other: UIColor, amount: Double) -> UIColor {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        var otherRed: CGFloat = 0
        var otherGreen: CGFloat = 0
        var otherBlue: CGFloat = 0
        var otherAlpha: CGFloat = 0
        guard getRed(&red, green: &green, blue: &blue, alpha: &alpha),
              other.getRed(&otherRed, green: &otherGreen, blue: &otherBlue, alpha: &otherAlpha)
        else { return self }

        let fraction = CGFloat(min(1, max(0, amount)))
        return UIColor(
            red: red + (otherRed - red) * fraction,
            green: green + (otherGreen - green) * fraction,
            blue: blue + (otherBlue - blue) * fraction,
            alpha: alpha + (otherAlpha - alpha) * fraction
        )
    }
}

private extension MapTheme {
    var terrainPalette: TerrainPalette {
        switch self {
        case .topographic:
            TerrainPalette(
                water: UIColor(red: 0.69, green: 0.84, blue: 0.9, alpha: 1),
                plain: UIColor(red: 0.82, green: 0.88, blue: 0.67, alpha: 1),
                lowland: UIColor(red: 0.67, green: 0.8, blue: 0.53, alpha: 1),
                hill: UIColor(red: 0.77, green: 0.69, blue: 0.47, alpha: 1),
                mountain: UIColor(red: 0.61, green: 0.5, blue: 0.37, alpha: 1),
                grid: UIColor.black.withAlphaComponent(0.045),
                contour: UIColor(red: 0.36, green: 0.27, blue: 0.18, alpha: 0.28),
                shoreline: UIColor(red: 0.23, green: 0.38, blue: 0.42, alpha: 0.5)
            )
        case .planning:
            TerrainPalette(
                water: UIColor(red: 0.86, green: 0.92, blue: 0.94, alpha: 1),
                plain: UIColor(red: 0.96, green: 0.95, blue: 0.89, alpha: 1),
                lowland: UIColor(red: 0.9, green: 0.91, blue: 0.8, alpha: 1),
                hill: UIColor(red: 0.87, green: 0.82, blue: 0.68, alpha: 1),
                mountain: UIColor(red: 0.76, green: 0.7, blue: 0.62, alpha: 1),
                grid: UIColor.black.withAlphaComponent(0.05),
                contour: UIColor(red: 0.38, green: 0.31, blue: 0.23, alpha: 0.22),
                shoreline: UIColor.black.withAlphaComponent(0.2)
            )
        case .ink:
            TerrainPalette(
                water: UIColor(white: 0.93, alpha: 1),
                plain: UIColor(white: 0.985, alpha: 1),
                lowland: UIColor(white: 0.955, alpha: 1),
                hill: UIColor(white: 0.92, alpha: 1),
                mountain: UIColor(white: 0.86, alpha: 1),
                grid: UIColor.black.withAlphaComponent(0.04),
                contour: UIColor.black.withAlphaComponent(0.16),
                shoreline: UIColor.black.withAlphaComponent(0.28)
            )
        }
    }
}

private extension RoadPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension RoadKind {
    var screenWidth: CGFloat {
        switch self {
        case .motorway: 10
        case .arterial: 7
        case .street: 3.5
        case .railway: 4
        }
    }

    func uiColor(for level: RoadLevel) -> UIColor {
        let base: UIColor = switch self {
        case .motorway: UIColor(red: 0.16, green: 0.18, blue: 0.19, alpha: 1)
        case .arterial: UIColor(red: 0.28, green: 0.31, blue: 0.32, alpha: 1)
        case .street: UIColor(red: 0.48, green: 0.51, blue: 0.51, alpha: 1)
        case .railway: UIColor(red: 0.33, green: 0.25, blue: 0.20, alpha: 1)
        }
        return level == .tunnel ? base.withAlphaComponent(0.55) : base
    }
}
