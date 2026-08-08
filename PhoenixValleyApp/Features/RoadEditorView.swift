import PhoenixValleyCore
import SwiftUI
import UniformTypeIdentifiers

struct RoadEditorView: View {
    @Bindable var document: RoadDocumentStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ProjectSidebar(document: document)
                .navigationSplitViewColumnWidth(min: 250, ideal: 290, max: 340)
        } detail: {
            RoadCanvasWorkspace(document: document)
        }
        .navigationSplitViewStyle(.balanced)
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
                        Button("随机场景", systemImage: "dice") {
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
    @State private var showsMapAppearance = false
    @AppStorage("showsConstructionIssueOverlayV2")
    private var showsConstructionIssueOverlay = false
    @AppStorage("enablesAdvancedEngineeringAnalysis")
    private var enablesAdvancedEngineeringAnalysis = false
    @State private var preparedExport: PreparedMapExport?
    @State private var isPresentingExporter = false
    @State private var isPreparingExport = false
    @State private var exportErrorMessage: String?

    var body: some View {
        RoadCanvasRepresentable(
            project: document.project,
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
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            if document.isEditingInterchange {
                RoadInterchangeInspector(document: document)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ForEach(MapExportFormat.allCases) { format in
                        Button(format.displayName, systemImage: format.symbol) {
                            prepareExport(format)
                        }
                        .accessibilityIdentifier("export-map-\(format.rawValue)")
                    }
                } label: {
                    if isPreparingExport {
                        ProgressView()
                    } else {
                        Label("导出地图", systemImage: "square.and.arrow.up")
                    }
                }
                .disabled(isPreparingExport)
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
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: preparedExport?.document,
            contentType: preparedExport?.format.contentType ?? .data,
            defaultFilename: preparedExport?.filename ?? "PhoenixValley",
            onCompletion: finishExport
        )
        .alert(
            "导出失败",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { exportErrorMessage = nil }
        } message: {
            Text(exportErrorMessage ?? "未知错误")
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

    private func prepareExport(_ format: MapExportFormat) {
        let project = document.project
        isPreparingExport = true

        Task { @MainActor in
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    try MapExporter.data(for: project, format: format)
                }.value
                preparedExport = PreparedMapExport(
                    format: format,
                    document: MapExportDocument(data: data),
                    filename: "\(project.name.sanitizedExportFilename).\(format.filenameExtension)"
                )
                isPreparingExport = false
                // Let SwiftUI rebuild the exporter with the prepared content type
                // before asking it to present the system document picker.
                try? await Task.sleep(for: .milliseconds(100))
                guard preparedExport?.format == format else { return }
                isPresentingExporter = true
            } catch {
                isPreparingExport = false
                exportErrorMessage = error.localizedDescription
            }
        }
    }

    private func finishExport(_ result: Result<URL, Error>) {
        if case let .failure(error) = result {
            let cocoaError = error as NSError
            if cocoaError.domain != NSCocoaErrorDomain ||
                cocoaError.code != NSUserCancelledError {
                exportErrorMessage = error.localizedDescription
            }
        }
        isPresentingExporter = false
        preparedExport = nil
    }
}

private struct PreparedMapExport: Identifiable {
    let id = UUID()
    let format: MapExportFormat
    let document: MapExportDocument
    let filename: String
}

private struct MapExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.png, .pdf, .svg, MapExportFormat.geoJSON.contentType]
    }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private extension MapExportFormat {
    var displayName: String {
        switch self {
        case .png: "PNG 图像"
        case .pdf: "PDF 文档"
        case .svg: "SVG 矢量图"
        case .geoJSON: "GeoJSON 数据"
        }
    }

    var symbol: String {
        switch self {
        case .png: "photo"
        case .pdf: "doc.richtext"
        case .svg: "scribble.variable"
        case .geoJSON: "curlybraces.square"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .pdf: .pdf
        case .svg: .svg
        case .geoJSON: UTType(filenameExtension: "geojson") ?? .json
        }
    }
}

private extension String {
    var sanitizedExportFilename: String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let components = components(separatedBy: forbidden)
            .filter { !$0.isEmpty }
        let value = components.joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "PhoenixValley" : value
    }
}

