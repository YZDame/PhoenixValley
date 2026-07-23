import AppIntents
import RoadSketchCore

enum IntentRoadKind: String, AppEnum {
    case motorway
    case arterial
    case street
    case railway

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "道路类型"

    static let caseDisplayRepresentations: [IntentRoadKind: DisplayRepresentation] = [
        .motorway: "高速公路",
        .arterial: "主干道",
        .street: "街道",
        .railway: "铁路",
    ]

    var roadKind: RoadKind {
        switch self {
        case .motorway: .motorway
        case .arterial: .arterial
        case .street: .street
        case .railway: .railway
        }
    }
}

struct OpenRoadCanvasIntent: AppIntent {
    static let title: LocalizedStringResource = "开始规划路网"
    static let description = IntentDescription("打开 RoadSketch，并选择一种道路开始绘制。")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "道路类型", default: .arterial)
    var roadKind: IntentRoadKind

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.openCanvas(roadKind: roadKind.roadKind)
        return .result()
    }
}

struct CreateRandomMapIntent: AppIntent {
    static let title: LocalizedStringResource = "创建随机地图"
    static let description = IntentDescription("生成一张新的随机地形地图并在 RoadSketch 中打开。")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        await AppIntentRouter.shared.createRandomMap()
        return .result()
    }
}

struct RoadSketchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRoadCanvasIntent(),
            phrases: [
                "在 \(.applicationName) 中规划路网",
                "用 \(.applicationName) 画道路",
            ],
            shortTitle: "规划路网",
            systemImageName: "point.topleft.down.to.point.bottomright.curvepath"
        )

        AppShortcut(
            intent: CreateRandomMapIntent(),
            phrases: [
                "用 \(.applicationName) 创建随机地图",
                "在 \(.applicationName) 中生成地形",
            ],
            shortTitle: "随机地图",
            systemImageName: "map"
        )
    }
}
