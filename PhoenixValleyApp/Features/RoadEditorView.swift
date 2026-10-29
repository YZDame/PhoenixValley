import PhoenixValleyCore
import SwiftUI
import UniformTypeIdentifiers

struct RoadEditorView: View {
    @Bindable var document: RoadDocumentStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectSidebar(document: document)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
        } detail: {
            RoadCanvasWorkspace(document: document)
        }
        .navigationSplitViewStyle(.balanced)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The sidebar hosts the generation status view; when it is
            // collapsed the detail column must still show progress and
            // cancellation, otherwise creating a map via the toolbar "+"
            // appears to do nothing until the canvas suddenly switches.
            if columnVisibility == .detailOnly,
               case let .generating(targetName, progress, usedCache)
                   = document.terrainGenerationState {
                TerrainGenerationStatusView(
                    targetName: targetName,
                    progress: progress,
                    usedCache: usedCache,
                    onCancel: document.cancelTerrainGeneration
                )
            }
        }
        .alert(
            document.alertTitle,
            isPresented: Binding(
                get: { document.saveErrorMessage != nil },
                set: { if !$0 { document.dismissSaveError() } }
            )
        ) {
            Button("好", role: .cancel) { document.dismissSaveError() }
        } message: {
            Text(document.saveErrorMessage ?? "未知错误")
        }
    }

}

private struct ProjectSidebar: View {
    @Bindable var document: RoadDocumentStore
    @State private var renameTarget: RenameTarget?
    @State private var deleteTarget: DeleteTarget?
    @State private var proposedName = ""
    @State private var collapsedGroups: Set<UUID> = []
    @State private var showsRealMapImporter = false