private struct RoadStructureReviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var document: RoadDocumentStore
    let review: RoadStructureReviewRecord
    @State private var selections: [String: RoadStructureType]

    init(document: RoadDocumentStore, review: RoadStructureReviewRecord) {
        self.document = document
        self.review = review
        _selections = State(
            initialValue: Dictionary(
                uniqueKeysWithValues: review.plan.candidates.map {
                    ($0.id, $0.structure)
                }
            )
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("道路", value: review.plan.roadKind.displayName)
                    LabeledContent(
                        "分析长度",
                        value: distanceDescription(review.plan.totalLength)
                    )
                    LabeledContent(
                        "采样点",
                        value: "\(review.plan.samples.count)"
                    )
                } header: {
                    Text("自动结构分析")
                } footer: {
                    Text("虚线高亮显示建议区段；桥梁、隧道与高架会作为独立结构保存。")
                }

                ForEach(review.plan.candidates) { candidate in
                    Section {
                        Picker(
                            "处理方式",
                            selection: selectionBinding(for: candidate)
                        ) {
                            ForEach(allowedStructures(for: candidate), id: \.self) { structure in
                                Text(structure.displayName).tag(structure)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("structure-choice-\(candidate.id)")

                        LabeledContent(
                            "沿线范围",
                            value: chainageDescription(candidate.evidence.sampleRange)
                        )
                        LabeledContent(
                            "触发条件",
                            value: candidate.evidence.triggers
                                .map(\.displayName)
                                .sorted()
                                .joined(separator: "、")
                        )
                        LabeledContent(
                            "原地表最大纵坡",
                            value: candidate.evidence.metrics.maximumAbsoluteGrade
                                .formatted(.percent.precision(.fractionLength(1)))
                        )
                        if let structure = engineeringStructure(for: candidate) {
                            engineeringDetails(structure)
                        }
                        if !candidate.evidence.relatedRoadIDs.isEmpty {
                            LabeledContent(
                                "关联道路",
                                value: "\(candidate.evidence.relatedRoadIDs.count) 条"
                            )
                        }
                    } header: {
                        Label(candidate.structure.displayName, systemImage: candidate.structure.symbol)
                    } footer: {
                        Text(transitionDescription(for: candidate))
                    }
                }

                if !review.plan.crossingSuggestions.isEmpty {
                    Section("道路交叉") {
                        ForEach(review.plan.crossingSuggestions) { suggestion in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(suggestion.treatment.displayName)
                                    .font(.subheadline.weight(.medium))
                                Text(
                                    "交角 \((suggestion.crossingAngle * 180 / .pi).formatted(.number.precision(.fractionLength(0))))° · "
                                        + "既有层级 \(suggestion.existingLevel.displayName)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("确认道路结构")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                reviewActions
                    .padding()
                    .background(.bar)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消绘制", role: .destructive) {
                        document.discardPendingRoad(id: review.id)
                        dismiss()
                    }
                }
            }
        }
    }

    private var reviewActions: some View {
        let construction = constructionEvaluation
        return VStack(alignment: .leading, spacing: 10) {
            if engineeringEvaluation.hasErrors {
                Label(
                    "当前方案有 \(engineeringEvaluation.issues.count) 项工程约束未满足",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier("structure-engineering-error-summary")
            }
            if !construction.isFeasible {
                Label(
                    "仍有 \(construction.issues.count) 个地面道路或高架区间不可施工",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption.weight(.semibold))
                .foregroundStyle(.red)
                .accessibilityIdentifier(
                    "structure-construction-error-summary"
                )
            }

            HStack {
                Button("保留原道路") {
                    document.rejectStructureReview(id: review.id)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reject-structure-plan")

                Spacer()

                Button("应用方案") {
                    if document.applyStructureReview(
                        id: review.id,
                        decisions: decisions
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    engineeringEvaluation.hasErrors
                        || !construction.isFeasible
                )
                .accessibilityIdentifier("apply-structure-plan")
            }
        }
    }

    private var decisions: [AutoStructureDecision] {
        review.plan.candidates.map { candidate in
            let selection = selections[candidate.id] ?? candidate.structure
            let resolution: AutoStructureDecisionResolution
            if selection == candidate.structure {
                resolution = .accept
            } else if selection == .ground {
                resolution = .reject
            } else {
                resolution = .replace(with: selection)
            }
            return AutoStructureDecision(
                candidateID: candidate.id,
                resolution: resolution
            )
        }
    }

    private var engineeringEvaluation: RoadEngineeringEvaluation {
        RoadEngineeringPlanner.evaluate(
            plan: review.plan,
            decisions: decisions,
            terrain: document.project.terrain,
            mapScale: document.project.mapScale
        )
    }

    private var constructionEvaluation: RoadConstructionFeasibilityReport {
        let roads = review.plan.resolving(decisions).enumerated().compactMap {
            index, span -> RoadSegment? in
            guard span.points.count >= 2 else { return nil }
            return RoadSegment(
                id: index == 0 ? review.plan.sourceEdgeID : UUID(),
                kind: span.roadKind,
                structure: span.structure,
                points: span.points,
                sourceRoadID: review.plan.sourceRoadID
            )
        }
        return RoadConstructionFeasibilityAnalyzer.evaluate(
            roads: roads,
            terrain: document.project.terrain,
            mapScale: document.project.mapScale
        )
    }

    private func engineeringStructure(
        for candidate: AutoStructureCandidate
    ) -> RoadEngineeringStructure? {
        engineeringEvaluation.structure(forCandidateID: candidate.id)
    }

    @ViewBuilder
    private func engineeringDetails(_ structure: RoadEngineeringStructure) -> some View {
        let report = structure.report
        LabeledContent(
            "结构长度",
            value: lengthRuleDescription(report)
        )
        LabeledContent(
            structure.structure == .bridge ? "桥面纵坡" : "隧道轴线纵坡",
            value: gradeRuleDescription(
                measured: report.structureGrade,
                limit: report.maximumStructureGrade
            )
        )
        LabeledContent(
            "入口引道纵坡",
            value: gradeRuleDescription(
                measured: abs(structure.endpoints.first?.approachGrade ?? 0),
                limit: report.maximumApproachGrade
            )
        )
        LabeledContent(
            "出口引道纵坡",
            value: gradeRuleDescription(
                measured: abs(structure.endpoints.last?.approachGrade ?? 0),
                limit: report.maximumApproachGrade
            )
        )
        if structure.structure == .bridge {
            LabeledContent(
                "桥墩布置",
                value: "\(structure.bridgePiers.count) 座 · 最大跨径 \(Int((report.maximumBridgeSpanMeters ?? 0).rounded())) m"
            )
        }
        if let cover = report.minimumTunnelCoverMeters {
            LabeledContent(
                "最小覆土",
                value: "\(cover.formatted(.number.precision(.fractionLength(1)))) m"
            )
        }
        ForEach(report.issues) { issue in
            Label(
                issue.displayDescription,
                systemImage: "exclamationmark.octagon.fill"
            )
            .font(.caption)
            .foregroundStyle(.red)
            .accessibilityIdentifier("structure-constraint-\(issue.id)")
        }
    }

    private func lengthRuleDescription(_ report: RoadEngineeringReport) -> String {
        let measured = Int(report.structureLengthMeters.rounded())
        let minimum = Int(report.minimumLengthMeters.rounded())
        if let maximum = report.maximumLengthMeters {
            return "\(measured) m（允许 \(minimum)–\(Int(maximum.rounded())) m）"
        }
        return "\(measured) m（至少 \(minimum) m）"
    }

    private func gradeRuleDescription(measured: Double, limit: Double) -> String {
        let measuredText = measured.formatted(
            .percent.precision(.fractionLength(1))
        )
        let limitText = limit.formatted(
            .percent.precision(.fractionLength(1))
        )
        return "\(measuredText)（上限 \(limitText)）"
    }

    private func selectionBinding(
        for candidate: AutoStructureCandidate
    ) -> Binding<RoadStructureType> {
        Binding(
            get: { selections[candidate.id] ?? candidate.structure },
            set: { selections[candidate.id] = $0 }
        )
    }

    private func allowedStructures(
        for candidate: AutoStructureCandidate
    ) -> [RoadStructureType] {
        if candidate.evidence.triggers.contains(.water) {
            return [.bridge, .tunnel]
        }
        return RoadStructureType.allCases
    }

    private func chainageDescription(_ range: StructureSampleRange) -> String {
        let start = document.project.mapScale.meters(
            forCanvasDistance: range.startDistance
        )
        let end = document.project.mapScale.meters(
            forCanvasDistance: range.endDistance
        )
        return "\(Int(start.rounded()))–\(Int(end.rounded())) m"
    }

    private func distanceDescription(_ canvasDistance: Double) -> String {
        let meters = document.project.mapScale.meters(
            forCanvasDistance: canvasDistance
        )
        return "\(Int(meters.rounded())) m"
    }

    private func transitionDescription(
        for candidate: AutoStructureCandidate
    ) -> String {
        let entranceGrade = candidate.entrance.approachGrade
            .formatted(.percent.precision(.fractionLength(1)))
        let exitGrade = candidate.exit.approachGrade
            .formatted(.percent.precision(.fractionLength(1)))
        return "入口纵坡 \(entranceGrade)，出口纵坡 \(exitGrade)。"
    }
}

private struct MapAppearanceButton: View {
    @Binding var isPresented: Bool
    let conflictCount: Int
    let engineeringIssueCount: Int
    let constructionIssueCount: Int

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "map.fill")
                .overlay(alignment: .topTrailing) {
                    if conflictCount > 0
                        || engineeringIssueCount > 0
                        || constructionIssueCount > 0 {
                        Circle()
                            .fill(.red)
                            .frame(width: 7, height: 7)
                            .offset(x: 4, y: -3)
                    }
                }
        }
        .accessibilityLabel("地图外观")
        .accessibilityValue(
            accessibilitySummary
        )
        .accessibilityIdentifier("map-appearance-button")
    }

    private var accessibilitySummary: String {
        let conflicts = conflictCount == 0
            ? "没有层级冲突"
            : "\(conflictCount) 处层级冲突"
        let engineering = engineeringIssueCount == 0
            ? "没有工程约束问题"
            : "\(engineeringIssueCount) 项工程约束问题"
        let construction = constructionIssueCount == 0
            ? "没有施工可行性问题"
            : "\(constructionIssueCount) 项施工可行性问题"
        return "\(conflicts)，\(engineering)，\(construction)"
    }
}

private struct MapAppearancePopover: View {
    @Bindable var document: RoadDocumentStore
    @Binding var enablesAdvancedEngineeringAnalysis: Bool
    @Binding var showsConstructionIssueOverlay: Bool

    var body: some View {
        let constructionIssues = document.constructionIssues
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("地图外观")
                    .font(.headline)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: 3),
                    spacing: 12
                ) {
                    ForEach(MapTheme.allCases) { theme in
                        ThemeOptionButton(
                            theme: theme,
                            isSelected: document.project.theme == theme
                        ) {
                            document.setTheme(theme)
                        }
                    }
                }

                Divider()

                VStack(spacing: 14) {
                    Toggle("地形", systemImage: "mountain.2", isOn: terrainSelection)
                    Toggle("等高线", systemImage: "lines.measurement.horizontal", isOn: contoursSelection)
                    Toggle("规划网格", systemImage: "grid", isOn: gridSelection)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "进阶工程分析",
                        systemImage: "ruler",
                        isOn: $enablesAdvancedEngineeringAnalysis
                    )
                    .accessibilityIdentifier("advanced-engineering-analysis-toggle")

                    Text("开启后，新绘道路会分析桥梁、隧道、坡度和施工区段；自由绘制默认不受这些建议打断。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("地图范围") {
                        Picker("地图范围", selection: mapScaleSelection) {
                            ForEach(MapScalePreset.allCases) { preset in
                                Text(preset.displayName).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .disabled(!document.project.roads.isEmpty)
                        .accessibilityIdentifier("map-scale-picker")
                    }

                    Text(
                        document.project.roads.isEmpty
                            ? "绘路前选择；规划网格每格 \(gridCellDistanceDescription)。"
                            : "已有道路后锁定比例；规划网格每格 \(gridCellDistanceDescription)。"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .font(.subheadline)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("道路图层")
                        .font(.subheadline.weight(.semibold))

                    ForEach(RoadKind.allCases) { kind in
                        Toggle(
                            kind.displayName,
                            systemImage: kind.layerSymbol,
                            isOn: roadLayerSelection(for: kind)
                        )
                    }
                }
                .font(.subheadline)

                if !document.layerConflicts.isEmpty {
                    Divider()

                    Label(
                        "\(document.layerConflicts.count) 处道路层级冲突",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("road-layer-conflict-summary")
                }

                if !document.project.engineeringStructures.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("工程构件")
                            .font(.subheadline.weight(.semibold))
                        Label(
                            "\(bridgeCount) 座桥梁 · \(bridgePierCount) 座桥墩",
                            systemImage: "water.waves"
                        )
                        Label(
                            "\(tunnelCount) 条隧道 · \(tunnelPortalCount) 个洞口",
                            systemImage: "mountain.2"
                        )
                        if !document.engineeringIssues.isEmpty {
                            Label(
                                "\(document.engineeringIssues.count) 项工程约束问题",
                                systemImage: "exclamationmark.octagon.fill"
                            )
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("road-engineering-issue-summary")
                        }
                    }
                    .font(.caption)
                }

                if enablesAdvancedEngineeringAnalysis
                    && !document.project.roads.isEmpty {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("施工可行性")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Toggle(
                                "显示红色标注",
                                isOn: $showsConstructionIssueOverlay
                            )
                            .labelsHidden()
                            .accessibilityLabel("显示施工问题标注")
                            .accessibilityIdentifier(
                                "construction-issue-overlay-toggle"
                            )
                        }
                        if constructionIssues.isEmpty {
                            Label(
                                "当前地面道路与高架未发现超限区间",
                                systemImage: "checkmark.circle"
                            )
                            .foregroundStyle(.secondary)
                        } else {
                            Label(
                                "\(constructionIssues.count) 个区间需要处理",
                                systemImage: "exclamationmark.octagon.fill"
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                            .accessibilityIdentifier(
                                "road-construction-issue-summary"
                            )

                            ForEach(constructionIssues.prefix(2)) { issue in
                                Text(issue.displayDescription)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if constructionIssues.count > 2 {
                                Text("另有 \(constructionIssues.count - 2) 个区间")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Text("红色虚线只标出当前结构下的超限区间；隐藏标注不会改变施工判定。")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                Divider()

                Menu {
                    Button("随机场景", systemImage: "dice") {
                        document.createNewMap()
                    }
                    Divider()
                    ForEach(TerrainScenario.allCases) { scenario in
                        Button(scenario.displayName, systemImage: scenario.symbol) {
                            document.createNewMap(scenario: scenario)
                        }
                    }
                } label: {
                    Label("创建场景地图", systemImage: "map")
                        .frame(maxWidth: .infinity)
                }
                .disabled(document.terrainGenerationState.isGenerating)
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("create-random-map-button")
            }
            .padding(20)
        }
        .scrollIndicators(.visible)
        .frame(width: 390)
        .frame(maxHeight: 620)
    }

    private var terrainSelection: Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.showsTerrain },
            set: { document.setShowsTerrain($0) }
        )
    }

    private var contoursSelection: Binding<Bool> {
        Binding(
            get: { document.project.showsContours },
            set: { document.setShowsContours($0) }
        )
    }

    private var gridSelection: Binding<Bool> {
        Binding(
            get: { document.project.showsGrid },
            set: { document.setShowsGrid($0) }
        )
    }

    private func roadLayerSelection(for kind: RoadKind) -> Binding<Bool> {
        Binding(
            get: { document.project.layerVisibility.isVisible(kind) },
            set: { document.setRoadKind(kind, isVisible: $0) }
        )
    }

    private var mapScaleSelection: Binding<MapScalePreset> {
        Binding(
            get: {
                MapScalePreset.allCases.min {
                    abs($0.rawValue - document.project.mapScale.metersPerPoint)
                        < abs($1.rawValue - document.project.mapScale.metersPerPoint)
                } ?? .standard
            },
            set: {
                document.setMapScale(
                    MapScale(metersPerPoint: $0.rawValue)
                )
            }
        )
    }

    private var gridCellDistanceDescription: String {
        MapScalePreset.distanceDescription(
            document.project.mapScale.meters(forCanvasDistance: 80)
        )
    }

    private var bridgeCount: Int {
        document.project.engineeringStructures.count { $0.structure == .bridge }
    }

    private var bridgePierCount: Int {
        document.project.engineeringStructures.reduce(0) {
            $0 + $1.bridgePiers.count
        }
    }

    private var tunnelCount: Int {
        document.project.engineeringStructures.count { $0.structure == .tunnel }
    }

    private var tunnelPortalCount: Int {
        document.project.engineeringStructures.reduce(0) {
            $0 + $1.tunnelPortals.count
        }
    }
}

