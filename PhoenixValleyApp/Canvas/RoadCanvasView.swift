import MapKit
import PhoenixValleyCore
import SwiftUI
import UIKit

struct RoadCanvasRepresentable: UIViewRepresentable {
    let project: RoadProject
    let onViewportChanged: (MapExportViewport) -> Void
    let allowsFingerDrawing: Bool
    let pendingRampPlan: RoadRampPlan?
    let pendingStructureReview: RoadStructureReviewRecord?
    let selectedKind: RoadKind
    let selectedLevel: RoadLevel
    let isErasing: Bool
    let eraserMode: RoadEraseMode
    let isSelecting: Bool
    let isEditingInterchange: Bool
    let isAwaitingRampDrawing: Bool
    let showsConstructionIssueOverlay: Bool
    let selectedInterchangeCrossingID: UUID?
    let selectedRampID: UUID?
    let selectedSourceRoadIDs: Set<UUID>
    var selectedStationID: UUID? = nil
    let onStrokeFinished: ([RoadPoint]) -> Void
    let onEraseFinished: (RoadEraseRequest) -> Void
    let onSelectionChanged: (Set<UUID>) -> Void
    let onSelectionMoved: (Set<UUID>, RoadPoint) -> Void
    let onControlPointMoved: (
        UUID,
        RoadPoint,
        RoadPoint,
        Double
    ) -> Void
    let onInterchangeCrossingSelected: (UUID?) -> Void
    let onRampSelected: (UUID?) -> Void
    var onStationSelected: ((UUID?) -> Void)? = nil

    func makeUIView(context: Context) -> RoadMapWorkspaceView {
        let workspace = RoadMapWorkspaceView()
        let view = workspace.canvas
        workspace.onViewportChanged = onViewportChanged
        view.onStrokeFinished = onStrokeFinished
        view.onEraseFinished = onEraseFinished
        view.onSelectionChanged = onSelectionChanged
        view.onSelectionMoved = onSelectionMoved
        view.onControlPointMoved = onControlPointMoved
        view.onInterchangeCrossingSelected = onInterchangeCrossingSelected
        view.onRampSelected = onRampSelected
        view.onStationSelected = onStationSelected
        return workspace
    }

    func updateUIView(_ workspace: RoadMapWorkspaceView, context: Context) {
        let view = workspace.canvas
        workspace.onViewportChanged = onViewportChanged
        view.allowsFingerDrawing = allowsFingerDrawing
        view.pendingRampPlan = pendingRampPlan
        let visibleRoads = project.roads.filter {
            project.layerVisibility.isVisible($0.kind)
        }
        let visibleSourceRoadIDs = Set(visibleRoads.map(\.sourceRoadID))
        let storedStructures = project.engineeringStructures.filter {
            visibleSourceRoadIDs.contains($0.sourceRoadID)
                && project.layerVisibility.isVisible($0.roadKind)
        }
        let storedSourceRoadIDs = Set(storedStructures.map(\.sourceRoadID))
        let inferredStructures = visibleRoads
            .filter {
                ($0.structure == .bridge || $0.structure == .tunnel)
                    && !storedSourceRoadIDs.contains($0.sourceRoadID)
            }
            .flatMap {
                RoadEngineeringPlanner.evaluate(
                    road: $0,
                    terrain: project.terrain,
                    mapScale: project.mapScale
                ).structures
            }
        view.displayProject(project.id)
        view.terrain = project.terrain
        view.realWorldMap = project.realWorldMap
        view.roads = visibleRoads
        let pendingSourceRoadIDs = Set(
            project.structureReviews
                .filter { $0.status == .pending }
                .map(\.plan.sourceRoadID)
        )
        view.constructionIssues = if showsConstructionIssueOverlay {
            RoadConstructionFeasibilityAnalyzer.evaluate(
                roads: visibleRoads.filter {
                    !pendingSourceRoadIDs.contains($0.sourceRoadID)
                },
                terrain: project.terrain,
                mapScale: project.mapScale
            ).issues
        } else {
            []
        }
        view.engineeringStructures = storedStructures + inferredStructures
        view.pendingStructureReview = pendingStructureReview.flatMap { review in
            visibleRoads.contains { $0.sourceRoadID == review.plan.sourceRoadID }
                ? review
                : nil
        }
        view.pendingEngineeringStructures = view.pendingStructureReview.map {
            RoadEngineeringPlanner.evaluate(
                plan: $0.plan,
                decisions: $0.decisions,
                terrain: project.terrain,
                mapScale: project.mapScale
            ).structures
        } ?? []
        view.theme = project.theme
        view.showsTerrain = project.layerVisibility.showsTerrain
        view.showsHydrology = project.layerVisibility.showsHydrology
        view.showsWatersheds = project.layerVisibility.showsWatersheds
        view.showsContours = project.showsContours
        view.showsGrid = project.showsGrid
        view.selectedKind = selectedKind
        view.selectedLevel = selectedLevel
        view.isErasing = isErasing
        view.eraserMode = eraserMode
        view.isSelecting = isSelecting
        view.isEditingInterchange = isEditingInterchange
        view.isAwaitingRampDrawing = isAwaitingRampDrawing
        view.interchanges = project.interchanges
        view.relations = project.roadNetwork.relations
        view.selectedInterchangeCrossingID = selectedInterchangeCrossingID
        view.selectedRampID = selectedRampID
        view.selectedSourceRoadIDs = selectedSourceRoadIDs
        view.railwayStations = project.railwayStations
        view.selectedStationID = selectedStationID
        view.referenceOverlay = project.referenceOverlay
        view.mapScale = project.mapScale
        view.accessibilityValue = [
            project.name,
            project.mapScale.accessibilityDescription,
            isSelecting ? "选择模式，已选 \(selectedSourceRoadIDs.count) 条" : nil,
            isEditingInterchange
                ? (isAwaitingRampDrawing ? "立交模式，正在绘制匝道" : "立交模式")
                : nil,
        ]
        .compactMap { $0 }
        .joined(separator: "，")
        view.onStrokeFinished = onStrokeFinished
        view.onEraseFinished = onEraseFinished
        view.onSelectionChanged = onSelectionChanged
        view.onSelectionMoved = onSelectionMoved
        view.onControlPointMoved = onControlPointMoved
        view.onInterchangeCrossingSelected = onInterchangeCrossingSelected
        view.onRampSelected = onRampSelected
        view.onStationSelected = onStationSelected
        workspace.update(project: project)
        view.refreshAccessibilityElements()
        view.setNeedsDisplay()
    }
}

final class RoadCanvasView: UIView, UIGestureRecognizerDelegate {
    private enum SelectionHit {
        case station(id: UUID)
        case controlPoint(sourceRoadID: UUID, point: RoadPoint)
        case selectedRoad(sourceRoadID: UUID)
        case unselectedRoad(sourceRoadID: UUID)
        case empty
    }

    private struct PendingSelection {
        var originScreenPoint: CGPoint
        var originCanvasPoint: RoadPoint
        var latestScreenPoint: CGPoint
        var hit: SelectionHit
        var isPencil: Bool
        var exceededDragThreshold: Bool
    }

    private enum SelectionInteraction {
        case idle
        case pending(PendingSelection)
        case marquee(origin: RoadPoint, current: RoadPoint)
        case translating(
            origin: RoadPoint,
            current: RoadPoint,
            sourceRoadIDs: Set<UUID>
        )
        case deforming(
            sourceRoadID: UUID,
            originalPoint: RoadPoint,
            current: RoadPoint,
            maximumDistanceMeters: Double
        )
    }

    private enum InterchangeHit {
        case crossing(UUID)
        case ramp(UUID)
        case empty
    }

    var terrain = TerrainGenerator.generate(seed: 1) {
        didSet { if oldValue != terrain { cachedTerrainImage = nil; elevationPaths = nil; waterPaths = nil } }
    }
    var realWorldMap: RealWorldMap? {
        didSet { if oldValue != realWorldMap { cachedTerrainImage = nil } }
    }
    var roads: [RoadSegment] = [] {
        didSet {
            guard oldValue != roads else { return }
            roadsByLevel = Dictionary(grouping: roads, by: \.level)
            updateRoadPathCache()
            setNeedsDisplay()
        }
    }
    private var roadsByLevel: [RoadLevel: [RoadSegment]] = [:]
    private var roadPathCache: [UUID: (segment: RoadSegment, path: CGPath)] = [:]

    var constructionIssues: [RoadConstructionIssue] = []
    var engineeringStructures: [RoadEngineeringStructure] = []
    var pendingStructureReview: RoadStructureReviewRecord?
    var pendingEngineeringStructures: [RoadEngineeringStructure] = []
    var interchanges: [RoadInterchange] = [] {
        didSet {
            guard oldValue != interchanges else { return }
            cachedRampSourceRoadIDs = Set(interchanges.flatMap(\.ramps).map(\.sourceRoadID))
            setNeedsDisplay()
        }
    }
    private var cachedRampSourceRoadIDs: Set<UUID> = []
    var relations: [RoadRelation] = []
    var selectedKind: RoadKind = .arterial
    var selectedLevel: RoadLevel = .ground
    var isErasing = false
    var eraserMode: RoadEraseMode = .wholeRoad
    var isSelecting = false {
        didSet {
            guard oldValue != isSelecting else { return }
            cancelContentInteraction()
            updatePanTouchCount()
            refreshAccessibilityElements()
        }
    }
    var isEditingInterchange = false {
        didSet {
            guard oldValue != isEditingInterchange else { return }
            cancelContentInteraction()
            updatePanTouchCount()
            refreshAccessibilityElements()
            setNeedsDisplay()
        }
    }
    var isAwaitingRampDrawing = false {
        didSet {
            guard oldValue != isAwaitingRampDrawing else { return }
            cancelContentInteraction()
            refreshAccessibilityElements()
            setNeedsDisplay()
        }
    }
    var selectedInterchangeCrossingID: UUID? {
        didSet {
            guard oldValue != selectedInterchangeCrossingID else { return }
            refreshAccessibilityElements()
            setNeedsDisplay()
        }
    }
    var selectedRampID: UUID? {
        didSet {
            guard oldValue != selectedRampID else { return }
            refreshAccessibilityElements()
            setNeedsDisplay()
        }
    }
    var selectedSourceRoadIDs: Set<UUID> = [] {
        didSet {
            guard oldValue != selectedSourceRoadIDs else { return }
            refreshAccessibilityElements()
            setNeedsDisplay()
        }
    }
    var mapScale: MapScale = .standard {
        didSet { if oldValue != mapScale { cachedTerrainImage = nil } }
    }
    var theme: MapTheme = .planning {
        didSet {
            if oldValue != theme {
                currentRoadPalette = theme.roadPalette
                currentTerrainPalette = theme.terrainPalette
                transitionTerrain()
            }
        }
    }
    private var currentRoadPalette: RoadPalette = MapTheme.planning.roadPalette
    private var currentTerrainPalette: TerrainPalette = MapTheme.planning.terrainPalette
    var showsTerrain = true
    var showsHydrology = true {
        didSet { if oldValue != showsHydrology { transitionTerrain() } }
    }
    var showsWatersheds = false {
        didSet { if oldValue != showsWatersheds { transitionTerrain() } }
    }
    var showsContours = true {
        didSet { if oldValue != showsContours { transitionTerrain() } }
    }
    var showsGrid = true {
        didSet { if oldValue != showsGrid { transitionTerrain() } }
    }
    var railwayStations: [RailwayStation] = [] {
        didSet {
            guard oldValue != railwayStations else { return }
            setNeedsDisplay()
        }
    }
    var selectedStationID: UUID? {
        didSet {
            guard oldValue != selectedStationID else { return }
            setNeedsDisplay()
        }
    }
    var referenceOverlay: ReferenceImageOverlay? {
        didSet {
            if referenceOverlay?.imageData != oldValue?.imageData {
                if let data = referenceOverlay?.imageData, let uiImage = UIImage(data: data) {
                    cachedOverlayImage = uiImage.cgImage
                } else {
                    cachedOverlayImage = nil
                }
            }
            setNeedsDisplay()
        }
    }
    private var cachedOverlayImage: CGImage?
    var onStrokeFinished: (([RoadPoint]) -> Void)?
    var onEraseFinished: ((RoadEraseRequest) -> Void)?
    var onSelectionChanged: ((Set<UUID>) -> Void)?
    var onSelectionMoved: ((Set<UUID>, RoadPoint) -> Void)?
    var onControlPointMoved: ((
        UUID,
        RoadPoint,
        RoadPoint,
        Double
    ) -> Void)?
    var onInterchangeCrossingSelected: ((UUID?) -> Void)?
    var onRampSelected: ((UUID?) -> Void)?
    var onStationSelected: ((UUID?) -> Void)?

    private var hoverGesture: UIHoverGestureRecognizer?
    private var hoverLocation: CGPoint?

    private var activeStroke: [RoadPoint] = []
    private var selectionInteraction: SelectionInteraction = .idle
    private var interchangeTouchOrigin: CGPoint?
    private var activeTouchIdentifier: ObjectIdentifier?
    private var activeNavigationRecognizers: Set<ObjectIdentifier> = []
    private var navigationAnchor: RoadPoint?
    private var navigationTouchCount = 0
    private var viewport = CanvasViewport()
    private var zoomScale: CGFloat { CGFloat(viewport.scale) }
    private var projectID: UUID?
    private var previousLayoutSize: CGSize = .zero
    private let compass = CanvasCompassControl()
    private let zoomInButton = UIButton(type: .system)
    private let zoomOutButton = UIButton(type: .system)
    private var northResetLink: CADisplayLink?
    private var northResetStart: CFTimeInterval = 0
    private var northResetRotation: Double = 0
    private var isRotating = false
    private var hasPositionedInitialMap = false
    private var cachedTerrainImage: CGImage?
    private var elevationPaths: [Int: CGMutablePath]?
    private var waterPaths: [CGMutablePath]?
    private weak var panGesture: UIPanGestureRecognizer?
    private var scaleBarHideWorkItem: DispatchWorkItem?
    private var isScaleBarVisible = false
    private var minimumZoomHintHideWorkItem: DispatchWorkItem?
    private var isMinimumZoomHintVisible = false
    private var zoomHint = "已显示完整可编辑区域，不能再缩小"
    private let boundaryBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private var didShowMinimumZoomHintForGesture = false