    var body: some View {
        List(selection: selectedProject) {
            ForEach(document.groups) { group in
                Section {
                    if !collapsedGroups.contains(group.id) {
                        ForEach(projects(in: group.id)) { project in
                            projectRow(project)
                        }
                    }
                } header: {
                    GroupHeader(
                        group: group,
                        isExpanded: !collapsedGroups.contains(group.id),
                        onToggle: { toggleGroup(group.id) },
                        onRename: { beginRenaming(group) },
                        onDelete: { deleteTarget = .group(group) }
                    )
                }
            }

            Section("未分组") {
                ForEach(projects(in: nil)) { project in
                    projectRow(project)
                }
            }

            Section {
                Label("每次修改都会自动保存", systemImage: "checkmark.icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if case let .generating(targetName, progress, usedCache)
                = document.terrainGenerationState {
                TerrainGenerationStatusView(
                    targetName: targetName,
                    progress: progress,
                    usedCache: usedCache,
                    onCancel: document.cancelTerrainGeneration
                )
            }
        }
        .navigationTitle("凤凰山谷")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Menu("新建地图", systemImage: "doc.badge.plus") {
                        Button("空白地图 · 100 × 75 千米", systemImage: "play.fill") {
                            document.createNewMap()
                        }
                        Divider()
                        ForEach(TerrainScenario.allCases) { scenario in
                            Button(scenario.displayName, systemImage: scenario.symbol) {
                                document.createNewMap(scenario: scenario)
                            }
                        }
                    }
                    .disabled(document.terrainGenerationState.isGenerating)
                    .keyboardShortcut("n", modifiers: .command)
                    Button("导入真实地图", systemImage: "globe.asia.australia") {
                        showsRealMapImporter = true
                    }
                    .accessibilityIdentifier("import-real-map")
                    Divider()
                    Button("新建分组", systemImage: "folder.badge.plus") {
                        let id = document.createGroup()
                        if let group = document.groups.first(where: { $0.id == id }) {
                            beginRenaming(group)
                        }
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsRealMapImporter) {
            RealMapImportView(document: document)
        }
        .alert(renameTarget?.title ?? "重命名", isPresented: renamePresentation) {
            TextField("名称", text: $proposedName)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                commitRename()
            }
        }
        .confirmationDialog(
            deleteTarget?.title ?? "确认删除",
            isPresented: groupDeletePresentation,
            titleVisibility: .visible
        ) {
            Button(deleteTarget?.actionTitle ?? "删除", role: .destructive) {
                commitDelete()
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget?.message ?? "这个操作无法撤销。")
        }
    }

    @ViewBuilder
    private func projectRow(_ project: RoadProject) -> some View {
        HStack(spacing: 8) {
            ProjectRow(project: project)
            Spacer(minLength: 4)
            Menu {
                projectActions(project)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(project.name)的更多操作")
        }
        .tag(project.id)
        .contextMenu { projectActions(project) }
        .confirmationDialog(
            deleteTarget?.title ?? "确认删除",
            isPresented: deletePresentation(for: project),
            titleVisibility: .visible
        ) {
            Button(deleteTarget?.actionTitle ?? "删除地图", role: .destructive) {
                commitDelete()
            }
            Button("取消", role: .cancel) { deleteTarget = nil }
        } message: {
            Text(deleteTarget?.message ?? "这个操作无法撤销。")
        }
    }

    @ViewBuilder
    private func projectActions(_ project: RoadProject) -> some View {
        Button("重命名", systemImage: "pencil") {
            beginRenaming(project)
        }
        Button("制作副本", systemImage: "plus.square.on.square") {
            select(project)
            document.duplicateCurrentProject()
        }
        Menu("移动到分组", systemImage: "folder") {
            Button("未分组") {
                document.moveProject(id: project.id, to: nil)
            }
            ForEach(document.groups) { group in
                Button(group.name) {
                    document.moveProject(id: project.id, to: group.id)
                }
            }
        }
        Divider()
        Button("删除", systemImage: "trash", role: .destructive) {
            deleteTarget = .project(project)
        }
    }

    private var selectedProject: Binding<UUID?> {
        Binding(
            get: { document.project.id },
            set: { id in
                if let id { document.selectProject(id: id) }
            }
        )
    }

    private var renamePresentation: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var deletePresentation: Binding<Bool> {
        Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private var groupDeletePresentation: Binding<Bool> {
        Binding(
            get: {
                if case .group = deleteTarget { return true }
                return false
            },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func deletePresentation(for project: RoadProject) -> Binding<Bool> {
        Binding(
            get: {
                guard case let .project(target) = deleteTarget else { return false }
                return target.id == project.id
            },
            set: { if !$0 { deleteTarget = nil } }
        )
    }

    private func projects(in groupID: UUID?) -> [RoadProject] {
        document.projects.filter { $0.groupID == groupID }
    }

    private func toggleGroup(_ id: UUID) {
        if collapsedGroups.contains(id) {
            collapsedGroups.remove(id)
        } else {
            collapsedGroups.insert(id)
        }
    }

    private func select(_ project: RoadProject) {
        if project.id != document.project.id {
            document.selectProject(id: project.id)
        }
    }

    private func beginRenaming(_ project: RoadProject) {
        proposedName = project.name
        renameTarget = .project(project.id)
    }

    private func beginRenaming(_ group: ProjectGroup) {
        proposedName = group.name
        renameTarget = .group(group.id)
    }

    private func commitRename() {
        switch renameTarget {
        case let .project(id): document.renameProject(id: id, to: proposedName)
        case let .group(id): document.renameGroup(id: id, to: proposedName)
        case nil: break
        }
        renameTarget = nil
    }

    private func commitDelete() {
        switch deleteTarget {
        case let .project(project):
            select(project)
            document.deleteCurrentProject()
        case let .group(group):
            document.deleteGroup(id: group.id)
        case nil: break
        }
        deleteTarget = nil
    }
}

private struct TerrainGenerationStatusView: View {
    let targetName: String
    let progress: TerrainGenerationProgress
    let usedCache: Bool
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(usedCache ? "正在载入缓存地形" : progress.phase.statusText)
                        .font(.caption.weight(.semibold))
                    Text(targetName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(progress.fractionCompleted, format: .percent.precision(.fractionLength(0)))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)

                Button("取消", action: onCancel)
                    .font(.caption)
                    .accessibilityIdentifier("cancel-terrain-generation")
            }

            ProgressView(value: progress.fractionCompleted)
                .progressViewStyle(.linear)
                .accessibilityLabel("地形生成进度")
                .accessibilityValue(
                    Text(
                        progress.fractionCompleted,
                        format: .percent.precision(.fractionLength(0))
                    )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("terrain-generation-progress")
    }
}

private extension TerrainGenerationPhase {
    var statusText: String {
        switch self {
        case .shoreline: "正在生成海岸线"
        case .landforms: "正在布置山脉与谷地"
        case .elevationGrid: "正在计算高程"
        case .hydrology: "正在分析河流和流域"
        case .finished: "地形生成完成"
        }
    }
}

private enum RenameTarget {
    case project(UUID)
    case group(UUID)

    var title: String {
        switch self {
        case .project: "重命名地图"
        case .group: "重命名分组"
        }
    }
}

private enum DeleteTarget {
    case project(RoadProject)
    case group(ProjectGroup)

    var title: String {
        switch self {
        case let .project(project): "删除“\(project.name)”？"
        case let .group(group): "删除分组“\(group.name)”？"
        }
    }

    var actionTitle: String {
        switch self {
        case .project: "删除地图"
        case .group: "删除分组"
        }
    }

    var message: String {
        switch self {
        case .project: "这个操作无法撤销。"
        case .group: "分组中的地图会移到“未分组”，地图本身不会删除。"
        }
    }
}

private struct GroupHeader: View {
    let group: ProjectGroup
    let isExpanded: Bool
    let onToggle: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.bold))
                    Label(group.name, systemImage: "folder")
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button("重命名分组", systemImage: "pencil", action: onRename)
                Button("删除分组", systemImage: "trash", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.plain)
        }
    }
}