private enum MapScalePreset: Double, CaseIterable, Identifiable {
    case compact = 0.5
    case standard = 1
    case regional = 2
    case wide = 5

    var id: Double { rawValue }

    var displayName: String {
        let scale = MapScale(metersPerPoint: rawValue)
        return "\(Self.distanceDescription(scale.widthMeters)) × "
            + Self.distanceDescription(scale.heightMeters)
    }

    static func distanceDescription(_ meters: Double) -> String {
        if meters >= 1_000 {
            let kilometers = meters / 1_000
            return kilometers.formatted(
                .number.precision(.fractionLength(kilometers.rounded() == kilometers ? 0 : 1))
            ) + " km"
        }
        return "\(Int(meters.rounded())) m"
    }
}

private struct ThemeOptionButton: View {
    let theme: MapTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(theme.previewBackground)
                    .frame(width: 92, height: 66)
                    .overlay {
                        Image(systemName: theme.previewSymbol)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(.primary.opacity(0.72))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .stroke(
                                isSelected
                                    ? Color.accentColor
                                    : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 3 : 1
                            )
                    }

                Text(theme.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("map-theme-\(theme.rawValue)")
    }
}

private struct MapContentThumbnail: View {
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

private struct FloatingToolPalette: View {
    @Bindable var document: RoadDocumentStore
    @Binding var isExpanded: Bool