    var allowsFingerDrawing = false {
        didSet { if oldValue != allowsFingerDrawing { cancelContentInteraction(); updatePanTouchCount() } }
    }
    var pendingRampPlan: RoadRampPlan?
    weak var nativeMap: MKMapView?
    var exportViewport: MapExportViewport {
        MapExportViewport(camera: viewport, width: bounds.width, height: bounds.height)
    }

    func useNativeNavigation(_ enabled: Bool) {
        for gesture in gestureRecognizers ?? [] { gesture.isEnabled = !enabled }
        isOpaque = !enabled
        backgroundColor = enabled ? .clear : .systemBackground
        compass.isHidden = enabled
        zoomInButton.isHidden = enabled
        zoomOutButton.isHidden = enabled
    }

    func followNativeMap(origin: CGPoint, xAxis: CGPoint) {
        viewport = CanvasViewport(scale: hypot(xAxis.x-origin.x, xAxis.y-origin.y) / 1600,
            rotation: atan2(xAxis.y-origin.y, xAxis.x-origin.x),
            translation: RoadPoint(x: origin.x, y: origin.y))
        updateBoundaryBlur()
        refreshAccessibilityElements()
        setNeedsDisplay()
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Native MapKit's recognizers live below this display-only overlay.
        // Editing observes the same touches on the map, so two fingers always
        // reach MapKit even while one finger or Pencil is drawing.
        if nativeMap != nil { return nil }
        return super.hitTest(point, with: event)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .systemBackground
        isAccessibilityElement = true
        accessibilityLabel = "道路画布"
        accessibilityIdentifier = "road-canvas"
        accessibilityTraits = [.allowsDirectInteraction, .adjustable]

        if #available(iOS 17.0, *) {
            registerForTraitChanges(
                [UITraitUserInterfaceStyle.self],
                action: #selector(userInterfaceStyleDidChange)
            )
        }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pan.minimumNumberOfTouches = allowsFingerDrawing ? 2 : 1
        pan.maximumNumberOfTouches = 2
        pan.cancelsTouchesInView = true
        pan.delegate = self
        addGestureRecognizer(pan)
        panGesture = pan

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        pinch.cancelsTouchesInView = true
        pinch.delegate = self
        addGestureRecognizer(pinch)
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        rotation.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        rotation.delegate = self
        addGestureRecognizer(rotation)

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        hover.allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)
        ]
        addGestureRecognizer(hover)
        hoverGesture = hover

        compass.addTarget(self, action: #selector(resetNorth), for: .touchUpInside)
        compass.accessibilityIdentifier = "canvas-compass"
        addSubview(compass)
        configureZoomButton(zoomInButton, symbol: "plus", label: "放大地图", identifier: "canvas-zoom-in", action: #selector(zoomIn))
        configureZoomButton(zoomOutButton, symbol: "minus", label: "缩小地图", identifier: "canvas-zoom-out", action: #selector(zoomOut))
        boundaryBlur.isUserInteractionEnabled = false
        boundaryBlur.isHidden = true
        addSubview(boundaryBlur)
        updateNavigationControls()
    }

    @objc private func userInterfaceStyleDidChange() {
        setNeedsDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if nativeMap != nil { return }
        let inset = safeAreaInsets
        let controlX = max(inset.left + 8, bounds.width - inset.right - 58)
        compass.frame = CGRect(x: controlX, y: inset.top + 18, width: 44, height: 44)
        zoomInButton.frame = CGRect(x: controlX, y: inset.top + 72, width: 44, height: 44)
        zoomOutButton.frame = CGRect(x: controlX, y: inset.top + 118, width: 44, height: 44)
        guard bounds.width > 0, bounds.height > 0 else { return }
        if !hasPositionedInitialMap {
            viewport = CanvasViewport(scale: max(bounds.width / 1600, bounds.height / 1200))
            let center = viewport.screenPoint(for: RoadPoint(x: 800, y: 600))
            viewport.pan(by: RoadPoint(x: bounds.midX - center.x, y: bounds.midY - center.y))
            hasPositionedInitialMap = true
        } else if previousLayoutSize != bounds.size {
            viewport.pan(by: RoadPoint(x: (bounds.width - previousLayoutSize.width) / 2,
                                      y: (bounds.height - previousLayoutSize.height) / 2))
            constrainTranslation()
        }
        previousLayoutSize = bounds.size
        navigationDidChange()
    }

    func displayProject(_ id: UUID) {
        guard projectID != id else { return }
        projectID = id
        stopNorthReset()
        cancelContentInteraction()
        hasPositionedInitialMap = false
        viewport = CanvasViewport()
        isRotating = false
        navigationAnchor = nil
        navigationTouchCount = 0
        updateNavigationControls()
        setNeedsLayout()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let palette = currentTerrainPalette
        if realWorldMap?.source != .appleMaps {
        context.setFillColor(
            (
                showsTerrain && realWorldMap == nil
                    ? (terrain.scenario.hasOceanBoundary ? palette.water : palette.plain)
                    : UIColor.systemBackground
            ).cgColor
        )
        context.fill(bounds)
        }

        context.saveGState()
        context.translateBy(x: viewport.translation.x, y: viewport.translation.y)
        context.rotate(by: viewport.rotation)
        context.scaleBy(x: zoomScale, y: zoomScale)
        if realWorldMap?.source == .appleMaps {
            // Keep the live native basemap visible beneath editable roads.
        } else if let realWorldMap, !showsTerrain {
            CartographicRenderer.draw(realWorldMap, theme: theme, showsTerrain: false, showsHydrology: showsHydrology, in: context)
        } else if showsTerrain {
            drawTerrain(in: context)
        } else {
            context.setFillColor(palette.plain.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
        }
        drawBridgePiers(
            engineeringStructures,
            alpha: 1,
            in: context
        )
        drawBridgePiers(
            pendingEngineeringStructures,
            alpha: 0.72,
            in: context
        )
        drawReferenceOverlay(in: context)
        drawRoads(in: context)
        drawInterchanges(in: context)
        drawRailwayStations(in: context)
        drawStructureCandidatePreview(in: context)
        drawConstructionIssues(in: context)
        drawTunnelPortals(
            engineeringStructures,
            alpha: 1,
            in: context
        )
        drawTunnelPortals(
            pendingEngineeringStructures,
            alpha: 0.72,
            in: context
        )
        drawRoadSelection(in: context)
        drawPendingRamp(in: context)
        drawActiveStroke(in: context)
        context.restoreGState()
        drawHoverReticle(in: context)
        if nativeMap == nil && isScaleBarVisible {
            drawScaleBar(in: context)
        }
        if isMinimumZoomHintVisible {
            drawMinimumZoomHint()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeDirectTouchCount(in: event) > 1 {
            cancelContentInteraction()
            return
        }
        guard activeNavigationRecognizers.isEmpty,
              activeTouchIdentifier == nil,
              let touch = touches.first,
              shouldHandleContentTouch(touch, event: event)
        else { return }

        activeTouchIdentifier = ObjectIdentifier(touch)
        if isSelecting {
            beginSelection(with: touch)
        } else if isEditingInterchange && !isAwaitingRampDrawing {
            interchangeTouchOrigin = touch.location(in: self)
        } else {
            activeStroke = [worldPoint(for: touch.location(in: self))]
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if activeDirectTouchCount(in: event) > 1 {
            cancelContentInteraction()
            return
        }
        guard activeNavigationRecognizers.isEmpty,
              let touch = trackedTouch(in: touches)
        else { return }

        if isSelecting {
            updateSelection(with: touch)
            setNeedsDisplay()
            return
        }
        if isEditingInterchange && !isAwaitingRampDrawing {
            return
        }
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        activeStroke.append(contentsOf: samples.map { worldPoint(for: $0.location(in: self)) })
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = trackedTouch(in: touches) else { return }
        defer { activeTouchIdentifier = nil }

        if isSelecting {
            finishSelection(with: touch)
            setNeedsDisplay()
            return
        }
        if isEditingInterchange && !isAwaitingRampDrawing {
            finishInterchangeSelection(with: touch)
            setNeedsDisplay()
            return
        }

        activeStroke.append(worldPoint(for: touch.location(in: self)))
        let completedStroke = activeStroke
        activeStroke.removeAll(keepingCapacity: true)
        setNeedsDisplay()
        if isErasing {
            onEraseFinished?(
                RoadEraseRequest(
                    points: completedStroke,
                    radius: Double(18 / zoomScale),
                    eligibleRoadIDs: Set(roads.map(\.id)),
                    mode: eraserMode
                )
            )
        } else if !isSelecting && !isEditingInterchange {
            let strokeDist = completedStroke.indices.dropFirst().reduce(0.0) { sum, idx in
                sum + hypot(completedStroke[idx].x - completedStroke[idx - 1].x, completedStroke[idx].y - completedStroke[idx - 1].y)
            }
            if strokeDist < 8, let station = nearestStation(to: completedStroke[0], isPencil: touch.type == .pencil) {
                onStationSelected?(station.id == selectedStationID ? nil : station.id)
                return
            }
            onStrokeFinished?(completedStroke)
        } else {
            onStrokeFinished?(completedStroke)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch(in: touches) != nil else { return }
        cancelContentInteraction()
    }

    @objc private func handleHover(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            hoverLocation = recognizer.location(in: self)
            setNeedsDisplay()
        case .ended, .cancelled:
            hoverLocation = nil
            setNeedsDisplay()
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        let navigationTypes = { (gesture: UIGestureRecognizer) in
            gesture is UIPanGestureRecognizer || gesture is UIPinchGestureRecognizer || gesture is UIRotationGestureRecognizer
        }
        return navigationTypes(gestureRecognizer) && navigationTypes(otherGestureRecognizer)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        updateNavigationState(for: recognizer)
        guard recognizer.state == .began || recognizer.state == .changed else {
            return
        }
        applyNavigation(from: recognizer)
        navigationDidChange()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        updateNavigationState(for: recognizer)
        if recognizer.state == .began {
            didShowMinimumZoomHintForGesture = false
        }
        if recognizer.state == .began || recognizer.state == .changed {
            showScaleBar()
        } else if recognizer.state == .ended
            || recognizer.state == .cancelled
            || recognizer.state == .failed {
            scheduleScaleBarHide()
        }
        guard recognizer.state == .began || recognizer.state == .changed else {
            return
        }
        guard recognizer.numberOfTouches >= 2 else { return }
        let proposedScale = zoomScale * recognizer.scale
        applyNavigation(from: recognizer, scaleFactor: recognizer.scale)
        if proposedScale < minimumZoomScale - 0.001 {
            showMinimumZoomHint()
        }
        recognizer.scale = 1
        navigationDidChange()
    }

    /// Every recognizer advances the same touch centroid. Transform around its previous
    /// location before translating to the new one, so callback order cannot double-pan
    /// a moving pinch/rotation anchor. A changing touch count starts a new anchor.
    private func applyNavigation(from recognizer: UIGestureRecognizer, scaleFactor: Double = 1, rotationDelta: Double = 0) {
        let location = recognizer.location(in: self)
        let current = RoadPoint(x: location.x, y: location.y)
        let previous = navigationTouchCount == recognizer.numberOfTouches
            ? navigationAnchor ?? current : current
        viewport.navigate(scaleFactor: scaleFactor, rotationDelta: rotationDelta, anchor: previous, minimumScale: minimumZoomScale)
        viewport.pan(by: current - previous)
        navigationAnchor = current
        navigationTouchCount = recognizer.numberOfTouches
        constrainTranslation()
    }

    private var navigationAccessibilityElements: [Any] {
        let zoom = CanvasZoomAccessibilityElement(accessibilityContainer: self)
        zoom.accessibilityIdentifier = "canvas-viewport"
        zoom.accessibilityLabel = "地图缩放"
        zoom.accessibilityHint = accessibilityValue
        let zoomDescription = String(format: "%.0f%%", viewport.scale / fittedZoomScale * 100)
        if let nativeMap {
            let heading = Int(nativeMap.camera.heading.rounded()) % 360
            zoom.accessibilityValue = "\(zoomDescription)，朝向 \(heading)°"
        } else { zoom.accessibilityValue = "\(zoomDescription)，朝向 \(Int((viewport.rotation * 180 / .pi).rounded()))°" }
        zoom.accessibilityTraits = [.adjustable]
        // Keep this virtual map control clear of real buttons and overlaid palettes.
        // A full-view accessibility frame would mask their hit targets.
        zoom.accessibilityFrameInContainerSpace = bounds.insetBy(
            dx: bounds.width * 0.35, dy: bounds.height * 0.35
        )
        zoom.adjust = { [weak self] increase in
            guard let self else { return }
            if let map = self.nativeMap {
                let camera = map.camera.copy() as! MKMapCamera
                camera.centerCoordinateDistance *= increase ? 1/1.35 : 1.35
                map.setCamera(camera, animated: true)
            } else { self.zoom(by: increase ? 1.35 : 1/1.35) }
        }
        if nativeMap != nil { return [zoom] }
        return [zoom] + (compass.isHidden ? [] : [compass]) + [zoomInButton, zoomOutButton]
    }

    private func configureZoomButton(_ button: UIButton, symbol: String, label: String, identifier: String, action: Selector) {
        var config = UIButton.Configuration.bordered()
        config.image = UIImage(systemName: symbol)
        config.baseForegroundColor = .label
        config.background.backgroundColor = .secondarySystemBackground
        config.cornerStyle = .medium
        button.configuration = config
        button.accessibilityLabel = label
        button.accessibilityIdentifier = identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        addSubview(button)
    }

    @objc private func zoomIn() { zoom(by: 1.35) }
    @objc private func zoomOut() { zoom(by: 1 / 1.35) }
    override func accessibilityIncrement() { zoomIn() }
    override func accessibilityDecrement() { zoomOut() }

    private func zoom(by factor: Double) {
        stopNorthReset()
        cancelContentInteraction()
        viewport.navigate(scaleFactor: factor, anchor: RoadPoint(x: bounds.midX, y: bounds.midY), minimumScale: minimumZoomScale)
        constrainTranslation()
        showScaleBar()
        scheduleScaleBarHide()
        navigationDidChange()
    }

    @objc private func handleRotation(_ recognizer: UIRotationGestureRecognizer) {
        isRotating = recognizer.state == .began || recognizer.state == .changed
        updateNavigationState(for: recognizer)
        if isRotating {
            applyNavigation(from: recognizer, rotationDelta: recognizer.rotation)
            recognizer.rotation = 0
        }
        navigationDidChange()
    }

    private func updateNavigationControls() {
        compass.heading = viewport.rotation
        compass.isHidden = viewport.isNorthUp && !isRotating && northResetLink == nil
        zoomInButton.isEnabled = zoomScale < 4 - 0.001
        zoomOutButton.isEnabled = zoomScale > minimumZoomScale + 0.001
        zoomInButton.accessibilityValue = String(format: "%.0f%%", viewport.scale * 100)
        zoomOutButton.accessibilityValue = zoomInButton.accessibilityValue
    }

    private func navigationDidChange() {
        updateNavigationControls()
        refreshAccessibilityElements()
        setNeedsDisplay()
    }

    @objc private func resetNorth() {
        stopNorthReset()
        cancelContentInteraction()
        if UIAccessibility.isReduceMotionEnabled || viewport.isNorthUp {
            setHeading(0)
            navigationDidChange()
            return
        }
        northResetRotation = viewport.rotation
        northResetStart = CACurrentMediaTime()
        let link = CADisplayLink(target: self, selector: #selector(advanceNorthReset(_:)))
        northResetLink = link
        link.add(to: .main, forMode: .common)
    }

    @objc private func advanceNorthReset(_ link: CADisplayLink) {
        let progress = min(1, (CACurrentMediaTime() - northResetStart) / 0.28)
        let eased = progress * progress * (3 - 2 * progress)
        setHeading(northResetRotation * (1 - eased))
        if progress >= 1 { stopNorthReset() }
        navigationDidChange()
    }

    private func setHeading(_ heading: Double) {
        viewport.navigate(rotationDelta: heading - viewport.rotation, anchor: RoadPoint(x: bounds.midX, y: bounds.midY), minimumScale: minimumZoomScale)
        constrainTranslation()
    }

    private func stopNorthReset() {
        northResetLink?.invalidate()
        northResetLink = nil
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { stopNorthReset() }
    }

    private func showScaleBar() {
        scaleBarHideWorkItem?.cancel()
        isScaleBarVisible = true
        setNeedsDisplay()
    }

    private func scheduleScaleBarHide() {
        scaleBarHideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.isScaleBarVisible = false
            self?.setNeedsDisplay()
        }
        scaleBarHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: workItem)
    }

    private func updateBoundaryBlur() {
        boundaryBlur.isHidden = realWorldMap?.source == .appleMaps || zoomScale >= fittedZoomScale
        guard !boundaryBlur.isHidden else { return }
        boundaryBlur.frame = bounds
        boundaryBlur.alpha = min(1, (fittedZoomScale - zoomScale) / (fittedZoomScale * 0.1))
        let mask = CAShapeLayer()
        let path = UIBezierPath(rect: bounds)
        let corners = [RoadPoint(x: 0, y: 0), RoadPoint(x: 1600, y: 0),
                       RoadPoint(x: 1600, y: 1200), RoadPoint(x: 0, y: 1200)].map(screenPoint)
        path.move(to: corners[0])
        corners.dropFirst().forEach { path.addLine(to: $0) }
        path.close()
        mask.path = path.cgPath
        mask.fillRule = .evenOdd
        boundaryBlur.layer.mask = mask
    }

    private var fittedZoomScale: CGFloat {
        max(0.01, min(bounds.width / 1600, bounds.height / 1200))
    }
    private var minimumZoomScale: CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0.2 }
        return min(bounds.width / 1600, bounds.height / 1200) * 0.92
    }


    private func constrainTranslation() {
        viewport.constrain(to: RoadPoint(x: bounds.width, y: bounds.height))
    }

    func showMinimumZoomHint(maximum: Bool = false) {
        zoomHint = maximum ? "已达到最大放大倍率" : "已显示完整可编辑区域，不能再缩小"
        guard !didShowMinimumZoomHintForGesture || nativeMap != nil else { return }
        didShowMinimumZoomHintForGesture = true
        minimumZoomHintHideWorkItem?.cancel()
        isMinimumZoomHintVisible = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(
            notification: .announcement,
            argument: zoomHint
        )
        setNeedsDisplay()

        let workItem = DispatchWorkItem { [weak self] in
            self?.isMinimumZoomHintVisible = false
            self?.setNeedsDisplay()
        }
        minimumZoomHintHideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.35, execute: workItem)
    }

    private func drawMinimumZoomHint() {
        let message = zoomHint
        let font = UIFont.preferredFont(forTextStyle: .footnote)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        let textSize = (message as NSString).size(withAttributes: attributes)
        let pill = CGRect(
            x: bounds.midX - textSize.width / 2 - 14,
            y: 66,
            width: textSize.width + 28,
            height: textSize.height + 14
        )
        UIColor.secondarySystemBackground.withAlphaComponent(0.94).setFill()
        UIBezierPath(roundedRect: pill, cornerRadius: pill.height / 2).fill()
        (message as NSString).draw(
            at: CGPoint(x: pill.minX + 14, y: pill.minY + 7),
            withAttributes: attributes
        )
    }

    private func shouldHandleContentTouch(
        _ touch: UITouch,
        event: UIEvent?
    ) -> Bool {
        if isSelecting || (isEditingInterchange && !isAwaitingRampDrawing) {
            return touch.type == .pencil || touch.type == .direct
        }
        return touch.type == .pencil
            || (
                allowsFingerDrawing
                    && touch.type == .direct
                    && activeDirectTouchCount(in: event) <= 1
            )
    }

    private func trackedTouch(in touches: Set<UITouch>) -> UITouch? {
        guard let activeTouchIdentifier else { return nil }
        return touches.first {
            ObjectIdentifier($0) == activeTouchIdentifier
        }
    }

    private func activeDirectTouchCount(in event: UIEvent?) -> Int {
        event?.allTouches?.count {
            $0.type == .direct
                && $0.phase != .ended
                && $0.phase != .cancelled
        } ?? 0
    }

    private func updatePanTouchCount() {
        panGesture?.minimumNumberOfTouches = isSelecting
            || isEditingInterchange
            || allowsFingerDrawing
            ? 2
            : 1
    }

    private func updateNavigationState(for recognizer: UIGestureRecognizer) {
        let identifier = ObjectIdentifier(recognizer)
        switch recognizer.state {
        case .began:
            if activeNavigationRecognizers.isEmpty {
                navigationAnchor = nil
                navigationTouchCount = 0
            }
            activeNavigationRecognizers.insert(identifier)
            stopNorthReset()
            cancelContentInteraction()
        case .ended, .cancelled, .failed:
            let wasActive = activeNavigationRecognizers.remove(identifier) != nil
            if wasActive && activeNavigationRecognizers.isEmpty {
                viewport.snapToNorthIfClose(
                    anchor: navigationAnchor ?? RoadPoint(x: bounds.midX, y: bounds.midY)
                )
                constrainTranslation()
                navigationAnchor = nil
                navigationTouchCount = 0
                navigationDidChange()
            }
        default:
            break
        }
    }

    private func cancelContentInteraction() {
        activeTouchIdentifier = nil
        activeStroke.removeAll(keepingCapacity: true)
        selectionInteraction = .idle
        interchangeTouchOrigin = nil
        setNeedsDisplay()
    }

    private func beginSelection(with touch: UITouch) {
        let screenPoint = touch.location(in: self)
        let canvasPoint = worldPoint(for: screenPoint)
        selectionInteraction = .pending(
            PendingSelection(
                originScreenPoint: screenPoint,
                originCanvasPoint: canvasPoint,
                latestScreenPoint: screenPoint,
                hit: selectionHit(at: canvasPoint, touch: touch),
                isPencil: touch.type == .pencil,
                exceededDragThreshold: false
            )
        )
    }

    private func updateSelection(with touch: UITouch) {
        let screenPoint = touch.location(in: self)
        let canvasPoint = worldPoint(for: screenPoint)

        switch selectionInteraction {
        case .idle:
            break

        case var .pending(pending):
            pending.latestScreenPoint = screenPoint
            let dragDistance = hypot(
                screenPoint.x - pending.originScreenPoint.x,
                screenPoint.y - pending.originScreenPoint.y
            )
            let threshold: CGFloat = pending.isPencil ? 6 : 10
            guard dragDistance > threshold else {
                selectionInteraction = .pending(pending)
                return
            }

            pending.exceededDragThreshold = true
            switch pending.hit {
            case let .controlPoint(sourceRoadID, point):
                selectionInteraction = .deforming(
                    sourceRoadID: sourceRoadID,
                    originalPoint: point,
                    current: clampedCanvasPoint(canvasPoint),
                    maximumDistanceMeters: hitRadiusMeters(
                        isPencil: pending.isPencil
                    )
                )

            case .selectedRoad:
                let offset = constrainedSelectionOffset(
                    canvasPoint - pending.originCanvasPoint,
                    sourceRoadIDs: selectedSourceRoadIDs
                )
                selectionInteraction = .translating(
                    origin: pending.originCanvasPoint,
                    current: pending.originCanvasPoint + offset,
                    sourceRoadIDs: selectedSourceRoadIDs
                )

            case .empty:
                selectionInteraction = .marquee(
                    origin: pending.originCanvasPoint,
                    current: clampedCanvasPoint(canvasPoint)
                )

            case .unselectedRoad, .station:
                selectionInteraction = .pending(pending)
            }

        case let .marquee(origin, _):
            selectionInteraction = .marquee(
                origin: origin,
                current: clampedCanvasPoint(canvasPoint)
            )

        case let .translating(origin, _, sourceRoadIDs):
            let offset = constrainedSelectionOffset(
                canvasPoint - origin,
                sourceRoadIDs: sourceRoadIDs
            )
            selectionInteraction = .translating(
                origin: origin,
                current: origin + offset,
                sourceRoadIDs: sourceRoadIDs
            )

        case let .deforming(
            sourceRoadID,
            originalPoint,
            _,
            maximumDistanceMeters
        ):
            selectionInteraction = .deforming(
                sourceRoadID: sourceRoadID,
                originalPoint: originalPoint,
                current: clampedCanvasPoint(canvasPoint),
                maximumDistanceMeters: maximumDistanceMeters
            )
        }
    }

    private func finishSelection(with touch: UITouch) {
        updateSelection(with: touch)
        let completedInteraction = selectionInteraction
        selectionInteraction = .idle

        switch completedInteraction {
        case let .pending(pending):
            guard !pending.exceededDragThreshold else { return }
            var selection = selectedSourceRoadIDs
            switch pending.hit {
            case let .station(stationID):
                if selectedStationID == stationID {
                    onStationSelected?(nil)
                } else {
                    onStationSelected?(stationID)
                }
                return
            case .controlPoint:
                return
            case let .selectedRoad(sourceRoadID),
                 let .unselectedRoad(sourceRoadID):
                onStationSelected?(nil)
                if selection.contains(sourceRoadID) {
                    selection.remove(sourceRoadID)
                } else {
                    selection.insert(sourceRoadID)
                }
            case .empty:
                selection.removeAll()
                onStationSelected?(nil)
            }
            publishSelection(selection)

        case let .marquee(origin, current):
            publishSelection(
                RoadSourceGeometry.sourceRoadIDs(
                    intersecting: RoadSourceSelectionRectangle(
                        canvasCornerA: origin,
                        canvasCornerB: current
                    ),
                    in: roads
                )
            )

        case let .translating(origin, current, sourceRoadIDs):
            let offset = current - origin
            guard hypot(offset.x, offset.y) > 1e-9 else { return }
            onSelectionMoved?(sourceRoadIDs, offset)

        case let .deforming(
            sourceRoadID,
            originalPoint,
            current,
            maximumDistanceMeters
        ):
            guard originalPoint.distance(to: current) > 1e-9 else { return }
            onControlPointMoved?(
                sourceRoadID,
                originalPoint,
                current,
                maximumDistanceMeters
            )

        case .idle:
            break
        }
    }

    private func finishInterchangeSelection(with touch: UITouch) {
        defer { interchangeTouchOrigin = nil }
        let screenPoint = touch.location(in: self)
        if let origin = interchangeTouchOrigin,
           hypot(screenPoint.x - origin.x, screenPoint.y - origin.y) > 10 {
            return
        }
        let canvasPoint = worldPoint(for: screenPoint)
        switch interchangeHit(at: canvasPoint, touch: touch) {
        case let .crossing(relationID):
            onRampSelected?(nil)
            onInterchangeCrossingSelected?(relationID)
        case let .ramp(sourceRoadID):
            onRampSelected?(sourceRoadID)
        case .empty:
            onRampSelected?(nil)
            onInterchangeCrossingSelected?(nil)
        }
    }

    private func interchangeHit(
        at canvasPoint: RoadPoint,
        touch: UITouch
    ) -> InterchangeHit {
        let radiusMeters = hitRadiusMeters(isPencil: touch.type == .pencil)
        let rampSourceRoadIDs = self.rampSourceRoadIDs
        if let hit = RoadSourceGeometry.nearestSource(
            toCanvasPoint: canvasPoint,
            maximumDistanceMeters: radiusMeters,
            mapScale: mapScale,
            in: roads.filter {
                rampSourceRoadIDs.contains($0.sourceRoadID)
            }
        ) {
            return .ramp(hit.sourceRoadID)
        }

        let maximumDistance = mapScale.canvasDistance(
            forMeters: radiusMeters
        )
        let crossing = selectableInterchangeCrossings
            .map { ($0, canvasPoint.distance(to: $0.point)) }
            .filter { $0.1.isFinite && $0.1 <= maximumDistance }
            .min {
                if abs($0.1 - $1.1) > 1e-12 {
                    return $0.1 < $1.1
                }
                return $0.0.id.uuidString < $1.0.id.uuidString
            }?
            .0
        return crossing.map { .crossing($0.id) } ?? .empty
    }

    private var rampSourceRoadIDs: Set<UUID> {
        cachedRampSourceRoadIDs
    }

    private var selectableInterchangeCrossings: [RoadRelation] {
        let rampIDs = rampSourceRoadIDs
        return relations.filter { relation in
            guard relation.kind == .gradeSeparatedCrossing,
                  relation.firstLevel != .tunnel,
                  relation.secondLevel != .tunnel,
                  !rampIDs.contains(relation.firstRoadID),
                  !rampIDs.contains(relation.secondRoadID)
            else {
                return false
            }
            let firstRoads = roads.filter {
                $0.sourceRoadID == relation.firstRoadID
            }
            let secondRoads = roads.filter {
                $0.sourceRoadID == relation.secondRoadID
            }
            return !firstRoads.isEmpty
                && !secondRoads.isEmpty
                && firstRoads.allSatisfy { $0.kind != .railway }
                && secondRoads.allSatisfy { $0.kind != .railway }
        }
    }

    private func publishSelection(_ selection: Set<UUID>) {
        selectedSourceRoadIDs = selection
        onSelectionChanged?(selection)
    }

    private func selectionHit(
        at canvasPoint: RoadPoint,
        touch: UITouch
    ) -> SelectionHit {
        let isPencil = touch.type == .pencil
        let maximumDistanceMeters = hitRadiusMeters(isPencil: isPencil)

        if let station = nearestStation(to: canvasPoint, isPencil: isPencil) {
            return .station(id: station.id)
        }

        if selectedSourceRoadIDs.count == 1,
           let sourceRoadID = selectedSourceRoadIDs.first,
           let controlPoint = nearestVisibleControlPoint(
               to: canvasPoint,
               on: sourceRoadID,
               maximumDistanceMeters: maximumDistanceMeters
           ) {
            return .controlPoint(
                sourceRoadID: sourceRoadID,
                point: controlPoint
            )
        }

        guard let road = RoadSourceGeometry.nearestSource(
            toCanvasPoint: canvasPoint,
            maximumDistanceMeters: maximumDistanceMeters,
            mapScale: mapScale,
            in: roads
        ) else {
            return .empty
        }
        return selectedSourceRoadIDs.contains(road.sourceRoadID)
            ? .selectedRoad(sourceRoadID: road.sourceRoadID)
            : .unselectedRoad(sourceRoadID: road.sourceRoadID)
    }

    private func nearestStation(to canvasPoint: RoadPoint, isPencil: Bool) -> RailwayStation? {
        let screenRadius: CGFloat = isPencil ? 20 : 30
        let maxCanvasDistance = Double(screenRadius / zoomScale)
        var nearest: RailwayStation?
        var bestDist = maxCanvasDistance
        for station in railwayStations {
            let dist = hypot(station.point.x - canvasPoint.x, station.point.y - canvasPoint.y)
            if dist < bestDist {
                bestDist = dist
                nearest = station
            }
        }
        return nearest
    }

    private func hitRadiusMeters(isPencil: Bool) -> Double {
        let screenRadius: CGFloat = isPencil ? 12 : 22
        return mapScale.meters(
            forCanvasDistance: Double(screenRadius / zoomScale)
        )
    }

    private func constrainedSelectionOffset(
        _ desiredOffset: RoadPoint,
        sourceRoadIDs: Set<UUID>
    ) -> RoadPoint {
        let selectedPoints = roads
            .filter { sourceRoadIDs.contains($0.sourceRoadID) }
            .flatMap(\.points)
        guard let minimumX = selectedPoints.map(\.x).min(),
              let maximumX = selectedPoints.map(\.x).max(),
              let minimumY = selectedPoints.map(\.y).min(),
              let maximumY = selectedPoints.map(\.y).max()
        else { return RoadPoint(x: 0, y: 0) }

        return RoadPoint(
            x: min(
                MapScale.canvasWidth - maximumX,
                max(-minimumX, desiredOffset.x)
            ),
            y: min(
                MapScale.canvasHeight - maximumY,
                max(-minimumY, desiredOffset.y)
            )
        )
    }

    private func clampedCanvasPoint(_ point: RoadPoint) -> RoadPoint {
        RoadPoint(
            x: min(MapScale.canvasWidth, max(0, point.x)),
            y: min(MapScale.canvasHeight, max(0, point.y))
        )
    }

    private func worldPoint(for screenPoint: CGPoint) -> RoadPoint {
        viewport.worldPoint(for: RoadPoint(x: screenPoint.x, y: screenPoint.y))
    }

    func refreshAccessibilityElements() {
        guard bounds.width > 0, bounds.height > 0 else {
            accessibilityElements = nil
            return
        }

        var elements: [Any] = navigationAccessibilityElements
        guard isSelecting || isEditingInterchange else {
            isAccessibilityElement = false
            accessibilityElements = navigationAccessibilityElements
            return
        }
        isAccessibilityElement = false
        if isEditingInterchange {
            accessibilityElements = navigationAccessibilityElements + interchangeAccessibilityElements()
            return
        }
        let roadsBySource = Dictionary(grouping: roads, by: \.sourceRoadID)
        for sourceRoadID in roadsBySource.keys.sorted(by: {
            $0.uuidString < $1.uuidString
        }) {
            guard let sourceRoads = roadsBySource[sourceRoadID],
                  let kind = sourceRoads.first?.kind,
                  let canvasPoint = representativePoint(for: sourceRoads)
            else { continue }
            let screenPoint = screenPoint(for: canvasPoint)
            let frame = CGRect(
                x: screenPoint.x - 22,
                y: screenPoint.y - 22,
                width: 44,
                height: 44
            )
            guard frame.intersects(bounds) else { continue }

            let element = CanvasAccessibilityElement(
                accessibilityContainer: self
            )
            element.accessibilityIdentifier = "road-source-\(sourceRoadID.uuidString.lowercased())"
            element.accessibilityLabel = "\(kind.displayName)道路"
            element.accessibilityValue = selectedSourceRoadIDs.contains(sourceRoadID)
                ? "已选择"
                : "未选择"
            element.accessibilityFrameInContainerSpace = frame
            element.accessibilityTraits = [.button]
            if selectedSourceRoadIDs.contains(sourceRoadID) {
                element.accessibilityTraits.insert(.selected)
            }
            element.onActivate = { [weak self] in
                guard let self, self.isSelecting else { return false }
                var nextSelection = self.selectedSourceRoadIDs
                if nextSelection.contains(sourceRoadID) {
                    nextSelection.remove(sourceRoadID)
                } else {
                    nextSelection.insert(sourceRoadID)
                }
                self.publishSelection(nextSelection)
                return true
            }
            elements.append(element)
        }

        if selectedSourceRoadIDs.count == 1,
           let sourceRoadID = selectedSourceRoadIDs.first {
            for (index, canvasPoint) in accessibilityControlPoints(
                for: sourceRoadID
            ).enumerated() {
                let screenPoint = screenPoint(for: canvasPoint)
                let frame = CGRect(
                    x: screenPoint.x - 22,
                    y: screenPoint.y - 22,
                    width: 44,
                    height: 44
                )
                guard frame.intersects(bounds) else { continue }
                let element = CanvasAccessibilityElement(
                    accessibilityContainer: self
                )
                element.accessibilityIdentifier = [
                    "road-control-point",
                    sourceRoadID.uuidString.lowercased(),
                    String(index),
                ].joined(separator: "-")
                element.accessibilityLabel = "道路控制点 \(index + 1)"
                element.accessibilityFrameInContainerSpace = frame
                element.accessibilityTraits = [.button, .adjustable]
                element.onActivate = { true }
                elements.append(element)
            }
        }
        accessibilityElements = elements
    }

    private func interchangeAccessibilityElements() -> [UIAccessibilityElement] {
        var elements: [UIAccessibilityElement] = []
        for relation in selectableInterchangeCrossings {
            let screenPoint = screenPoint(for: relation.point)
            let frame = CGRect(
                x: screenPoint.x - 22,
                y: screenPoint.y - 22,
                width: 44,
                height: 44
            )
            guard frame.intersects(bounds) else { continue }
            let firstKind = roads.first {
                $0.sourceRoadID == relation.firstRoadID
            }?.kind.displayName ?? "道路"
            let secondKind = roads.first {
                $0.sourceRoadID == relation.secondRoadID
            }?.kind.displayName ?? "道路"
            let rampCount = interchanges
                .filter {
                    Set([
                        $0.anchor.upperSourceRoadID,
                        $0.anchor.lowerSourceRoadID,
                    ]) == Set([relation.firstRoadID, relation.secondRoadID])
                }
                .flatMap(\.ramps)
                .count
            let element = CanvasAccessibilityElement(
                accessibilityContainer: self
            )
            element.accessibilityIdentifier = [
                "interchange-crossing",
                relation.id.uuidString.lowercased(),
            ].joined(separator: "-")
            element.accessibilityLabel = "异层交叉，\(firstKind)与\(secondKind)"
            element.accessibilityValue = rampCount == 0
                ? "未建立匝道"
                : "\(rampCount) 条匝道"
            element.accessibilityFrameInContainerSpace = frame
            element.accessibilityTraits = [.button]
            if relation.id == selectedInterchangeCrossingID {
                element.accessibilityTraits.insert(.selected)
            }
            element.onActivate = { [weak self] in
                guard let self, self.isEditingInterchange else { return false }
                self.onRampSelected?(nil)
                self.onInterchangeCrossingSelected?(relation.id)
                return true
            }
            elements.append(element)
        }

        let roadsBySource = Dictionary(grouping: roads, by: \.sourceRoadID)
        for interchange in interchanges {
            for ramp in interchange.ramps {
                guard let sourceRoads = roadsBySource[ramp.sourceRoadID],
                      let canvasPoint = representativePoint(for: sourceRoads)
                else {
                    continue
                }
                let screenPoint = screenPoint(for: canvasPoint)
                let frame = CGRect(
                    x: screenPoint.x - 22,
                    y: screenPoint.y - 22,
                    width: 44,
                    height: 44
                )
                guard frame.intersects(bounds) else { continue }
                let kind = sourceRoads.first?.kind.displayName ?? "道路"
                let element = CanvasAccessibilityElement(
                    accessibilityContainer: self
                )
                element.accessibilityIdentifier = [
                    "interchange-ramp",
                    ramp.sourceRoadID.uuidString.lowercased(),
                ].joined(separator: "-")
                element.accessibilityLabel = "\(kind)匝道"
                element.accessibilityValue = rampDirectionDescription(ramp)
                element.accessibilityFrameInContainerSpace = frame
                element.accessibilityTraits = [.button]
                if ramp.sourceRoadID == selectedRampID {
                    element.accessibilityTraits.insert(.selected)
                }
                element.onActivate = { [weak self] in
                    guard let self, self.isEditingInterchange else { return false }
                    self.onRampSelected?(ramp.sourceRoadID)
                    return true
                }
                elements.append(element)

                if ramp.sourceRoadID == selectedRampID {
                    elements.append(
                        rampTerminalAccessibilityElement(
                            point: ramp.start.lastKnownPoint,
                            rampSourceRoadID: ramp.sourceRoadID,
                            role: .start
                        )
                    )
                    elements.append(
                        rampTerminalAccessibilityElement(
                            point: ramp.end.lastKnownPoint,
                            rampSourceRoadID: ramp.sourceRoadID,
                            role: .end
                        )
                    )
                }
            }
        }
        return elements
    }

    private func rampTerminalAccessibilityElement(
        point: RoadPoint,
        rampSourceRoadID: UUID,
        role: RoadRampTerminalRole
    ) -> UIAccessibilityElement {
        let screenPoint = screenPoint(for: point)
        let element = CanvasAccessibilityElement(
            accessibilityContainer: self
        )
        element.accessibilityIdentifier = [
            "ramp-endpoint",
            rampSourceRoadID.uuidString.lowercased(),
            role.rawValue,
        ].joined(separator: "-")
        element.accessibilityLabel = role == .start ? "匝道起点" : "匝道终点"
        element.accessibilityValue = "已连接"
        element.accessibilityFrameInContainerSpace = CGRect(
            x: screenPoint.x - 22,
            y: screenPoint.y - 22,
            width: 44,
            height: 44
        )
        element.accessibilityTraits = [.button, .adjustable]
        element.onActivate = { true }
        return element
    }

    private func rampDirectionDescription(_ ramp: RoadRamp) -> String {
        switch ramp.direction {
        case .forward:
            "\(levelName(ramp.start.level))到\(levelName(ramp.end.level))"
        case .reverse:
            "\(levelName(ramp.end.level))到\(levelName(ramp.start.level))"
        case .bidirectional:
            "双向"
        }
    }

    private func levelName(_ level: RoadLevel) -> String {
        switch level {
        case .tunnel: "隧道"
        case .ground: "地面"
        case .elevated: "高架"
        }
    }

    private func representativePoint(
        for sourceRoads: [RoadSegment]
    ) -> RoadPoint? {
        guard let road = sourceRoads.max(by: {
            polylineLength($0.points) < polylineLength($1.points)
        }) else { return nil }
        let length = polylineLength(road.points)
        guard length > 1e-9 else { return road.points.first }
        var remaining = length / 2
        for index in 0..<(road.points.count - 1) {
            let start = road.points[index]
            let end = road.points[index + 1]
            let segmentLength = start.distance(to: end)
            if remaining <= segmentLength, segmentLength > 1e-9 {
                return start + (end - start) * (remaining / segmentLength)
            }
            remaining -= segmentLength
        }
        return road.points.last
    }

    private func accessibilityControlPoints(
        for sourceRoadID: UUID
    ) -> [RoadPoint] {
        visibleControlPoints(for: sourceRoadID)
    }

    private func visibleControlPoints(
        for sourceRoadID: UUID
    ) -> [RoadPoint] {
        let candidates = Set(
            roads
                .filter { $0.sourceRoadID == sourceRoadID }
                .flatMap(\.points)
                .filter { $0.x.isFinite && $0.y.isFinite }
        )
        .sorted {
            $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x
        }
        var result: [RoadPoint] = []
        for point in candidates
        where result.allSatisfy({
            $0.distance(to: point) * Double(zoomScale) >= 28
        }) {
            result.append(point)
        }
        return result
    }

    private func nearestVisibleControlPoint(
        to canvasPoint: RoadPoint,
        on sourceRoadID: UUID,
        maximumDistanceMeters: Double
    ) -> RoadPoint? {
        guard canvasPoint.x.isFinite,
              canvasPoint.y.isFinite,
              maximumDistanceMeters.isFinite else {
            return nil
        }
        let maximumDistance = mapScale.canvasDistance(
            forMeters: max(0, maximumDistanceMeters)
        )
        guard maximumDistance.isFinite else { return nil }

        return visibleControlPoints(for: sourceRoadID)
            .map { ($0, canvasPoint.distance(to: $0)) }
            .filter { $0.1.isFinite && $0.1 <= maximumDistance }
            .min {
                if abs($0.1 - $1.1) > 1e-12 {
                    return $0.1 < $1.1
                }
                return ($0.0.x, $0.0.y) < ($1.0.x, $1.0.y)
            }?
            .0
    }

    private func polylineLength(_ points: [RoadPoint]) -> Double {
        guard points.count >= 2 else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) {
            $0 + $1.0.distance(to: $1.1)
        }
    }

    private func screenPoint(for canvasPoint: RoadPoint) -> CGPoint {
        let point = viewport.screenPoint(for: canvasPoint)
        return CGPoint(x: point.x, y: point.y)
    }

    private func transitionTerrain() {
        cachedTerrainImage = nil
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let transition = CATransition()
        transition.type = .fade
        transition.duration = 0.22
        layer.add(transition, forKey: "mapAppearance")
    }

    private func drawTerrain(in context: CGContext) {
        if cachedTerrainImage == nil {
            let bounds = CGRect(x: 0, y: 0, width: 1600, height: 1200)
            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            let image = renderer.image { rendererContext in
                drawTerrainContent(in: rendererContext.cgContext)
            }
            cachedTerrainImage = image.cgImage
        }
        guard let cachedTerrainImage else { return }
        context.saveGState()
        context.translateBy(x: 0, y: 1200)
        context.scaleBy(x: 1, y: -1)
        context.draw(cachedTerrainImage, in: CGRect(x: 0, y: 0, width: 1600, height: 1200))
        context.restoreGState()
    }

    private func drawTerrainContent(in context: CGContext) {
        if let realWorldMap {
            CartographicRenderer.draw(realWorldMap, theme: theme, showsTerrain: true, showsHydrology: showsHydrology, in: context)
            return
        }
        let palette = currentTerrainPalette
        if !terrain.scenario.hasOceanBoundary {
            context.setFillColor(palette.plain.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 1200))
            context.saveGState()
            context.clip(to: CGRect(x: 0, y: 0, width: 1600, height: 1200))
            drawElevationBands(in: context, palette: palette)
            if showsGrid {
                drawGrid(in: context, color: palette.grid)
            }
            if showsContours {
                drawContours(in: context, color: palette.contour)
            }
            if showsWatersheds {
                drawWatershedBoundaries(in: context, color: palette.watershed)
            }
            context.restoreGState()
            drawTerrainEdgeFade(in: context, fadeColor: palette.plain)
            return
        }

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
        if showsWatersheds {
            drawWatershedBoundaries(in: context, color: palette.watershed)
        }
        context.restoreGState()

        context.setStrokeColor(palette.shoreline.cgColor)
        context.setLineWidth(1.2)
        context.addPath(shorePath)
        context.strokePath()
        drawTerrainEdgeFade(in: context, fadeColor: palette.water)
    }

    private func drawTerrainEdgeFade(in context: CGContext, fadeColor: UIColor) {
        let fadeWidth: CGFloat = 80
        context.saveGState()
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        fadeColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let edgeColor = CGColor(red: red, green: green, blue: blue, alpha: 0.95)
        let clearColor = CGColor(red: red, green: green, blue: blue, alpha: 0.0)
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [edgeColor, clearColor] as CFArray,
            locations: [0, 1]
        ) else {
            context.restoreGState()
            return
        }

        // Top edge
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: 1600, height: fadeWidth))
        context.drawLinearGradient(gradient, start: CGPoint(x: 800, y: 0), end: CGPoint(x: 800, y: fadeWidth), options: [])
        context.restoreGState()

        // Bottom edge
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 1200 - fadeWidth, width: 1600, height: fadeWidth))
        context.drawLinearGradient(gradient, start: CGPoint(x: 800, y: 1200), end: CGPoint(x: 800, y: 1200 - fadeWidth), options: [])
        context.restoreGState()

        // Left edge
        context.saveGState()
        context.clip(to: CGRect(x: 0, y: 0, width: fadeWidth, height: 1200))
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 600), end: CGPoint(x: fadeWidth, y: 600), options: [])
        context.restoreGState()

        // Right edge
        context.saveGState()
        context.clip(to: CGRect(x: 1600 - fadeWidth, y: 0, width: fadeWidth, height: 1200))
        context.drawLinearGradient(gradient, start: CGPoint(x: 1600, y: 600), end: CGPoint(x: 1600 - fadeWidth, y: 600), options: [])
        context.restoreGState()

        context.restoreGState()
    }

    private func drawElevationBands(in context: CGContext, palette: TerrainPalette) {
        guard terrain.hasElevationData else { return }
        struct Vertex { var point: CGPoint; var height: Double }
        var paths: [Int: CGMutablePath] = [:]
        let dx = 1600.0/Double(terrain.gridWidth-1)
        let dy = 1200.0/Double(terrain.gridHeight-1)
        func clip(_ polygon: [Vertex], at threshold: Double, above: Bool) -> [Vertex] {
            guard var previous = polygon.last else { return [] }
            var result: [Vertex] = []
            for current in polygon {
                let previousInside = above ? previous.height >= threshold : previous.height <= threshold
                let currentInside = above ? current.height >= threshold : current.height <= threshold
                if previousInside != currentInside {
                    let fraction = (threshold-previous.height)/(current.height-previous.height)
                    result.append(Vertex(point: CGPoint(x: previous.point.x+(current.point.x-previous.point.x)*fraction,
                        y: previous.point.y+(current.point.y-previous.point.y)*fraction), height: threshold))
                }
                if currentInside { result.append(current) }
                previous = current
            }
            return result
        }
        func append(_ vertices: [Vertex], bucket: Int) {
            guard vertices.count >= 3 else { return }
            let path = paths[bucket] ?? CGMutablePath()
            path.move(to: vertices[0].point)
            vertices.dropFirst().forEach { path.addLine(to: $0.point) }
            path.closeSubpath()
            paths[bucket] = path
        }
        if let cached = elevationPaths { paths = cached } else {
        for row in 0..<(terrain.gridHeight-1) {
            for column in 0..<(terrain.gridWidth-1) {
                let corners = [(column,row),(column+1,row),(column+1,row+1),(column,row+1)].map { x,y in
                    Vertex(point: CGPoint(x: Double(x)*dx, y: Double(y)*dy),
                        height: Double(terrain.elevations[y*terrain.gridWidth+x])/Double(UInt16.max))
                }
                for triangle in [[corners[0],corners[1],corners[2]], [corners[0],corners[2],corners[3]]] {
                    let lower = Int(triangle.map(\.height).min()!*24)
                    let upper = Int(triangle.map(\.height).max()!*24)
                    for bucket in lower...upper {
                        append(clip(clip(triangle, at: Double(bucket)/24, above: true),
                            at: Double(bucket+1)/24, above: false), bucket: bucket)
                    }
                }
            }
        }
        elevationPaths = paths
        }
        context.saveGState()
        context.setShouldAntialias(false)
        for bucket in paths.keys.sorted() {
            let color = bucket == -1 ? palette.water : (bucket == -2 ? palette.wetland : palette.color(for: Double(bucket)/24))
            context.setFillColor(color.cgColor)
            context.addPath(paths[bucket]!)
            context.fillPath()
        }
        context.restoreGState()
        guard showsHydrology else { return }
        if let waterPaths {
            for (index, path) in waterPaths.enumerated() {
                context.setFillColor((index == 0 ? palette.wetland : palette.water).cgColor)
                context.addPath(path)
                context.fillPath()
            }
            return
        }
        var builtWaterPaths: [CGMutablePath] = []
        for wetland in [true, false] {
            let waterPath = CGMutablePath()
            struct Edge: Hashable { let start: Int; let end: Int }
            var edges = Set<Edge>()
            var points: [Int: CGPoint] = [:]
            func vertexID(_ point: CGPoint) -> Int {
                let x = Int((point.x / dx * 2).rounded())
                let y = Int((point.y / dy * 2).rounded())
                let id = y * (terrain.gridWidth * 2 + 1) + x
                points[id] = point
                return id
            }
            for row in 0..<(terrain.gridHeight - 1) {
                for column in 0..<(terrain.gridWidth - 1) {
                    let vertices = [(column,row),(column+1,row),(column+1,row+1),(column,row+1)].map { x,y in
                        let surface = terrain.hydrology.surface(column: x, row: y)
                        let covered = wetland ? surface == .wetland : (surface == .river || surface == .lake)
                        return Vertex(point: CGPoint(x: Double(x)*dx, y: Double(y)*dy), height: covered ? 1 : 0)
                    }
                    for triangle in [[vertices[0],vertices[1],vertices[2]], [vertices[0],vertices[2],vertices[3]]] {
                        let polygon = clip(triangle, at: 0.5, above: true)
                        guard polygon.count >= 3 else { continue }
                        let ids = polygon.map { vertexID($0.point) }
                        for index in ids.indices {
                            let a = ids[index], b = ids[(index + 1) % ids.count]
                            if edges.remove(Edge(start: b, end: a)) == nil {
                                edges.insert(Edge(start: a, end: b))
                            }
                        }
                    }
                }
            }
            // Cancel interior triangle edges, then round each continuous shoreline.
            // Curves describe the boundary, rather than rounded individual tiles.
            var next: [Int: [Int]] = [:]
            for edge in edges { next[edge.start, default: []].append(edge.end) }
            while let start = next.keys.min() {
                var ring: [CGPoint] = []
                var current = start
                repeat {
                    guard let point = points[current], let target = next[current]?.popLast() else { break }
                    ring.append(point)
                    if next[current]?.isEmpty == true { next.removeValue(forKey: current) }
                    current = target
                } while current != start
                guard ring.count >= 3, current == start else { continue }
                // Remove cell-scale stair steps before fitting quadratic curves with multi-pass Laplacian smoothing.
                let smoothingPasses = ring.count > 12 ? 10 : (ring.count > 5 ? 4 : 2)
                for _ in 0..<smoothingPasses {
                    let previousRing = ring
                    for index in ring.indices {
                        let a = previousRing[(index + ring.count - 1) % ring.count]
                        let b = previousRing[index]
                        let c = previousRing[(index + 1) % ring.count]
                        ring[index] = CGPoint(x: (a.x + 2 * b.x + c.x) / 4,
                                              y: (a.y + 2 * b.y + c.y) / 4)
                    }
                }
                func middle(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
                    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
                }
                waterPath.move(to: middle(ring.last!, ring[0]))
                for index in ring.indices {
                    waterPath.addQuadCurve(to: middle(ring[index], ring[(index + 1) % ring.count]),
                                           control: ring[index])
                }
                waterPath.closeSubpath()
            }
            builtWaterPaths.append(waterPath)
            context.setFillColor((wetland ? palette.wetland : palette.water).cgColor)
            context.addPath(waterPath)
            context.fillPath()
        }
        waterPaths = builtWaterPaths
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

    private func drawWatershedBoundaries(in context: CGContext, color: UIColor) {
        let hydrology = terrain.hydrology
        guard hydrology.hasData else { return }
        let cellWidth = MapScale.canvasWidth / Double(hydrology.gridWidth - 1)
        let cellHeight = MapScale.canvasHeight / Double(hydrology.gridHeight - 1)

        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(0.75)
        context.setLineCap(.butt)
        context.setLineJoin(.miter)
        context.beginPath()
        for row in 0..<hydrology.gridHeight {
            for column in 0..<hydrology.gridWidth {
                guard let current = hydrology.watershedID(column: column, row: row) else {
                    continue
                }
                if column + 1 < hydrology.gridWidth,
                   let right = hydrology.watershedID(column: column + 1, row: row),
                   right != current {
                    let x = (Double(column) + 0.5) * cellWidth
                    context.move(to: CGPoint(x: x, y: Double(row) * cellHeight))
                    context.addLine(to: CGPoint(x: x, y: Double(row + 1) * cellHeight))
                }
                if row + 1 < hydrology.gridHeight,
                   let bottom = hydrology.watershedID(column: column, row: row + 1),
                   bottom != current {
                    let y = (Double(row) + 0.5) * cellHeight
                    context.move(to: CGPoint(x: Double(column) * cellWidth, y: y))
                    context.addLine(to: CGPoint(x: Double(column + 1) * cellWidth, y: y))
                }
            }
        }
        context.strokePath()
        context.restoreGState()
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
            guard let levelRoads = roadsByLevel[level] else { continue }
            for road in levelRoads {
                drawRoadCasing(road: road, in: context)
            }
        }
        for level in RoadLevel.allCases {
            guard let levelRoads = roadsByLevel[level] else { continue }
            for road in levelRoads {
                drawRoadSurface(road: road, in: context)
            }
        }
        drawStructureTransitionMarkers(in: context)
    }

    private func drawInterchanges(in context: CGContext) {
        let rampIDs = rampSourceRoadIDs
        for road in roads where rampIDs.contains(road.sourceRoadID) {
            drawRampDirection(for: road, in: context)
        }

        guard isEditingInterchange else { return }
        for relation in selectableInterchangeCrossings {
            let isSelected = relation.id == selectedInterchangeCrossingID
            let radius = (isSelected ? 9.0 : 7.0) / Double(zoomScale)
            let center = relation.point
            let path = CGMutablePath()
            path.move(to: CGPoint(x: center.x, y: center.y - radius))
            path.addLine(to: CGPoint(x: center.x + radius, y: center.y))
            path.addLine(to: CGPoint(x: center.x, y: center.y + radius))
            path.addLine(to: CGPoint(x: center.x - radius, y: center.y))
            path.closeSubpath()

            context.saveGState()
            context.setFillColor(
                (
                    isSelected
                        ? UIColor.systemTeal.withAlphaComponent(0.92)
                        : UIColor.systemBackground.withAlphaComponent(0.88)
                ).cgColor
            )
            context.addPath(path)
            context.fillPath()
            context.setStrokeColor(
                (
                    isSelected
                        ? UIColor.white
                        : UIColor.systemTeal
                ).cgColor
            )
            context.setLineWidth((isSelected ? 2.5 : 2) / zoomScale)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }

        for interchange in interchanges {
            for ramp in interchange.ramps
            where ramp.id == selectedRampID
                || interchangeMatchesSelectedCrossing(interchange) {
                drawRampTerminal(
                    ramp.start.lastKnownPoint,
                    isSelected: ramp.id == selectedRampID,
                    in: context
                )
                drawRampTerminal(
                    ramp.end.lastKnownPoint,
                    isSelected: ramp.id == selectedRampID,
                    in: context
                )
            }
        }
    }

    private func drawRailwayStations(in context: CGContext) {
        guard !railwayStations.isEmpty else { return }
        let badgeRadius: CGFloat = max(5, 7.5 / zoomScale)
        let innerRadius: CGFloat = max(2, 3 / zoomScale)
        let strokeWidth: CGFloat = max(1.2, 1.8 / zoomScale)

        for station in railwayStations {
            let center = CGPoint(x: station.point.x, y: station.point.y)
            let isSelected = selectedStationID == station.id

            context.saveGState()

            // Station circle badge shadow
            context.setShadow(
                offset: CGSize(width: 0, height: 1.5 / zoomScale),
                blur: 3 / zoomScale,
                color: UIColor.black.withAlphaComponent(0.25).cgColor
            )

            // Outer ring
            let circleRect = CGRect(
                x: center.x - badgeRadius,
                y: center.y - badgeRadius,
                width: badgeRadius * 2,
                height: badgeRadius * 2
            )
            context.setFillColor(UIColor.systemBackground.cgColor)
            context.fillEllipse(in: circleRect)

            context.setStrokeColor(
                isSelected ? UIColor.systemOrange.cgColor : UIColor(red: 0.22, green: 0.25, blue: 0.28, alpha: 1).cgColor
            )
            context.setLineWidth(isSelected ? strokeWidth * 1.5 : strokeWidth)
            context.strokeEllipse(in: circleRect)

            // Inner dot
            let innerRect = CGRect(
                x: center.x - innerRadius,
                y: center.y - innerRadius,
                width: innerRadius * 2,
                height: innerRadius * 2
            )
            context.setFillColor(
                isSelected ? UIColor.systemOrange.cgColor : UIColor(red: 0.22, green: 0.25, blue: 0.28, alpha: 1).cgColor
            )
            context.fillEllipse(in: innerRect)

            // Station name label
            let fontSize: CGFloat = max(11, 13 / zoomScale)
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: isSelected ? UIColor.systemOrange : UIColor.label
            ]
            let attributedText = NSAttributedString(string: station.name, attributes: attributes)
            let textSize = attributedText.size()
            let labelOrigin = CGPoint(
                x: center.x - textSize.width / 2,
                y: center.y + badgeRadius + 4 / zoomScale
            )

            // Pill background behind label for contrast
            let bgRect = CGRect(
                x: labelOrigin.x - 5 / zoomScale,
                y: labelOrigin.y - 2 / zoomScale,
                width: textSize.width + 10 / zoomScale,
                height: textSize.height + 4 / zoomScale
            )
            let pillPath = UIBezierPath(roundedRect: bgRect, cornerRadius: 4 / zoomScale)
            context.setFillColor(UIColor.systemBackground.withAlphaComponent(0.88).cgColor)
            context.addPath(pillPath.cgPath)
            context.fillPath()

            UIGraphicsPushContext(context)
            attributedText.draw(at: labelOrigin)
            UIGraphicsPopContext()

            context.restoreGState()
        }
    }

    private func drawReferenceOverlay(in context: CGContext) {
        guard let overlay = referenceOverlay,
              overlay.isVisible,
              overlay.opacity > 0.01,
              let image = cachedOverlayImage else { return }

        context.saveGState()
        context.setAlpha(CGFloat(overlay.opacity))
        let rect = CGRect(
            x: overlay.bounds.count >= 4 ? overlay.bounds[0] : 0,
            y: overlay.bounds.count >= 4 ? overlay.bounds[1] : 0,
            width: overlay.bounds.count >= 4 ? overlay.bounds[2] : 1600,
            height: overlay.bounds.count >= 4 ? overlay.bounds[3] : 1200
        )
        context.translateBy(x: 0, y: rect.origin.y * 2 + rect.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: rect)
        context.restoreGState()
    }

    private func nearestEndpoint(to canvasPoint: RoadPoint) -> RoadPoint? {
        let maxDistance = 24.0 / zoomScale
        var best: RoadPoint?
        var bestDist = maxDistance
        for road in roads {
            guard let first = road.points.first, let last = road.points.last else { continue }
            let d1 = canvasPoint.distance(to: first)
            if d1 < bestDist {
                bestDist = d1
                best = first
            }
            let d2 = canvasPoint.distance(to: last)
            if d2 < bestDist {
                bestDist = d2
                best = last
            }
        }
        return best
    }

    private func drawHoverReticle(in context: CGContext) {
        guard let hoverLocation, activeStroke.isEmpty else { return }
        context.saveGState()

        let reticleRadius: CGFloat
        let strokeColor: UIColor
        if isErasing {
            reticleRadius = 18
            strokeColor = UIColor.systemRed.withAlphaComponent(0.65)
        } else if isSelecting {
            reticleRadius = 14
            strokeColor = UIColor.systemBlue.withAlphaComponent(0.65)
        } else {
            reticleRadius = max(6, (selectedKind.screenWidth + 4) * zoomScale / 2)
            strokeColor = UIColor.systemOrange.withAlphaComponent(0.75)
        }

        let circleRect = CGRect(
            x: hoverLocation.x - reticleRadius,
            y: hoverLocation.y - reticleRadius,
            width: reticleRadius * 2,
            height: reticleRadius * 2
        )
        context.setStrokeColor(strokeColor.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: circleRect)

        let dotRadius: CGFloat = 2.0
        context.setFillColor(strokeColor.cgColor)
        context.fillEllipse(in: CGRect(
            x: hoverLocation.x - dotRadius,
            y: hoverLocation.y - dotRadius,
            width: dotRadius * 2,
            height: dotRadius * 2
        ))

        if !isErasing && !isSelecting {
            let wp = worldPoint(for: hoverLocation)
            if let snapTarget = nearestEndpoint(to: wp) {
                let snapScreen = screenPoint(for: snapTarget)
                let snapRadius: CGFloat = 10
                context.setStrokeColor(UIColor.systemGreen.cgColor)
                context.setLineWidth(2.0)
                context.strokeEllipse(in: CGRect(
                    x: snapScreen.x - snapRadius,
                    y: snapScreen.y - snapRadius,
                    width: snapRadius * 2,
                    height: snapRadius * 2
                ))
            }
        }

        context.restoreGState()
    }

    private func interchangeMatchesSelectedCrossing(
        _ interchange: RoadInterchange
    ) -> Bool {
        guard let selectedInterchangeCrossingID,
              let relation = relations.first(where: {
                  $0.id == selectedInterchangeCrossingID
              }) else {
            return false
        }
        return Set([
            interchange.anchor.upperSourceRoadID,
            interchange.anchor.lowerSourceRoadID,
        ]) == Set([relation.firstRoadID, relation.secondRoadID])
            && interchange.anchor.lastKnownPoint.distance(to: relation.point)
                <= max(1, mapScale.canvasDistance(forMeters: 30))
    }

    private func drawRampDirection(
        for road: RoadSegment,
        in context: CGContext
    ) {
        guard let sample = midpointAndTangent(of: road.points) else { return }
        let directions: [Double] = switch road.direction {
        case .forward: [1]
        case .reverse: [-1]
        case .bidirectional: [-1, 1]
        }
        for (index, direction) in directions.enumerated() {
            let tangent = sample.tangent * direction
            let normal = RoadPoint(x: -tangent.y, y: tangent.x)
            let alongOffset = directions.count == 2
                ? (index == 0 ? -5.0 : 5.0) / Double(zoomScale)
                : 0
            let center = sample.point + tangent * alongOffset
            let length = 8 / Double(zoomScale)
            let halfWidth = 4 / Double(zoomScale)
            let tip = center + tangent * length
            let base = center - tangent * (length * 0.45)
            let path = CGMutablePath()
            path.move(to: tip.cgPoint)
            path.addLine(to: (base + normal * halfWidth).cgPoint)
            path.addLine(to: (base - normal * halfWidth).cgPoint)
            path.closeSubpath()
            context.saveGState()
            context.setFillColor(
                UIColor.systemBackground.withAlphaComponent(0.94).cgColor
            )
            context.addPath(path)
            context.fillPath()
            context.setStrokeColor(
                UIColor.systemTeal.withAlphaComponent(0.9).cgColor
            )
            context.setLineWidth(1.2 / zoomScale)
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawRampTerminal(
        _ point: RoadPoint,
        isSelected: Bool,
        in context: CGContext
    ) {
        let radius = (isSelected ? 6.0 : 5.0) / Double(zoomScale)
        let rectangle = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        context.saveGState()
        context.setFillColor(
            (
                isSelected
                    ? UIColor.systemTeal
                    : UIColor.systemGreen
            ).cgColor
        )
        context.fillEllipse(in: rectangle)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(2 / zoomScale)
        context.strokeEllipse(in: rectangle)
        context.restoreGState()
    }

    private func midpointAndTangent(
        of points: [RoadPoint]
    ) -> (point: RoadPoint, tangent: RoadPoint)? {
        guard points.count >= 2 else { return nil }
        let lengths = zip(points, points.dropFirst()).map {
            $0.distance(to: $1)
        }
        let total = lengths.reduce(0, +)
        guard total.isFinite, total > 1e-9 else { return nil }
        var remaining = total / 2
        for index in lengths.indices {
            let length = lengths[index]
            guard length > 1e-9 else { continue }
            let start = points[index]
            let end = points[index + 1]
            if remaining <= length {
                let unit = (end - start) * (1 / length)
                return (
                    point: start + (end - start) * (remaining / length),
                    tangent: unit
                )
            }
            remaining -= length
        }
        return nil
    }

    private func drawBridgePiers(
        _ structures: [RoadEngineeringStructure],
        alpha: CGFloat,
        in context: CGContext
    ) {
        let lodStep = zoomScale < 0.32 ? 3 : (zoomScale < 0.5 ? 2 : 1)
        for structure in structures where structure.structure == .bridge {
            for (index, pier) in structure.bridgePiers.enumerated()
            where index.isMultiple(of: lodStep) {
                let normal = RoadPoint(
                    x: -pier.tangent.y,
                    y: pier.tangent.x
                )
                let halfLength = (
                    structure.roadKind.screenWidth
                        + structure.roadKind.casingWidth + 8
                ) / (2 * zoomScale)
                let start = CGPoint(
                    x: pier.point.x - normal.x * halfLength,
                    y: pier.point.y - normal.y * halfLength
                )
                let end = CGPoint(
                    x: pier.point.x + normal.x * halfLength,
                    y: pier.point.y + normal.y * halfLength
                )

                context.saveGState()
                context.setLineCap(.round)
                context.setStrokeColor(
                    UIColor.black.withAlphaComponent(0.3 * alpha).cgColor
                )
                context.setLineWidth(4 / zoomScale)
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                context.setStrokeColor(
                    UIColor.systemCyan.withAlphaComponent(0.9 * alpha).cgColor
                )
                context.setLineWidth(1.5 / zoomScale)
                context.move(to: start)
                context.addLine(to: end)
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private func drawTunnelPortals(
        _ structures: [RoadEngineeringStructure],
        alpha: CGFloat,
        in context: CGContext
    ) {
        for structure in structures where structure.structure == .tunnel {
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
                let halfWidth = (
                    structure.roadKind.screenWidth
                        + structure.roadKind.casingWidth + 8
                ) / (2 * zoomScale)
                let depth = 5 / zoomScale
                let mouthLeft = portal.point + normal * halfWidth
                let mouthRight = portal.point - normal * halfWidth
                let outerLeft = mouthLeft + outward * depth
                let outerRight = mouthRight + outward * depth
                let path = CGMutablePath()
                path.move(to: mouthLeft.cgPoint)
                path.addLine(to: outerLeft.cgPoint)
                path.addLine(to: outerRight.cgPoint)
                path.addLine(to: mouthRight.cgPoint)

                context.saveGState()
                context.setLineCap(.round)
                context.setLineJoin(.round)
                context.setStrokeColor(
                    currentRoadPalette.casing.withAlphaComponent(0.9 * alpha).cgColor
                )
                context.setLineWidth(5 / zoomScale)
                context.addPath(path)
                context.strokePath()
                context.setStrokeColor(
                    UIColor.systemPurple.withAlphaComponent(0.95 * alpha).cgColor
                )
                context.setLineWidth(2 / zoomScale)
                context.addPath(path)
                context.strokePath()
                context.restoreGState()
            }
        }
    }

    private func updateRoadPathCache() {
        let currentIDs = Set(roads.map(\.id))
        roadPathCache = roadPathCache.filter { currentIDs.contains($0.key) }
        for road in roads {
            if let cached = roadPathCache[road.id], cached.segment == road {
                continue
            }
            if let path = buildRoadPath(for: road) {
                roadPathCache[road.id] = (road, path)
            }
        }
    }

    private func buildRoadPath(for road: RoadSegment) -> CGPath? {
        guard let first = road.points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first.cgPoint)
        for point in road.points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }
        return path
    }

    private func roadPath(for road: RoadSegment) -> CGPath? {
        if let cached = roadPathCache[road.id], cached.segment == road {
            return cached.path
        }
        if let path = buildRoadPath(for: road) {
            roadPathCache[road.id] = (road, path)
            return path
        }
        return nil
    }

    private func drawRoadCasing(road: RoadSegment, in context: CGContext) {
        guard let path = roadPath(for: road) else { return }
        let widthFactor = rampSourceRoadIDs.contains(road.sourceRoadID)
            ? 0.78
            : 1.0

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(currentRoadPalette.casing.cgColor)
        context.setLineWidth(
            (road.kind.screenWidth + road.kind.casingWidth)
                * widthFactor / zoomScale
        )
        if road.structure == .tunnel {
            context.setLineDash(phase: 0, lengths: [8 / zoomScale, 5 / zoomScale])
        }
        if road.structure == .bridge {
            context.setStrokeColor(UIColor.systemCyan.withAlphaComponent(0.72).cgColor)
        }
        if road.structure == .bridge || road.structure == .elevated {
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

    private func drawRoadSurface(road: RoadSegment, in context: CGContext) {
        guard let path = roadPath(for: road) else { return }
        let widthFactor = rampSourceRoadIDs.contains(road.sourceRoadID)
            ? 0.78
            : 1.0

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(
            currentRoadPalette.color(for: road.kind, level: road.level).cgColor
        )
        context.setLineWidth(road.kind.screenWidth * widthFactor / zoomScale)
        if road.structure == .tunnel {
            context.setLineDash(phase: 0, lengths: [8 / zoomScale, 5 / zoomScale])
        }
        if road.structure == .bridge || road.structure == .elevated {
            context.setShadow(
                offset: CGSize(width: 0, height: 2 / zoomScale),
                blur: 2 / zoomScale,
                color: UIColor.black.withAlphaComponent(0.22).cgColor
            )
        }
        context.addPath(path)
        context.strokePath()

        if road.structure == .bridge {
            context.setStrokeColor(UIColor.white.withAlphaComponent(0.72).cgColor)
            context.setLineWidth(max(0.8, 1.2 / zoomScale))
            context.setLineDash(phase: 0, lengths: [2 / zoomScale, 7 / zoomScale])
            context.addPath(path)
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawStructureCandidatePreview(in context: CGContext) {
        guard let review = pendingStructureReview else { return }

        for span in review.resolvedSpans where span.structure != .ground {
            guard let first = span.points.first else { continue }
            let path = CGMutablePath()
            path.move(to: first.cgPoint)
            for point in span.points.dropFirst() {
                path.addLine(to: point.cgPoint)
            }

            let color: UIColor = switch span.structure {
            case .ground:
                .clear
            case .bridge:
                .systemCyan
            case .tunnel:
                .systemPurple
            case .elevated:
                .systemOrange
            }
            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(color.withAlphaComponent(0.85).cgColor)
            context.setLineWidth((span.roadKind.screenWidth + 6) / zoomScale)
            context.setLineDash(phase: 0, lengths: [10 / zoomScale, 5 / zoomScale])
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawConstructionIssues(in context: CGContext) {
        for issue in constructionIssues {
            guard let first = issue.centerline.first else { continue }
            let path = CGMutablePath()
            path.move(to: first.cgPoint)
            for point in issue.centerline.dropFirst() {
                path.addLine(to: point.cgPoint)
            }

            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(
                currentRoadPalette.casing.withAlphaComponent(0.9).cgColor
            )
            context.setLineWidth(
                (issue.roadKind.screenWidth + 7) / zoomScale
            )
            context.addPath(path)
            context.strokePath()

            context.setStrokeColor(
                UIColor.systemRed.withAlphaComponent(0.92).cgColor
            )
            context.setLineWidth(
                (issue.roadKind.screenWidth + 3) / zoomScale
            )
            context.setLineDash(
                phase: 0,
                lengths: [8 / zoomScale, 5 / zoomScale]
            )
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }
    }

    private func drawStructureTransitionMarkers(in context: CGContext) {
        let roadsBySource = Dictionary(grouping: roads, by: \.sourceRoadID)
        var renderedPoints = Set<RoadPoint>()

        for sourceRoads in roadsBySource.values {
            for firstIndex in sourceRoads.indices {
                for secondIndex in sourceRoads.indices where secondIndex > firstIndex {
                    let first = sourceRoads[firstIndex]
                    let second = sourceRoads[secondIndex]
                    guard first.structure != second.structure,
                          let point = sharedEndpoint(first, second),
                          renderedPoints.insert(point).inserted
                    else { continue }

                    let structure = first.structure == .ground
                        ? second.structure
                        : first.structure
                    guard structure != .tunnel else { continue }
                    let color: UIColor = switch structure {
                    case .ground:
                        .secondaryLabel
                    case .bridge:
                        .systemCyan
                    case .tunnel:
                        .systemPurple
                    case .elevated:
                        .systemOrange
                    }
                    let radius = 5 / zoomScale
                    let markerRect = CGRect(
                        x: point.x - radius,
                        y: point.y - radius,
                        width: radius * 2,
                        height: radius * 2
                    )
                    context.saveGState()
                    context.setFillColor(currentRoadPalette.casing.cgColor)
                    context.fillEllipse(in: markerRect)
                    context.setStrokeColor(color.cgColor)
                    context.setLineWidth(2 / zoomScale)
                    context.strokeEllipse(in: markerRect)
                    context.restoreGState()
                }
            }
        }
    }

    private func sharedEndpoint(
        _ first: RoadSegment,
        _ second: RoadSegment
    ) -> RoadPoint? {
        let firstEndpoints = [first.points.first, first.points.last].compactMap { $0 }
        let secondEndpoints = [second.points.first, second.points.last].compactMap { $0 }
        return firstEndpoints.first { firstPoint in
            secondEndpoints.contains { firstPoint.distance(to: $0) < 0.001 }
        }
    }

    private func drawRoadSelection(in context: CGContext) {
        let displayedSourceRoadIDs: Set<UUID>
        if isSelecting {
            displayedSourceRoadIDs = selectedSourceRoadIDs
        } else if isEditingInterchange, let selectedRampID {
            displayedSourceRoadIDs = [selectedRampID]
        } else {
            return
        }

        for road in roads
        where displayedSourceRoadIDs.contains(road.sourceRoadID) {
            let points = road.points.map {
                selectionPreviewPoint($0, sourceRoadID: road.sourceRoadID)
            }
            guard let first = points.first else { continue }
            let path = CGMutablePath()
            path.move(to: first.cgPoint)
            for point in points.dropFirst() {
                path.addLine(to: point.cgPoint)
            }

            context.saveGState()
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.setStrokeColor(
                UIColor.systemBackground.withAlphaComponent(0.9).cgColor
            )
            context.setLineWidth(
                (road.kind.screenWidth + road.kind.casingWidth + 10) / zoomScale
            )
            context.addPath(path)
            context.strokePath()
            context.setStrokeColor(
                UIColor.systemTeal.withAlphaComponent(0.86).cgColor
            )
            context.setLineWidth(
                (road.kind.screenWidth + road.kind.casingWidth + 5) / zoomScale
            )
            context.addPath(path)
            context.strokePath()
            context.restoreGState()
        }

        if isSelecting,
           selectedSourceRoadIDs.count == 1,
           let sourceRoadID = selectedSourceRoadIDs.first {
            drawSelectionControlPoints(
                for: sourceRoadID,
                in: context
            )
        }

        if isSelecting,
           case let .marquee(origin, current) = selectionInteraction {
            let rectangle = CGRect(
                x: min(origin.x, current.x),
                y: min(origin.y, current.y),
                width: abs(current.x - origin.x),
                height: abs(current.y - origin.y)
            )
            context.saveGState()
            context.setFillColor(
                UIColor.systemTeal.withAlphaComponent(0.12).cgColor
            )
            context.fill(rectangle)
            context.setStrokeColor(
                UIColor.systemTeal.withAlphaComponent(0.9).cgColor
            )
            context.setLineWidth(2 / zoomScale)
            context.setLineDash(
                phase: 0,
                lengths: [8 / zoomScale, 5 / zoomScale]
            )
            context.stroke(rectangle)
            context.restoreGState()
        }
    }

    private func drawSelectionControlPoints(
        for sourceRoadID: UUID,
        in context: CGContext
    ) {
        for candidate in visibleControlPoints(for: sourceRoadID) {
            let point = selectionPreviewPoint(
                candidate,
                sourceRoadID: sourceRoadID
            )

            let radius = 6 / zoomScale
            let rectangle = CGRect(
                x: point.x - radius,
                y: point.y - radius,
                width: radius * 2,
                height: radius * 2
            )
            context.saveGState()
            context.setFillColor(
                UIColor.systemBackground.withAlphaComponent(0.98).cgColor
            )
            context.fillEllipse(in: rectangle)
            context.setStrokeColor(UIColor.systemTeal.cgColor)
            context.setLineWidth(2 / zoomScale)
            context.strokeEllipse(in: rectangle)
            context.restoreGState()
        }
    }

    private func selectionPreviewPoint(
        _ point: RoadPoint,
        sourceRoadID: UUID
    ) -> RoadPoint {
        switch selectionInteraction {
        case let .translating(origin, current, sourceRoadIDs)
        where sourceRoadIDs.contains(sourceRoadID):
            return point + (current - origin)

        case let .deforming(
            editedSourceRoadID,
            originalPoint,
            current,
            _
        ) where editedSourceRoadID == sourceRoadID
            && point.distance(to: originalPoint) <= 1e-6:
            return current

        default:
            return point
        }
    }

    private func drawPendingRamp(in context: CGContext) {
        guard let plan = pendingRampPlan else { return }
        context.saveGState()
        context.setStrokeColor(UIColor.systemOrange.cgColor)
        context.setLineWidth(5 / zoomScale)
        context.setLineCap(.round)
        context.setLineDash(phase: 0, lengths: [9 / zoomScale, 5 / zoomScale])
        for segment in plan.roadSegments {
            guard let first = segment.points.first else { continue }
            context.move(to: first.cgPoint)
            for point in segment.points.dropFirst() { context.addLine(to: point.cgPoint) }
            context.strokePath()
        }
        context.restoreGState()
    }

    private func drawActiveStroke(in context: CGContext) {
        guard !isSelecting, let first = activeStroke.first else { return }
        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(
            isErasing
                ? UIColor.systemRed.withAlphaComponent(0.35).cgColor
                : (
                    isEditingInterchange
                        ? UIColor.systemOrange
                        : selectedKind.uiColor(for: selectedLevel)
                ).withAlphaComponent(0.62).cgColor
        )
        let drawingWidth = isEditingInterchange
            ? selectedKind.screenWidth * 0.78
            : selectedKind.screenWidth
        context.setLineWidth((isErasing ? 36 : drawingWidth) / zoomScale)
        context.move(to: first.cgPoint)
        for point in activeStroke.dropFirst() {
            context.addLine(to: point.cgPoint)
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawScaleBar(in context: CGContext) {
        let targetWidth = min(132, bounds.width * 0.24)
        let metersPerScreenPoint = mapScale.metersPerPoint / Double(zoomScale)
        let distance = niceScaleDistance(
            atMost: Double(targetWidth) * metersPerScreenPoint
        )
        guard distance > 0 else { return }

        let barWidth = CGFloat(distance / metersPerScreenPoint)
        let origin = CGPoint(
            x: safeAreaInsets.left + 18,
            y: max(safeAreaInsets.top + 18, 76)
        )
        context.saveGState()
        let startX = origin.x
        let endX = startX + barWidth
        let barY = origin.y + 29
        context.setStrokeColor(UIColor.label.withAlphaComponent(0.82).cgColor)
        context.setLineWidth(2)
        context.setLineCap(.round)
        context.beginPath()
        context.move(to: CGPoint(x: startX, y: barY))
        context.addLine(to: CGPoint(x: endX, y: barY))
        context.move(to: CGPoint(x: startX, y: barY - 5))
        context.addLine(to: CGPoint(x: startX, y: barY + 3))
        context.move(to: CGPoint(x: endX, y: barY - 5))
        context.addLine(to: CGPoint(x: endX, y: barY + 3))
        context.strokePath()
        context.restoreGState()

        let label = formattedScaleDistance(distance) as NSString
        label.draw(
            at: origin,
            withAttributes: [
                .font: UIFont.monospacedDigitSystemFont(
                    ofSize: 12,
                    weight: .semibold
                ),
                .foregroundColor: UIColor.label.withAlphaComponent(0.88),
            ]
        )
    }

    private func niceScaleDistance(atMost distance: Double) -> Double {
        guard distance > 0 else { return 0 }
        let magnitude = pow(10, floor(log10(distance)))
        let normalized = distance / magnitude
        let multiplier: Double
        if normalized >= 5 {
            multiplier = 5
        } else if normalized >= 2 {
            multiplier = 2
        } else {
            multiplier = 1
        }
        return multiplier * magnitude
    }

    private func formattedScaleDistance(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            return kilometers.formatted(
                .number.precision(
                    .fractionLength(kilometers.rounded() == kilometers ? 0 : 1)
                )
            ) + " km"
        }
        return "\(Int(meters.rounded())) m"
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

private final class CanvasAccessibilityElement: UIAccessibilityElement {
    var onActivate: (() -> Bool)?

    override func accessibilityActivate() -> Bool {
        onActivate?() ?? false
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

    var wetland: UIColor {
        plain.mixed(with: water, amount: 0.44).mixed(with: lowland, amount: 0.2)
    }

    var watershed: UIColor {
        contour.withAlphaComponent(0.48)
    }

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
        let p = palette
        return TerrainPalette(water: UIColor(cgColor: p.water.cgColor), plain: UIColor(cgColor: p.plain.cgColor), lowland: UIColor(cgColor: p.lowland.cgColor), hill: UIColor(cgColor: p.hill.cgColor), mountain: UIColor(cgColor: p.mountain.cgColor), grid: UIColor(cgColor: p.grid.cgColor), contour: UIColor(cgColor: p.contour.cgColor), shoreline: UIColor(cgColor: p.shoreline.cgColor))
    }
    var roadPalette: RoadPalette {
        let p = palette
        return RoadPalette(motorway: UIColor(cgColor: p.motorway.cgColor), arterial: UIColor(cgColor: p.arterial.cgColor), street: UIColor(cgColor: p.street.cgColor), railway: UIColor(cgColor: p.railway.cgColor), casing: UIColor(cgColor: p.roadCasing.cgColor))
    }
}

private struct RoadPalette {
    let motorway: UIColor
    let arterial: UIColor
    let street: UIColor
    let railway: UIColor
    let casing: UIColor

    func color(for kind: RoadKind, level: RoadLevel) -> UIColor {
        let color: UIColor = switch kind {
        case .motorway: motorway
        case .arterial: arterial
        case .street: street
        case .railway: railway
        }
        return level == .tunnel ? color.withAlphaComponent(0.55) : color
    }
}

private extension RoadPoint {
    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

private extension MapScale {
    var accessibilityDescription: String {
        "地图范围 \(Int(widthMeters.rounded())) × \(Int(heightMeters.rounded())) 米"
    }
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

    var casingWidth: CGFloat {
        switch self {
        case .motorway: 4
        case .arterial: 3
        case .street: 2
        case .railway: 1.5
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

/// Upright screen control; only its north pointer follows the map's camera heading.
private final class CanvasCompassControl: UIControl {
    var heading: Double = 0 {
        didSet {
            let degrees = (360 - heading * 180 / .pi).truncatingRemainder(dividingBy: 360)
            accessibilityValue = String(format: "地图朝向 %.0f 度", degrees)
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityLabel = "指南针，恢复指北"
        accessibilityHint = "双击将地图转为北方朝上"
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let circle = bounds.insetBy(dx: 2, dy: 2)
        context.setFillColor(UIColor.secondarySystemBackground.cgColor)
        context.fillEllipse(in: circle)
        context.setStrokeColor(UIColor.separator.cgColor)
        context.setLineWidth(1)
        context.strokeEllipse(in: circle)
        context.translateBy(x: bounds.midX, y: bounds.midY)
        context.rotate(by: heading)
        context.setFillColor(UIColor.systemRed.cgColor)
        context.move(to: CGPoint(x: 0, y: -16))
        context.addLine(to: CGPoint(x: -5, y: 3))
        context.addLine(to: CGPoint(x: 5, y: 3))
        context.closePath()
        context.fillPath()
        context.setFillColor(UIColor.secondaryLabel.cgColor)
        context.move(to: CGPoint(x: 0, y: 16))
        context.addLine(to: CGPoint(x: -5, y: 3))
        context.addLine(to: CGPoint(x: 5, y: 3))
        context.closePath()
        context.fillPath()
    }
}

private final class CanvasZoomAccessibilityElement: UIAccessibilityElement {
    var adjust: ((Bool) -> Void)?
    override func accessibilityIncrement() { adjust?(true) }
    override func accessibilityDecrement() { adjust?(false) }
}

/// MapKit owns camera movement, deceleration, scale and compass. The transparent
/// canvas keeps the same road editing and persistence model as generated maps.
final class RoadMapWorkspaceView: UIView, MKMapViewDelegate {
    let canvas = RoadCanvasView()
    var onViewportChanged: ((MapExportViewport) -> Void)?
    private let map = MKMapView()
    private var usesAppleMap = false
    private var fittedCameraDistance = 0.0
    private var awaitsFittedCamera = false
    private var isSettlingCamera = false
    private var lastZoomHintTime: CFTimeInterval = 0

    private lazy var nativeCompass = MKCompassButton(mapView: map)
    private lazy var nativeScale = MKScaleView(mapView: map)
    private var displayedProjectID: UUID?
    private var geographicBounds: GeoBounds?
    private var worldMetersPerPoint = 1.0
    private var needsInitialRegion = false
    private lazy var editingTouches = MapEditingTouches(canvas: canvas)

    override init(frame: CGRect) {
        super.init(frame: frame)
        map.delegate = self
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
        map.accessibilityIdentifier = "native-map"
        addSubview(map)
        addSubview(canvas)
        map.addGestureRecognizer(editingTouches)
        addSubview(nativeCompass)
        addSubview(nativeScale)
        nativeCompass.compassVisibility = .visible
        nativeCompass.accessibilityIdentifier = "native-map-compass"
        nativeScale.scaleVisibility = .visible
        nativeScale.accessibilityIdentifier = "native-map-scale"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(project: RoadProject) {
        usesAppleMap = project.realWorldMap?.source == .appleMaps
        canvas.nativeMap = map
        canvas.useNativeNavigation(true)
        configureNativeNavigation(in: map)
        // The generated world is opaque above the entire native map, including
        // its unused basemap chrome. Apple projects expose the actual basemap.
        if !map.overlays.isEmpty { map.removeOverlays(map.overlays) }
        accessibilityElements = usesAppleMap
            ? [map, canvas, nativeCompass, nativeScale] : [canvas, nativeCompass, nativeScale]
        let area = project.realWorldMap?.bounds ?? Self.syntheticBounds(for: project.mapScale)
        let targetScale = project.mapScale.metersPerPoint
        if displayedProjectID != project.id || geographicBounds != area || worldMetersPerPoint != targetScale {
            displayedProjectID = project.id
            geographicBounds = area
            worldMetersPerPoint = targetScale
            needsInitialRegion = true
        }
        setNeedsLayout()
        synchronizeCanvas()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        map.frame = bounds
        canvas.frame = bounds
        configureNativeNavigation(in: map)
        let inset = safeAreaInsets
        let controlsY = max(inset.top+180, bounds.height-inset.bottom-190)
        nativeCompass.frame = CGRect(x: inset.left + 16, y: controlsY, width: 44, height: 44)
        nativeScale.frame = CGRect(x: inset.left + 16, y: controlsY+54, width: 150, height: 36)
        if needsInitialRegion, bounds.width > 0, bounds.height > 0, let area = geographicBounds {
            needsInitialRegion = false
            let center = CLLocationCoordinate2D(
                latitude: (area.minLatitude + area.maxLatitude) / 2,
                longitude: (area.minLongitude + area.maxLongitude) / 2
            )
            let region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: worldMetersPerPoint * 1200,
                longitudinalMeters: worldMetersPerPoint * 1600
            )
            let boundaryRegion = MKCoordinateRegion(
                center: center,
                latitudinalMeters: worldMetersPerPoint * 1200 * 1.8,
                longitudinalMeters: worldMetersPerPoint * 1600 * 1.8
            )
            map.cameraBoundary = MKMapView.CameraBoundary(coordinateRegion: boundaryRegion)
            map.cameraZoomRange = nil
            fittedCameraDistance = 0
            awaitsFittedCamera = true
            map.setRegion(region, animated: false)
        }
        synchronizeCanvas()
    }

    private func configureNativeNavigation(in view: UIView) {
        let editsWithFinger = canvas.allowsFingerDrawing || canvas.isSelecting || canvas.isEditingInterchange
        for gesture in view.gestureRecognizers ?? [] {
            if let pan = gesture as? UIPanGestureRecognizer {
                pan.minimumNumberOfTouches = editsWithFinger ? 2 : 1
                pan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            } else if gesture is UIPinchGestureRecognizer || gesture is UIRotationGestureRecognizer {
                gesture.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
            }
        }
        for child in view.subviews where child !== canvas {
            configureNativeNavigation(in: child)
        }
    }

    func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
        synchronizeCanvas()
        guard fittedCameraDistance > 0, !isSettlingCamera else { return }
        let distance = map.camera.centerCoordinateDistance
        if (distance > fittedCameraDistance / 0.9 || distance < fittedCameraDistance / 7.95),
           CACurrentMediaTime() - lastZoomHintTime > 2 {
            lastZoomHintTime = CACurrentMediaTime()
            canvas.showMinimumZoomHint(maximum: distance < fittedCameraDistance / 7.95)
        }
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        if awaitsFittedCamera {
            awaitsFittedCamera = false
            fittedCameraDistance = map.camera.centerCoordinateDistance
            map.cameraZoomRange = MKMapView.CameraZoomRange(
                minCenterCoordinateDistance: fittedCameraDistance / 8,
                maxCenterCoordinateDistance: fittedCameraDistance / 0.84)
            let camera = map.camera.copy() as! MKMapCamera
            camera.centerCoordinateDistance = fittedCameraDistance / 1.2
            map.setCamera(camera, animated: false)
            synchronizeCanvas()
            return
        }
        guard fittedCameraDistance > 0, !isSettlingCamera,
              map.camera.centerCoordinateDistance > fittedCameraDistance / 0.9 else { return }
        isSettlingCamera = true
        let camera = map.camera.copy() as! MKMapCamera
        camera.centerCoordinateDistance = fittedCameraDistance / 0.9
        map.setCamera(camera, animated: !UIAccessibility.isReduceMotionEnabled)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isSettlingCamera = false
        }
    }

    private func coordinate(for point: RoadPoint, area: GeoBounds) -> CLLocationCoordinate2D {
        let latitude = (area.minLatitude + area.maxLatitude) / 2
        let center = MKMapPoint(CLLocationCoordinate2D(latitude: latitude,
            longitude: (area.minLongitude + area.maxLongitude) / 2))
        let scale = worldMetersPerPoint / MKMetersPerMapPointAtLatitude(latitude)
        return MKMapPoint(x: center.x+(point.x-800)*scale, y: center.y+(point.y-600)*scale).coordinate
    }

    private func synchronizeCanvas() {
        guard canvas.nativeMap != nil, let area = geographicBounds,
              map.bounds.width > 0, map.bounds.height > 0 else { return }
        let origin = map.convert(coordinate(for: RoadPoint(x: 0, y: 0), area: area), toPointTo: canvas)
        let xAxis = map.convert(coordinate(for: RoadPoint(x: 1600, y: 0), area: area), toPointTo: canvas)
        canvas.followNativeMap(origin: origin, xAxis: xAxis)
        onViewportChanged?(canvas.exportViewport)
    }

    private static func syntheticBounds(for mapScale: MapScale) -> GeoBounds {
        let dy = max(50, mapScale.heightMeters) / 2 / 111_195
        let dx = max(50, mapScale.widthMeters) / 2 / 111_195
        if let bounds = try? GeoBounds(
            minLatitude: max(-80, -dy),
            minLongitude: max(-180, -dx),
            maxLatitude: min(80, dy),
            maxLongitude: min(180, dx)
        ) {
            return bounds
        }
        return try! GeoBounds(minLatitude: -0.1, minLongitude: -0.1, maxLatitude: 0.1, maxLongitude: 0.1)
    }
}


/// Observes editing input without competing with MapKit's native recognizers.
/// The canvas cancels its provisional stroke as soon as a second finger arrives.
private final class MapEditingTouches: UIGestureRecognizer {
    private weak var canvas: RoadCanvasView?

    init(canvas: RoadCanvasView) {
        self.canvas = canvas
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.touchesBegan(touches, with: event)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.touchesMoved(touches, with: event)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.touchesEnded(touches, with: event)
        if event.allTouches?.allSatisfy({ $0.phase == .ended || $0.phase == .cancelled }) == true { state = .failed }
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        canvas?.touchesCancelled(touches, with: event)
        state = .failed
    }
}