private struct ProjectRow: View {
    let project: RoadProject

    var body: some View {
        HStack(spacing: 11) {
            MapContentThumbnail(
                project: project,
                size: CGSize(width: 42, height: 34)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text("\(project.roads.count) 段 · \(project.updatedAt.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct RoadCanvasWorkspace: View {
    @Bindable var document: RoadDocumentStore
    @State private var isPaletteExpanded = true
    @AppStorage("fingerDrawingEnabled") private var fingerDrawingEnabled = true
    @State private var showsMapAppearance = false
    @AppStorage("showsConstructionIssueOverlayV2")
    private var showsConstructionIssueOverlay = false
    @AppStorage("enablesAdvancedEngineeringAnalysis")
    private var enablesAdvancedEngineeringAnalysis = false
    @State private var exportSession: MapExportSession?
    @State private var viewportReference = MapViewportReference()

    var body: some View {
        RoadCanvasRepresentable(
            project: document.project,
            onViewportChanged: { viewportReference.value = $0 },
            allowsFingerDrawing: fingerDrawingEnabled,
            pendingRampPlan: document.pendingRampPlan,
            pendingStructureReview: enablesAdvancedEngineeringAnalysis
                ? document.pendingStructureReview
                : nil,
            selectedKind: document.selectedKind,
            selectedLevel: document.selectedLevel,
            isErasing: document.isErasing,
            eraserMode: document.eraserMode,
            isSelecting: document.isSelecting,
            isEditingInterchange: document.isEditingInterchange,
            isAwaitingRampDrawing: document.isAwaitingRampDrawing,
            showsConstructionIssueOverlay: showsConstructionIssueOverlay,
            selectedInterchangeCrossingID: document.selectedInterchangeCrossingID,
            selectedRampID: document.selectedRampID,
            selectedSourceRoadIDs: document.selectedSourceRoadIDs,
            selectedStationID: document.selectedStationID,
            onStrokeFinished: { points in
                if document.isEditingInterchange,
                   document.isAwaitingRampDrawing {
                    document.prepareRampDraft(points)
                } else {
                    document.addStroke(
                        points,
                        requestsStructureReview: enablesAdvancedEngineeringAnalysis
                    )
                }
            },
            onEraseFinished: { request in document.eraseRoads(request) },
            onSelectionChanged: { sourceRoadIDs in
                document.setSelectedSourceRoadIDs(sourceRoadIDs)
            },
            onSelectionMoved: { sourceRoadIDs, offset in
                document.moveRoadSources(sourceRoadIDs, by: offset)
            },
            onControlPointMoved: {
                sourceRoadID,
                originalPoint,
                destination,
                maximumDistanceMeters in
                document.moveRoadControlPoint(
                    sourceRoadID: sourceRoadID,
                    probeCanvasPoint: originalPoint,
                    destinationCanvasPoint: destination,
                    maximumDistanceMeters: maximumDistanceMeters
                )
            },
            onInterchangeCrossingSelected: { id in
                document.selectInterchangeCrossing(id: id)
            },
            onRampSelected: { id in
                document.selectRamp(id: id)
            },
            onStationSelected: { id in
                document.selectStation(id: id)
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottomTrailing) {
            realWorldAttribution
                .padding(.trailing, 16)
                .padding(.bottom, 94)
        }
        .overlay(alignment: .topTrailing) {
            if document.isEditingInterchange {
                RoadInterchangeInspector(document: document)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            } else if let stationID = document.selectedStationID,
                      let station = document.project.railwayStations.first(where: { $0.id == stationID }) {
                RailwayStationInspector(station: station, document: document)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            } else if document.isSelecting,
               !document.selectedSourceRoadIDs.isEmpty {
                RoadSelectionInspector(document: document)
                    .padding(.top, 12)
                    .padding(.trailing, 16)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            FloatingToolPalette(
                document: document,
                isExpanded: $isPaletteExpanded
            )
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("新建设计", systemImage: "plus") { document.createNewMap() }
                    .accessibilityIdentifier("new-design-map")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("导出地图", systemImage: "square.and.arrow.up") {
                    exportSession = MapExportSession(viewport: viewportReference.value)
                }
                .accessibilityIdentifier("export-map-menu")
            }

            ToolbarItem(placement: .topBarTrailing) {
                MapAppearanceButton(
                    isPresented: $showsMapAppearance,
                    conflictCount: document.layerConflicts.count,
                    engineeringIssueCount: enablesAdvancedEngineeringAnalysis
                        ? document.engineeringIssues.count
                        : 0,
                    constructionIssueCount: enablesAdvancedEngineeringAnalysis
                        ? document.constructionIssues.count
                        : 0
                )
                    .popover(
                        isPresented: $showsMapAppearance,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        MapAppearancePopover(
                            document: document,
                            enablesAdvancedEngineeringAnalysis:
                                $enablesAdvancedEngineeringAnalysis,
                            showsConstructionIssueOverlay:
                                $showsConstructionIssueOverlay
                        )
                            .presentationCompactAdaptation(.popover)
                    }
            }
        }
        .sheet(item: structureReviewPresentation) { review in
            RoadStructureReviewSheet(document: document, review: review)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .interactiveDismissDisabled()
        }
        .sheet(item: $exportSession) { session in
            MapExportSheet(document: document, viewport: session.viewport)
        }
    }

    @ViewBuilder
    private var realWorldAttribution: some View {
        if let map = document.project.realWorldMap {
            Group {
                if map.source == .osmXML {
                    Link("© OpenStreetMap contributors · ODbL",
                         destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                        .frame(minHeight: 44)
                } else {
                    Text(map.source == .kml ? "来源：导入的 KML" : "来源：导入的高程网格")
                }
            }
            .font(.caption2)
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: Capsule())
            .accessibilityIdentifier("real-map-attribution")
        }
    }

    private var structureReviewPresentation: Binding<RoadStructureReviewRecord?> {
        Binding(
            get: {
                enablesAdvancedEngineeringAnalysis
                    ? document.pendingStructureReview
                    : nil
            },
            set: { _ in }
        )
    }

}

#Preview("Road editor") {
    RoadEditorView(document: RoadDocumentStore())
}