    var body: some View {
        horizontalPalette
            .padding(8)
            .modifier(PaletteGlassSurface())
        .animation(.snappy(duration: 0.22), value: isExpanded)
        .accessibilityElement(children: .contain)
    }

    private var horizontalPalette: some View {
        HStack(spacing: 8) {
            paletteContent
            Divider().frame(height: 34)
            historyAndCollapseControls
        }
    }

    @ViewBuilder
    private var paletteContent: some View {
        if isExpanded {
            ToolControls(document: document)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            CompactToolSummary(document: document)
                .transition(.opacity)
        }
    }

    private var historyAndCollapseControls: some View {
        HStack(spacing: 6) {
            Button("撤销", systemImage: "arrow.uturn.backward") {
                document.undo()
            }
            .labelStyle(.iconOnly)
            .frame(width: 32, height: 38)
            .disabled(!document.canUndo)
            .accessibilityIdentifier("undo-button")

            Button("重做", systemImage: "arrow.uturn.forward") {
                document.redo()
            }
            .labelStyle(.iconOnly)
            .frame(width: 32, height: 38)
            .disabled(!document.canRedo)
            .accessibilityIdentifier("redo-button")

            Divider().frame(height: 30)

            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                    .frame(width: 32, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "折叠工具栏" : "展开工具栏")
        }
    }

}

private struct PaletteGlassSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.primary.opacity(0.12))
                }
        }
    }
}

