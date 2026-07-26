import PhoenixValleyCore
import SwiftUI
import UIKit

struct RoadCanvasRepresentable: UIViewRepresentable {
    let project: RoadProject
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

    func makeUIView(context: Context) -> RoadCanvasView {
        let view = RoadCanvasView()
        view.onStrokeFinished = onStrokeFinished
        view.onEraseFinished = onEraseFinished
        view.onSelectionChanged = onSelectionChanged
        view.onSelectionMoved = onSelectionMoved
        view.onControlPointMoved = onControlPointMoved
        view.onInterchangeCrossingSelected = onInterchangeCrossingSelected
        view.onRampSelected = onRampSelected
        return view
    }

    func updateUIView(_ view: RoadCanvasView, context: Context) {
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
        view.terrain = project.terrain
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
        view.mapScale = project.mapScale
        view.accessibilityValue = [
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
        view.refreshAccessibilityElements()
        view.setNeedsDisplay()
    }
}

final class RoadCanvasView: UIView, UIGestureRecognizerDelegate {
    private enum SelectionHit {
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
        didSet { if oldValue != terrain { terrainImage = nil } }
    }
    var roads: [RoadSegment] = []
    var constructionIssues: [RoadConstructionIssue] = []
    var engineeringStructures: [RoadEngineeringStructure] = []
    var pendingStructureReview: RoadStructureReviewRecord?
    var pendingEngineeringStructures: [RoadEngineeringStructure] = []
    var interchanges: [RoadInterchange] = []
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
    var mapScale: MapScale = .standard
    var theme: MapTheme = .planning {
        didSet { if oldValue != theme { terrainImage = nil } }
    }
    var showsTerrain = true
    var showsContours = true {
        didSet { if oldValue != showsContours { terrainImage = nil } }
    }
    var showsGrid = true {
        didSet { if oldValue != showsGrid { terrainImage = nil } }
    }
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

    private var activeStroke: [RoadPoint] = []
    private var selectionInteraction: SelectionInteraction = .idle
    private var interchangeTouchOrigin: CGPoint?
    private var activeTouchIdentifier: ObjectIdentifier?
    private var activeNavigationRecognizers: Set<ObjectIdentifier> = []
    private var zoomScale: CGFloat = 1
    private var translation: CGPoint = .zero
    private var hasPositionedInitialMap = false
    private var terrainImage: UIImage?
    private weak var panGesture: UIPanGestureRecognizer?
    private var scaleBarHideWorkItem: DispatchWorkItem?
    private var isScaleBarVisible = false
    private var minimumZoomHintHideWorkItem: DispatchWorkItem?
    private var isMinimumZoomHintVisible = false
    private var didShowMinimumZoomHintForGesture = false

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
        isAccessibilityElement = true
        accessibilityLabel = "道路画布"
        accessibilityIdentifier = "road-canvas"
        accessibilityTraits = [.allowsDirectInteraction]

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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !hasPositionedInitialMap, bounds.width > 0, bounds.height > 0 else { return }
        zoomScale = max(bounds.width / 1600, bounds.height / 1200)
        translation = CGPoint(
            x: bounds.midX - 800 * zoomScale,
            y: bounds.midY - 600 * zoomScale
        )
        hasPositionedInitialMap = true
        refreshAccessibilityElements()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let palette = theme.terrainPalette
        context.setFillColor(
            (
                showsTerrain && terrain.scenario.hasOceanBoundary
                    ? palette.water
                    : UIColor.systemBackground
            ).cgColor
        )
        context.fill(bounds)

