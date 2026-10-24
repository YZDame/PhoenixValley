import CoreGraphics
import CoreText
import Foundation

/// The same geographic backdrop is used on screen and in exported documents.
public enum CartographicRenderer {
    public static func featureColor(_ kind: GeoMapFeatureKind, dark: Bool = false) -> CGColor {
        let rgb: (Double, Double, Double) = switch kind {
        case .water: dark ? (0.10, 0.23, 0.30) : (0.68, 0.83, 0.89)
        case .forest: dark ? (0.16, 0.28, 0.23) : (0.75, 0.83, 0.70)
        case .park: dark ? (0.20, 0.32, 0.25) : (0.83, 0.89, 0.76)
        case .building: dark ? (0.30, 0.31, 0.30) : (0.86, 0.84, 0.80)
        }
        return CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
    }

    public static func draw(_ map: RealWorldMap, theme: MapTheme, showsTerrain: Bool, showsHydrology: Bool, in context: CGContext) {
        let dark = theme == .midnight
        context.saveGState()
        defer { context.restoreGState() }
        let canvas = CGRect(x: 0, y: 0, width: 1600, height: 1200)
        context.clip(to: canvas)
        context.setFillColor(dark ? CGColor(red: 0.13, green: 0.17, blue: 0.19, alpha: 1) : CGColor(red: 0.95, green: 0.94, blue: 0.91, alpha: 1))
        context.fill(canvas)
        guard showsTerrain else { return }
        // Large land-use polygons precede water and building footprints.
        for kind in [GeoMapFeatureKind.park, .forest, .water, .building] {
            if kind == .water && !showsHydrology { continue }
            for feature in map.features where feature.kind == kind && feature.points.count >= 3 {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: feature.points[0].x, y: feature.points[0].y))
                for point in feature.points.dropFirst() { path.addLine(to: CGPoint(x: point.x, y: point.y)) }
                path.closeSubpath()
                let color = featureColor(kind, dark: dark)
                context.setFillColor(color)
                context.addPath(path)
                context.fillPath()
                context.setStrokeColor(CGColor(gray: dark ? 1 : 0.25, alpha: kind == .building ? 0.16 : 0.10))
                context.setLineWidth(kind == .building ? 0.65 : 0.8)
                context.addPath(path)
                context.strokePath()
            }
        }
        if let elevation = map.elevation {
            drawRelief(width: elevation.width, height: elevation.height, meters: elevation.meters,
                       widthMeters: map.bounds.metersPerPoint * 1600,
                       heightMeters: map.bounds.metersPerPoint * 1200, in: context)
        }
    }

    public static func drawRelief(_ terrain: TerrainLayout, mapScale: MapScale, in context: CGContext) {
        guard terrain.hasElevationData else { return }
        let scale = RoadEngineeringConfiguration().elevationScaleMeters
        let meters = terrain.elevations.map { Optional(Double($0) / Double(UInt16.max) * scale) }
        drawRelief(width: terrain.gridWidth, height: terrain.gridHeight, meters: meters,
                   widthMeters: mapScale.widthMeters, heightMeters: mapScale.heightMeters, in: context)
    }

    /// North-west illumination from measured gradients; missing DEM cells remain unshaded.
    public static func drawRelief(width: Int, height: Int, meters: [Double?], widthMeters: Double, heightMeters: Double, in context: CGContext) {
        guard width >= 2, height >= 2, meters.count == width * height,
              widthMeters > 0, heightMeters > 0 else { return }
        let dx = widthMeters / Double(width - 1), dy = heightMeters / Double(height - 1)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            for column in 0..<width {
                let left = max(0, column - 1), right = min(width - 1, column + 1)
                let top = max(0, row - 1), bottom = min(height - 1, row + 1)
                guard let z = meters[row * width + column], z.isFinite,
                      let zl = meters[row * width + left], let zr = meters[row * width + right],
                      let zt = meters[top * width + column], let zb = meters[bottom * width + column] else { continue }
                let gx = (zr-zl) / (Double(right-left)*dx)
                let gy = (zb-zt) / (Double(bottom-top)*dy)
                let light = (-gx * -0.5 - gy * -0.5 + 0.7071) / sqrt(gx*gx + gy*gy + 1)
                let delta = light - 0.7071
                let alpha = min(0.18, abs(delta) * 0.26)
                guard alpha.isFinite, alpha > 0.003 else { continue }
                let alphaByte = UInt8((alpha * 255).rounded())
                let index = (row * width + column) * 4
                // Premultiplied RGBA: lit cells are translucent white.
                let value: UInt8 = delta > 0 ? alphaByte : 0
                pixels[index] = value; pixels[index + 1] = value; pixels[index + 2] = value
                pixels[index + 3] = alphaByte
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.interpolationQuality = .high
        context.translateBy(x: 0, y: 1200)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1600, height: 1200))
    }

    public static func drawAttribution(_ text: String, in context: CGContext, canvasSize: CGSize) {
        guard !text.isEmpty else { return }
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.18, alpha: 1)
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = min(canvasSize.width - 32, ceil(CTLineGetTypographicBounds(line, nil, nil, nil)) + 16)
        let box = CGRect(x: 16, y: canvasSize.height - 31, width: max(0, width), height: 23)
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(CGColor(gray: 1, alpha: 0.90))
        context.fill(box)
        context.clip(to: box)
        context.translateBy(x: box.minX + 8, y: box.maxY - 7)
        context.scaleBy(x: 1, y: -1)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
    }
}