private struct CompactToolSummary: View {
    @Bindable var document: RoadDocumentStore

    var body: some View {
        HStack(spacing: 8) {
            if document.isEditingInterchange {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(.tint)
                Text("立交")
            } else if document.isSelecting {
                Image(systemName: "selection.pin.in.out")
                    .foregroundStyle(.tint)
                Text("选择")
            } else if document.isErasing {
                Image(systemName: "eraser.line.dashed")
                    .foregroundStyle(.red)
                Text("擦除·\(document.eraserMode.displayName)")
            } else {
                RoadSwatch(kind: document.selectedKind)
                Text(document.selectedKind.displayName)
            }
        }
        .font(.caption.weight(.medium))
        .frame(width: 88)
    }
}

private struct ToolControls: View {
    @Bindable var document: RoadDocumentStore

    var body: some View { horizontalControls }

    private var horizontalControls: some View {
        HStack(spacing: 7) {
            ForEach(RoadKind.allCases) { kind in
                roadButton(kind)
            }
            selectButton
            interchangeButton
            eraseButton

            Divider().frame(height: 36).padding(.horizontal, 4)
            if document.isSelecting {
                selectionSummary.frame(width: 220)
            } else if document.isEditingInterchange {
                interchangeSummary.frame(width: 220)

                Divider().frame(height: 36).padding(.horizontal, 4)
                correctionSlider.frame(width: 104)
            } else if document.isErasing {
                eraserModePicker.frame(width: 180)
            } else {
                levelPicker.frame(width: 220)

                Divider().frame(height: 36).padding(.horizontal, 4)
                correctionSlider.frame(width: 104)
            }
        }
    }


