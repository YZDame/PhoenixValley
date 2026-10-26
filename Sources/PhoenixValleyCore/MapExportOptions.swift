import Foundation

public struct MapExportViewport: Equatable, Sendable {
    public var camera: CanvasViewport
    public var width: Double
    public var height: Double
    public init(camera: CanvasViewport, width: Double, height: Double) {
        self.camera = camera
        self.width = min(4096, max(64, width.isFinite ? width : 1600))
        self.height = min(4096, max(64, height.isFinite ? height : 1200))
    }
}

public struct MapExportOptions: Equatable, Sendable {
    /// nil exports the entire design world; otherwise exports the camera view.
    public var viewport: MapExportViewport?
    public var showsTitle: Bool
    public var showsScale: Bool
    public var showsInformation: Bool
    public var showsAttribution: Bool
    public init(viewport: MapExportViewport? = nil, showsTitle: Bool = true, showsScale: Bool = true,
                showsInformation: Bool = false, showsAttribution: Bool = true) {
        self.viewport = viewport; self.showsTitle = showsTitle; self.showsScale = showsScale
        self.showsInformation = showsInformation; self.showsAttribution = showsAttribution
    }
}
