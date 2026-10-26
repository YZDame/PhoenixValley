import CoreGraphics
import Foundation

public struct MapColor: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 255)/255
        green = Double((hex >> 8) & 255)/255
        blue = Double(hex & 255)/255
        self.alpha = alpha
    }
    public var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
    public var hex: String { String(format: "#%02X%02X%02X", Int((red*255).rounded()), Int((green*255).rounded()), Int((blue*255).rounded())) }
}

public struct MapThemePalette: Sendable {
    public let water, plain, lowland, hill, mountain: MapColor
    public let grid, contour, shoreline, roadCasing: MapColor
    public let motorway, arterial, street, railway: MapColor

    init(_ water: UInt32, _ plain: UInt32, _ lowland: UInt32, _ hill: UInt32, _ mountain: UInt32,
         _ ink: UInt32, _ casing: UInt32, _ motorway: UInt32, _ arterial: UInt32, _ street: UInt32, _ railway: UInt32) {
        self.water = MapColor(water); self.plain = MapColor(plain); self.lowland = MapColor(lowland)
        self.hill = MapColor(hill); self.mountain = MapColor(mountain)
        grid = MapColor(ink, alpha: 0.055); contour = MapColor(ink, alpha: 0.23)
        shoreline = MapColor(ink, alpha: 0.5); roadCasing = MapColor(casing)
        self.motorway = MapColor(motorway); self.arterial = MapColor(arterial)
        self.street = MapColor(street); self.railway = MapColor(railway)
    }
}

public extension MapTheme {
    var palette: MapThemePalette {
        switch self {
        case .topographic:
            .init(0xBDD9DA, 0xF1F2E8, 0xDEE6D1, 0xC9D5BB, 0xA8B99F,
                  0x536D64, 0x859487, 0xC99665, 0xE6C39A, 0xFFFDF5, 0x566B61)
        case .planning:
            .init(0xD0E3E5, 0xF7F3EA, 0xEAEBDD, 0xDDDCC7, 0xC4C4AF,
                  0x77796B, 0xA1A295, 0xC98C66, 0xE4BB8D, 0xFFFDF7, 0x636F6D)
        case .ink:
            .init(0xE0E6E6, 0xF9FAF7, 0xEEF0EB, 0xDDE2DB, 0xC5CEC6,
                  0x536160, 0xFCFDF9, 0x293D41, 0x637B7D, 0x91A4A3, 0x35464C)
        case .coastal:
            .init(0xA8CDD6, 0xFAF3E5, 0xE9E7CB, 0xD5D5B6, 0xB9C0A9,
                  0x557C84, 0xEBE2CB, 0x396D7B, 0xCD946F, 0xFFFCF1, 0x526A72)
        case .midnight:
            .init(0x142B3C, 0x223B45, 0x2C494E, 0x385957, 0x496A61,
                  0xADC9C3, 0x132C36, 0xE7BA85, 0xA6CCC9, 0x6B9B9D, 0xBCABCF)
        case .forest:
            .init(0xB4CFCA, 0xEEF0E3, 0xD9E2CA, 0xBECEB1, 0x95AE91,
                  0x536D5E, 0x9EAF97, 0x6A8376, 0xD2AF7D, 0xFEFCED, 0x596B5F)
        }
    }
    var detail: String {
        switch self {
        case .topographic: "雾青水域 · 灰绿山脊 · 暖白道路"
        case .planning: "细腻绢纸 · 陶土主路 · 浅金支线"
        case .ink: "冷白纸面 · 石墨线条 · 克制层次"
        case .coastal: "浅湾海蓝 · 沙色陆地 · 珊瑚暖线"
        case .midnight: "深蓝底色 · 柔金干道 · 青灰支路"
        case .forest: "鼠尾草绿 · 苔色山脊 · 奶油白路面"
        }
    }
}