    private func roadButton(_ kind: RoadKind) -> some View {
        RoadToolButton(
            kind: kind,
            isSelected: (document.activeTool == .draw
                || document.isEditingInterchange)
                && document.selectedKind == kind
        ) {
            guard !(document.isEditingInterchange && kind == .railway) else {
                return
            }
            if document.isEditingInterchange {
                if document.selectedRampID != nil {
                    document.changeSelectedRampKind(to: kind)
                } else if let plan = document.pendingRampPlan {
                    document.updatePendingRamp(
                        direction: plan.ramp.direction,
                        kind: kind
                    )
                } else {
                    document.selectedKind = kind
                }
            } else {
                document.activateDrawing(kind: kind)
            }
        }
        .disabled(document.isEditingInterchange && kind == .railway)
    }

    private var selectButton: some View {
        Button {
            document.activateSelection()
        } label: {
            ToolButtonLabel(
                title: "选择",
                symbol: "selection.pin.in.out"
            )
            .background(
                document.isSelecting
                    ? Color.accentColor.opacity(0.14)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("road-selection-tool")
    }

    private var interchangeButton: some View {
        Button {
            document.activateInterchange()
        } label: {
            ToolButtonLabel(
                title: "立交",
                symbol: "point.3.connected.trianglepath.dotted"
            )
            .background(
                document.isEditingInterchange
                    ? Color.accentColor.opacity(0.14)
                    : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("road-interchange-tool")
    }

    private var eraseButton: some View {
        Button {
            document.activateEraser()
        } label: {
            ToolButtonLabel(
                title: "擦除",
                symbol: "eraser.line.dashed"
            )
            .background(
                document.isErasing ? Color.red.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("erase-road-tool")
    }

    private var eraserModePicker: some View {
        Picker("擦除方式", selection: $document.eraserMode) {
            ForEach(RoadEraseMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("eraser-mode-picker")
    }

    private var selectionSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "cursorarrow.rays")
                .foregroundStyle(.tint)
            Text(
                document.selectedSourceRoadIDs.isEmpty
                    ? "轻点或框选道路"
                    : "已选 \(document.selectedSourceRoadIDs.count) 条道路"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            Spacer(minLength: 0)
            if !document.selectedSourceRoadIDs.isEmpty {
                Button {
                    document.clearRoadSelection()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除道路选择")
            }
        }
    }

    private var interchangeSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: interchangeSummarySymbol)
                .foregroundStyle(.tint)
            Text(interchangeSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
    }

    private var interchangeSummarySymbol: String {
        if document.pendingRampPlan != nil {
            return "checkmark.circle"
        }
        if document.isAwaitingRampDrawing {
            return "pencil.tip"
        }
        if document.selectedRampID != nil {
            return "arrow.triangle.merge"
        }
        return "diamond"
    }

    private var interchangeSummaryText: String {
        if document.pendingRampPlan != nil {
            return "检查草稿后添加"
        }
        if document.isAwaitingRampDrawing {
            return "从一条主线画向另一条"
        }
        if document.selectedRampID != nil {
            return "已选匝道"
        }
        if document.selectedInterchangeCrossingID != nil {
            return "已选异层交叉"
        }
        return "轻点菱形异层交叉"
    }

    private var levelPicker: some View {
        Picker("道路层级", selection: $document.selectedLevel) {
            Text("隧道").tag(RoadLevel.tunnel)
            Text("地面").tag(RoadLevel.ground)
            Text("高架").tag(RoadLevel.elevated)
        }
        .pickerStyle(.segmented)
        .disabled(document.isErasing || document.isSelecting)
    }

    private var correctionSlider: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("修正 \(Int(document.correctionStrength * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Slider(value: $document.correctionStrength, in: 0...1)
                .accessibilityLabel("笔迹修正强度")
        }
    }
}

private struct RoadToolButton: View {
    let kind: RoadKind
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                RoadSwatch(kind: kind)
                    .frame(height: ToolButtonLabel.iconLaneHeight)
                Text(kind.displayName)
                    .font(.caption2)
            }
            .frame(
                width: ToolButtonLabel.width,
                height: ToolButtonLabel.height
            )
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .accessibilityIdentifier("road-tool-\(kind.rawValue)")
    }
}

private struct ToolButtonLabel: View {
    static let width: CGFloat = 62
    static let height: CGFloat = 48
    static let iconLaneHeight: CGFloat = 20

    let title: String
    let symbol: String

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(height: Self.iconLaneHeight)
            Text(title)
                .font(.caption2)
        }
        .frame(width: Self.width, height: Self.height)
    }
}

private struct RoadSwatch: View {
    let kind: RoadKind