        context.saveGState()
        context.translateBy(x: translation.x, y: translation.y)
        context.scaleBy(x: zoomScale, y: zoomScale)
        if showsTerrain {
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
        drawRoads(in: context)
        drawInterchanges(in: context)
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
        drawActiveStroke(in: context)
        context.restoreGState()
        if isScaleBarVisible {
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
        } else {
            onStrokeFinished?(completedStroke)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard trackedTouch(in: touches) != nil else { return }
        cancelContentInteraction()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        (gestureRecognizer is UIPanGestureRecognizer
            && otherGestureRecognizer is UIPinchGestureRecognizer)
            || (gestureRecognizer is UIPinchGestureRecognizer
                && otherGestureRecognizer is UIPanGestureRecognizer)
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        updateNavigationState(for: recognizer)
        guard recognizer.state == .began || recognizer.state == .changed else {
            return
        }
        let delta = recognizer.translation(in: self)
        translation.x += delta.x
        translation.y += delta.y
        constrainTranslation()
        recognizer.setTranslation(.zero, in: self)
        refreshAccessibilityElements()
        setNeedsDisplay()
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
        let anchor = recognizer.location(in: self)
        let worldAtAnchor = worldPoint(for: anchor)
        let proposedScale = zoomScale * recognizer.scale
        let nextScale = min(4, max(minimumZoomScale, proposedScale))
        zoomScale = nextScale
        translation = CGPoint(
            x: anchor.x - worldAtAnchor.x * nextScale,
            y: anchor.y - worldAtAnchor.y * nextScale
        )
        constrainTranslation()
        if proposedScale < minimumZoomScale - 0.001 {
            showMinimumZoomHint()
        }
        recognizer.scale = 1
        refreshAccessibilityElements()
        setNeedsDisplay()
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

    private var minimumZoomScale: CGFloat {
        guard bounds.width > 0, bounds.height > 0 else { return 0.2 }
        return min(bounds.width / 1600, bounds.height / 1200) * 0.92
    }

    private func constrainTranslation() {
        let contentWidth = 1600 * zoomScale
        let contentHeight = 1200 * zoomScale
        let overscroll: CGFloat = 36

        if contentWidth <= bounds.width {
            translation.x = (bounds.width - contentWidth) / 2
        } else {
            translation.x = min(
                overscroll,
                max(bounds.width - contentWidth - overscroll, translation.x)
            )
        }

        if contentHeight <= bounds.height {
            translation.y = (bounds.height - contentHeight) / 2
        } else {
            translation.y = min(
                overscroll,
                max(bounds.height - contentHeight - overscroll, translation.y)
            )
        }
    }

    private func showMinimumZoomHint() {
        guard !didShowMinimumZoomHintForGesture else { return }
        didShowMinimumZoomHintForGesture = true
        minimumZoomHintHideWorkItem?.cancel()
        isMinimumZoomHintVisible = true
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIAccessibility.post(
            notification: .announcement,
            argument: "已显示完整可编辑区域，不能再缩小"
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
        let message = "已显示完整可编辑区域"
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
            activeNavigationRecognizers.insert(identifier)
            cancelContentInteraction()
        case .ended, .cancelled, .failed:
            activeNavigationRecognizers.remove(identifier)
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

            case .unselectedRoad:
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
            case .controlPoint:
                return
            case let .selectedRoad(sourceRoadID),
                 let .unselectedRoad(sourceRoadID):
                if selection.contains(sourceRoadID) {
                    selection.remove(sourceRoadID)
                } else {
                    selection.insert(sourceRoadID)
                }
            case .empty:
                selection.removeAll()
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
        Set(interchanges.flatMap(\.ramps).map(\.sourceRoadID))
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
        RoadPoint(
            x: Double((screenPoint.x - translation.x) / zoomScale),
            y: Double((screenPoint.y - translation.y) / zoomScale)
        )
    }

    func refreshAccessibilityElements() {
        guard bounds.width > 0, bounds.height > 0 else {
            accessibilityElements = nil
            return
        }

        var elements: [UIAccessibilityElement] = []
        guard isSelecting || isEditingInterchange else {
            isAccessibilityElement = true
            accessibilityElements = nil
            return
        }
        isAccessibilityElement = false
        if isEditingInterchange {
            accessibilityElements = interchangeAccessibilityElements()
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
        CGPoint(
            x: CGFloat(canvasPoint.x) * zoomScale + translation.x,
            y: CGFloat(canvasPoint.y) * zoomScale + translation.y
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
            context.restoreGState()
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
                    let color = value <= terrain.waterLevel
                        ? palette.water
                        : palette.color(for: value)
                    renderer.cgContext.setFillColor(color.cgColor)
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
                drawRoadCasing(road: road, in: context)
            }
        }
        for level in RoadLevel.allCases {
            for road in roads where road.level == level {
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
                    theme.roadPalette.casing.withAlphaComponent(0.9 * alpha).cgColor
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

    private func roadPath(for road: RoadSegment) -> CGMutablePath? {
        guard let first = road.points.first else { return nil }
        let path = CGMutablePath()
        path.move(to: first.cgPoint)
        for point in road.points.dropFirst() {
            path.addLine(to: point.cgPoint)
        }
        return path
    }

    private func drawRoadCasing(road: RoadSegment, in context: CGContext) {
        guard let path = roadPath(for: road) else { return }
        let widthFactor = rampSourceRoadIDs.contains(road.sourceRoadID)
            ? 0.78
            : 1.0

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setStrokeColor(theme.roadPalette.casing.cgColor)
        context.setLineWidth(
            (road.kind.screenWidth + road.kind.casingWidth)
                * widthFactor / zoomScale
        )
        if road.kind == .railway || road.structure == .tunnel {
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
            theme.roadPalette.color(for: road.kind, level: road.level).cgColor
        )
        context.setLineWidth(road.kind.screenWidth * widthFactor / zoomScale)
        if road.kind == .railway || road.structure == .tunnel {
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
                theme.roadPalette.casing.withAlphaComponent(0.9).cgColor
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
                    context.setFillColor(theme.roadPalette.casing.cgColor)
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
        case .coastal:
            TerrainPalette(
                water: UIColor(red: 0.49, green: 0.77, blue: 0.86, alpha: 1),
                plain: UIColor(red: 0.96, green: 0.91, blue: 0.76, alpha: 1),
                lowland: UIColor(red: 0.84, green: 0.87, blue: 0.67, alpha: 1),
                hill: UIColor(red: 0.78, green: 0.72, blue: 0.54, alpha: 1),
                mountain: UIColor(red: 0.57, green: 0.48, blue: 0.4, alpha: 1),
                grid: UIColor.white.withAlphaComponent(0.14),
                contour: UIColor(red: 0.22, green: 0.38, blue: 0.4, alpha: 0.25),
                shoreline: UIColor(red: 0.12, green: 0.34, blue: 0.42, alpha: 0.55)
            )
        case .midnight:
            TerrainPalette(
                water: UIColor(red: 0.05, green: 0.1, blue: 0.17, alpha: 1),
                plain: UIColor(red: 0.11, green: 0.16, blue: 0.2, alpha: 1),
                lowland: UIColor(red: 0.14, green: 0.22, blue: 0.23, alpha: 1),
                hill: UIColor(red: 0.2, green: 0.27, blue: 0.25, alpha: 1),
                mountain: UIColor(red: 0.3, green: 0.32, blue: 0.28, alpha: 1),
                grid: UIColor.white.withAlphaComponent(0.08),
                contour: UIColor(red: 0.54, green: 0.72, blue: 0.68, alpha: 0.28),
                shoreline: UIColor(red: 0.48, green: 0.7, blue: 0.78, alpha: 0.45)
            )
        case .forest:
            TerrainPalette(
                water: UIColor(red: 0.43, green: 0.68, blue: 0.69, alpha: 1),
                plain: UIColor(red: 0.78, green: 0.84, blue: 0.69, alpha: 1),
                lowland: UIColor(red: 0.58, green: 0.72, blue: 0.5, alpha: 1),
                hill: UIColor(red: 0.42, green: 0.58, blue: 0.38, alpha: 1),
                mountain: UIColor(red: 0.3, green: 0.4, blue: 0.31, alpha: 1),
                grid: UIColor.black.withAlphaComponent(0.05),
                contour: UIColor(red: 0.16, green: 0.3, blue: 0.18, alpha: 0.3),
                shoreline: UIColor(red: 0.12, green: 0.3, blue: 0.28, alpha: 0.5)
            )
        }
    }

    var roadPalette: RoadPalette {
        switch self {
        case .topographic: RoadPalette(motorway: UIColor.white, arterial: UIColor(red: 0.96, green: 0.83, blue: 0.28, alpha: 1), street: UIColor(red: 0.86, green: 0.93, blue: 0.82, alpha: 1), railway: UIColor(red: 0.28, green: 0.2, blue: 0.16, alpha: 1), casing: UIColor(red: 0.18, green: 0.25, blue: 0.22, alpha: 1))
        case .planning: RoadPalette(motorway: UIColor(red: 0.18, green: 0.2, blue: 0.21, alpha: 1), arterial: UIColor(red: 0.32, green: 0.36, blue: 0.37, alpha: 1), street: UIColor(red: 0.72, green: 0.75, blue: 0.73, alpha: 1), railway: UIColor(red: 0.35, green: 0.25, blue: 0.2, alpha: 1), casing: UIColor.white)
        case .ink: RoadPalette(motorway: UIColor(red: 0.08, green: 0.09, blue: 0.1, alpha: 1), arterial: UIColor(red: 0.2, green: 0.22, blue: 0.23, alpha: 1), street: UIColor(red: 0.48, green: 0.5, blue: 0.5, alpha: 1), railway: UIColor.black, casing: UIColor.white)
        case .coastal: RoadPalette(motorway: UIColor(red: 0.16, green: 0.3, blue: 0.36, alpha: 1), arterial: UIColor(red: 0.93, green: 0.52, blue: 0.22, alpha: 1), street: UIColor(red: 0.96, green: 0.88, blue: 0.62, alpha: 1), railway: UIColor(red: 0.35, green: 0.22, blue: 0.17, alpha: 1), casing: UIColor(red: 0.95, green: 0.92, blue: 0.78, alpha: 1))
        case .midnight: RoadPalette(motorway: UIColor(red: 0.68, green: 0.84, blue: 0.95, alpha: 1), arterial: UIColor(red: 0.98, green: 0.7, blue: 0.31, alpha: 1), street: UIColor(red: 0.55, green: 0.72, blue: 0.72, alpha: 1), railway: UIColor(red: 0.78, green: 0.55, blue: 0.84, alpha: 1), casing: UIColor(red: 0.04, green: 0.08, blue: 0.13, alpha: 1))
        case .forest: RoadPalette(motorway: UIColor(red: 0.23, green: 0.3, blue: 0.25, alpha: 1), arterial: UIColor(red: 0.77, green: 0.55, blue: 0.21, alpha: 1), street: UIColor(red: 0.87, green: 0.82, blue: 0.58, alpha: 1), railway: UIColor(red: 0.3, green: 0.19, blue: 0.14, alpha: 1), casing: UIColor(red: 0.7, green: 0.78, blue: 0.58, alpha: 1))
        }
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