    var body: some View {
        Capsule()
            .fill(kind == .railway ? .clear : kind.color)
            .stroke(kind.color, style: StrokeStyle(lineWidth: kind == .railway ? 2 : 0, dash: kind == .railway ? [4, 3] : []))
            .frame(width: 34, height: kind.previewWidth)
    }
}

private extension RoadStructureType {
    var symbol: String {
        switch self {
        case .ground:
            "road.lanes"
        case .bridge:
            "water.waves"
        case .tunnel:
            "mountain.2"
        case .elevated:
            "arrow.up.forward"
        }
    }
}

private extension AutoStructureTrigger {
    var displayName: String {
        switch self {
        case .water:
            "水域"
        case .steepGrade:
            "纵坡过陡"
        case .mountainRelief:
            "山体起伏"
        case .tunnelLengthAdvantage:
            "隧道缩短路线"
        case .roadCrossing:
            "道路交叉"
        case .roadPriority:
            "道路等级"
        case .crossingAngle:
            "交叉角度"
        case .existingVerticalSeparation:
            "既有分层"
        }
    }
}

private extension RoadCrossingTreatment {
    var displayName: String {
        switch self {
        case .atGrade:
            "平面路口"
        case .elevated:
            "建议高架"
        case .interchange:
            "建议立交"
        case .preserveExistingSeparation:
            "保持既有分层"
        case .deferToPrimaryStructure:
            "服从连续桥隧结构"
        }
    }
}

private extension RoadLevel {
    var displayName: String {
        switch self {
        case .tunnel:
            "隧道"
        case .ground:
            "地面"
        case .elevated:
            "高架"
        }
    }
}

extension RoadKind {
    var layerSymbol: String {
        switch self {
        case .motorway: "road.lanes"
        case .arterial: "arrow.triangle.branch"
        case .street: "point.topleft.down.to.point.bottomright.curvepath"
        case .railway: "tram"
        }
    }

    var color: Color {
        switch self {
        case .motorway: Color(red: 0.18, green: 0.21, blue: 0.22)
        case .arterial: Color(red: 0.28, green: 0.32, blue: 0.33)
        case .street: Color(red: 0.48, green: 0.52, blue: 0.52)
        case .railway: Color(red: 0.36, green: 0.28, blue: 0.23)
        }
    }

    var previewWidth: CGFloat {
        switch self {
        case .motorway: 8
        case .arterial: 6
        case .street: 3
        case .railway: 5
        }
    }
}

private extension MapTheme {
    var previewSymbol: String {
        switch self {
        case .topographic: "mountain.2.fill"
        case .planning: "point.bottomleft.forward.to.point.topright.scurvepath"
        case .ink: "scribble.variable"
        case .coastal: "water.waves"
        case .midnight: "moon.stars.fill"
        case .forest: "tree.fill"
        }
    }

    var previewBackground: Color {
        switch self {
        case .topographic: Color(red: 0.72, green: 0.82, blue: 0.59)
        case .planning: Color(red: 0.91, green: 0.92, blue: 0.85)
        case .ink: Color(white: 0.94)
        case .coastal: Color(red: 0.49, green: 0.77, blue: 0.86)
        case .midnight: Color(red: 0.08, green: 0.14, blue: 0.22)
        case .forest: Color(red: 0.56, green: 0.7, blue: 0.49)
        }
    }

    var previewForeground: Color {
        switch self {
        case .topographic: Color(red: 0.24, green: 0.34, blue: 0.22)
        case .planning: Color(red: 0.28, green: 0.34, blue: 0.35)
        case .ink: Color(white: 0.22)
        case .coastal: Color(red: 0.12, green: 0.34, blue: 0.42)
        case .midnight: Color(red: 0.7, green: 0.86, blue: 0.95)
        case .forest: Color(red: 0.18, green: 0.3, blue: 0.18)
        }
    }

    var thumbnailPalette: ThumbnailPalette {
        switch self {
        case .topographic:
            ThumbnailPalette(
                water: Color(red: 0.69, green: 0.84, blue: 0.9),
                plain: Color(red: 0.82, green: 0.88, blue: 0.67),
                lowland: Color(red: 0.67, green: 0.8, blue: 0.53),
                hill: Color(red: 0.77, green: 0.69, blue: 0.47),
                mountain: Color(red: 0.61, green: 0.5, blue: 0.37),
                shoreline: Color(red: 0.23, green: 0.38, blue: 0.42),
                roadCasing: Color(red: 0.18, green: 0.25, blue: 0.22),
                motorway: .white,
                arterial: Color(red: 0.96, green: 0.83, blue: 0.28),
                street: Color(red: 0.86, green: 0.93, blue: 0.82),
                railway: Color(red: 0.28, green: 0.2, blue: 0.16)
            )
        case .planning:
            ThumbnailPalette(
                water: Color(red: 0.86, green: 0.92, blue: 0.94),
                plain: Color(red: 0.96, green: 0.95, blue: 0.89),
                lowland: Color(red: 0.9, green: 0.91, blue: 0.8),
                hill: Color(red: 0.87, green: 0.82, blue: 0.68),
                mountain: Color(red: 0.76, green: 0.7, blue: 0.62),
                shoreline: .black.opacity(0.3),
                roadCasing: .white,
                motorway: Color(red: 0.18, green: 0.2, blue: 0.21),
                arterial: Color(red: 0.32, green: 0.36, blue: 0.37),
                street: Color(red: 0.72, green: 0.75, blue: 0.73),
                railway: Color(red: 0.35, green: 0.25, blue: 0.2)
            )
        case .ink:
            ThumbnailPalette(
                water: Color(white: 0.93),
                plain: Color(white: 0.985),
                lowland: Color(white: 0.955),
                hill: Color(white: 0.92),
                mountain: Color(white: 0.86),
                shoreline: .black.opacity(0.35),
                roadCasing: .white,
                motorway: Color(white: 0.08),
                arterial: Color(white: 0.2),
                street: Color(white: 0.48),
                railway: .black
            )
        case .coastal:
            ThumbnailPalette(
                water: Color(red: 0.49, green: 0.77, blue: 0.86),
                plain: Color(red: 0.96, green: 0.91, blue: 0.76),
                lowland: Color(red: 0.84, green: 0.87, blue: 0.67),
                hill: Color(red: 0.78, green: 0.72, blue: 0.54),
                mountain: Color(red: 0.57, green: 0.48, blue: 0.4),
                shoreline: Color(red: 0.12, green: 0.34, blue: 0.42),
                roadCasing: Color(red: 0.95, green: 0.92, blue: 0.78),
                motorway: Color(red: 0.16, green: 0.3, blue: 0.36),
                arterial: Color(red: 0.93, green: 0.52, blue: 0.22),
                street: Color(red: 0.96, green: 0.88, blue: 0.62),
                railway: Color(red: 0.35, green: 0.22, blue: 0.17)
            )
        case .midnight:
            ThumbnailPalette(
                water: Color(red: 0.05, green: 0.1, blue: 0.17),
                plain: Color(red: 0.11, green: 0.16, blue: 0.2),
                lowland: Color(red: 0.14, green: 0.22, blue: 0.23),
                hill: Color(red: 0.2, green: 0.27, blue: 0.25),
                mountain: Color(red: 0.3, green: 0.32, blue: 0.28),
                shoreline: Color(red: 0.48, green: 0.7, blue: 0.78),
                roadCasing: Color(red: 0.04, green: 0.08, blue: 0.13),
                motorway: Color(red: 0.68, green: 0.84, blue: 0.95),
                arterial: Color(red: 0.98, green: 0.7, blue: 0.31),
                street: Color(red: 0.55, green: 0.72, blue: 0.72),
                railway: Color(red: 0.78, green: 0.55, blue: 0.84)
            )
        case .forest:
            ThumbnailPalette(
                water: Color(red: 0.43, green: 0.68, blue: 0.69),
                plain: Color(red: 0.78, green: 0.84, blue: 0.69),
                lowland: Color(red: 0.58, green: 0.72, blue: 0.5),
                hill: Color(red: 0.42, green: 0.58, blue: 0.38),
                mountain: Color(red: 0.3, green: 0.4, blue: 0.31),
                shoreline: Color(red: 0.12, green: 0.3, blue: 0.28),
                roadCasing: Color(red: 0.7, green: 0.78, blue: 0.58),
                motorway: Color(red: 0.23, green: 0.3, blue: 0.25),
                arterial: Color(red: 0.77, green: 0.55, blue: 0.21),
                street: Color(red: 0.87, green: 0.82, blue: 0.58),
                railway: Color(red: 0.3, green: 0.19, blue: 0.14)
            )
        }
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

private extension RoadEngineeringConstraintIssue {
    var displayDescription: String {
        switch kind {
        case .belowMinimumLength:
            "结构长度 \(formattedValue(measuredValue))，低于 \(formattedValue(limitValue))"
        case .aboveMaximumBridgeLength:
            "桥梁长度 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .structureGradeTooSteep:
            "结构纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .entranceApproachTooSteep:
            "入口引道纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .exitApproachTooSteep:
            "出口引道纵坡 \(formattedValue(measuredValue))，超过 \(formattedValue(limitValue))"
        case .bridgeheadInWater:
            location == .entrance ? "入口桥头位于水域" : "出口桥头位于水域"
        case .tunnelPortalInWater:
            location == .entrance ? "入口洞口位于水域" : "出口洞口位于水域"
        case .insufficientTunnelCover:
            "最小覆土 \(formattedValue(measuredValue))，低于 \(formattedValue(limitValue))"
        case .bridgeDeckBelowTerrain:
            "桥面与地形相交 \(formattedValue(measuredValue))"
        }
    }

    private func formattedValue(_ value: Double) -> String {
        switch unit {
        case .meters:
            "\(value.formatted(.number.precision(.fractionLength(1)))) m"
        case .grade:
            value.formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

private extension RoadConstructionIssue {
    var displayDescription: String {
        let chainage = "\(startChainageMeters.formatted(.number.precision(.fractionLength(0))))"
            + "–\(endChainageMeters.formatted(.number.precision(.fractionLength(0)))) m"
        switch kind {
        case .localGradeAboveLimit:
            return "\(roadKind.displayName) \(chainage)：局部纵坡 "
                + measuredValue.formatted(.percent.precision(.fractionLength(1)))
                + "，上限 "
                + limitValue.formatted(.percent.precision(.fractionLength(1)))
        case .groundRoadInWater:
            return "\(roadKind.displayName) \(chainage)：地面道路进入水域"
        case .elevatedAxisGradeAboveLimit:
            return "\(roadKind.displayName) \(chainage)：高架轴线纵坡 "
                + measuredValue.formatted(.percent.precision(.fractionLength(1)))
                + "，上限 "
                + limitValue.formatted(.percent.precision(.fractionLength(1)))
        }
    }
}

#Preview("Road editor") {
    RoadEditorView(document: RoadDocumentStore())
}
