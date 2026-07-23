import RoadSketchCore
import SwiftUI

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
        .preferredColorScheme(.light)
        .alert(
            "地图未能保存",
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

    var body: some View {
        List(selection: selectedProject) {
            ForEach(document.groups) { group in
                Section {
                    ForEach(projects(in: group.id)) { project in
                        projectRow(project)
                    }
                } header: {
                    GroupHeader(
                        group: group,
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
        .navigationTitle("RoadSketch")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("新建地图", systemImage: "doc.badge.plus") {
                        document.createNewMap()
                    }
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
            isPresented: deletePresentation,
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

    private func projects(in groupID: UUID?) -> [RoadProject] {
        document.projects.filter { $0.groupID == groupID }
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
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Label(group.name, systemImage: "folder")
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
            MapStyleThumbnail(theme: project.theme, size: CGSize(width: 42, height: 34))

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
    @State private var paletteDock: PaletteDock = .bottom
    @State private var isPaletteExpanded = true
    @State private var showsMapAppearance = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                RoadCanvasRepresentable(
                    project: document.project,
                    selectedKind: document.selectedKind,
                    selectedLevel: document.selectedLevel,
                    isErasing: document.isErasing,
                    onStrokeFinished: { points in document.addStroke(points) },
                    onEraseFinished: { ids in document.eraseRoads(ids: ids) }
                )
                .ignoresSafeArea()

                MapAppearanceButton(isPresented: $showsMapAppearance)
                    .popover(
                        isPresented: $showsMapAppearance,
                        attachmentAnchor: .rect(.bounds),
                        arrowEdge: .top
                    ) {
                        MapAppearancePopover(document: document)
                            .presentationCompactAdaptation(.popover)
                    }
                    .padding(12)
                    .zIndex(2)

                FloatingToolPalette(
                    document: document,
                    dock: $paletteDock,
                    isExpanded: $isPaletteExpanded,
                    canvasSize: geometry.size
                )
                .zIndex(3)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct MapAppearanceButton: View {
    @Binding var isPresented: Bool

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "map.fill")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .labelStyle(.iconOnly)
        .modifier(FloatingGlassButtonStyle())
        .accessibilityLabel("地图外观")
        .accessibilityIdentifier("map-appearance-button")
    }
}

private struct FloatingGlassButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .buttonStyle(.glass)
        } else {
            content
                .buttonStyle(.plain)
                .background(.ultraThinMaterial, in: Circle())
                .overlay { Circle().stroke(.black.opacity(0.1)) }
                .shadow(color: .black.opacity(0.1), radius: 8, y: 3)
        }
    }
}

private struct MapAppearancePopover: View {
    @Bindable var document: RoadDocumentStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("地图外观")
                .font(.headline)

            HStack(spacing: 12) {
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
                Toggle("等高线", systemImage: "lines.measurement.horizontal", isOn: contoursSelection)
                Toggle("规划网格", systemImage: "grid", isOn: gridSelection)
            }
            .font(.subheadline)

            Divider()

            Button("创建随机地图", systemImage: "dice") {
                document.createNewMap()
            }
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("create-random-map-button")
        }
        .padding(20)
        .frame(width: 354)
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
                                isSelected ? Color.accentColor : .black.opacity(0.1),
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

private struct MapStyleThumbnail: View {
    let theme: MapTheme
    let size: CGSize

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(theme.previewBackground)
            .frame(width: size.width, height: size.height)
            .overlay {
                Image(systemName: theme.previewSymbol)
                    .font(.system(size: min(size.width, size.height) * 0.38, weight: .medium))
                    .foregroundStyle(theme.previewForeground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(.black.opacity(0.09))
            }
    }
}

private enum PaletteDock: Equatable {
    case bottom
    case left
    case right

    var isVertical: Bool { self != .bottom }
}

private struct FloatingToolPalette: View {
    @Bindable var document: RoadDocumentStore
    @Binding var dock: PaletteDock
    @Binding var isExpanded: Bool
    let canvasSize: CGSize
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        Group {
            if dock.isVertical {
                verticalPalette
            } else {
                horizontalPalette
            }
        }
        .padding(dock.isVertical ? 10 : 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.black.opacity(0.1))
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
        .fixedSize()
        .position(
            x: restingPosition.x + dragTranslation.width,
            y: restingPosition.y + dragTranslation.height
        )
        .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.82), value: dock)
        .animation(.snappy(duration: 0.22), value: isExpanded)
        .sensoryFeedback(.alignment, trigger: dock)
        .accessibilityElement(children: .contain)
    }

    private var horizontalPalette: some View {
        HStack(spacing: 8) {
            dragHandle
            paletteContent(isVertical: false)
            Divider().frame(height: 34)
            historyAndCollapseControls
        }
    }

    private var verticalPalette: some View {
        VStack(spacing: 8) {
            dragHandle
                .frame(height: 20)
            paletteContent(isVertical: true)
            Divider().frame(width: 142)
            historyAndCollapseControls
        }
    }

    @ViewBuilder
    private func paletteContent(isVertical: Bool) -> some View {
        if isExpanded {
            ToolControls(document: document, isVertical: isVertical)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
        } else {
            CompactToolSummary(document: document, isVertical: isVertical)
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

    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 42)
            .contentShape(Rectangle())
            .accessibilityLabel("拖动画笔栏")
            .accessibilityAction(named: "停靠左侧") { dock = .left }
            .accessibilityAction(named: "停靠底部") { dock = .bottom }
            .accessibilityAction(named: "停靠右侧") { dock = .right }
            .gesture(
                DragGesture(minimumDistance: 2)
                    .updating($dragTranslation) { value, state, _ in
                        state = value.translation
                    }
                    .onEnded { value in
                        let predicted = CGPoint(
                            x: restingPosition.x + value.predictedEndTranslation.width,
                            y: restingPosition.y + value.predictedEndTranslation.height
                        )
                        dock = Self.nearestDock(to: predicted, in: canvasSize)
                    }
            )
    }

    private var restingPosition: CGPoint {
        let inset: CGFloat = 14
        switch dock {
        case .bottom:
            return CGPoint(x: canvasSize.width / 2, y: canvasSize.height - inset - 34)
        case .left:
            return CGPoint(x: inset + (isExpanded ? 86 : 58), y: canvasSize.height / 2)
        case .right:
            return CGPoint(x: canvasSize.width - inset - (isExpanded ? 86 : 58), y: canvasSize.height / 2)
        }
    }

    static func nearestDock(to point: CGPoint, in size: CGSize) -> PaletteDock {
        let distances: [(PaletteDock, CGFloat)] = [
            (.left, point.x),
            (.right, size.width - point.x),
            (.bottom, size.height - point.y),
        ]
        return distances.min(by: { $0.1 < $1.1 })?.0 ?? .bottom
    }
}

private struct CompactToolSummary: View {
    @Bindable var document: RoadDocumentStore
    let isVertical: Bool

    var body: some View {
        HStack(spacing: 8) {
            if document.isErasing {
                Image(systemName: "eraser.line.dashed")
                    .foregroundStyle(.red)
                Text("拆除")
            } else {
                RoadSwatch(kind: document.selectedKind)
                Text(document.selectedKind.displayName)
            }
        }
        .font(.caption.weight(.medium))
        .frame(width: isVertical ? 74 : 88, height: isVertical ? 48 : nil)
    }
}

private struct ToolControls: View {
    @Bindable var document: RoadDocumentStore
    let isVertical: Bool

    @ViewBuilder
    var body: some View {
        if isVertical {
            verticalControls
        } else {
            horizontalControls
        }
    }

    private var horizontalControls: some View {
        HStack(spacing: 7) {
            ForEach(RoadKind.allCases) { kind in
                roadButton(kind)
            }
            eraseButton

            Divider().frame(height: 36).padding(.horizontal, 4)
            levelPicker.frame(width: 220)

            Divider().frame(height: 36).padding(.horizontal, 4)
            correctionSlider.frame(width: 104)
        }
    }

    private var verticalControls: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.fixed(68)), GridItem(.fixed(68))], spacing: 6) {
                ForEach(RoadKind.allCases) { kind in
                    roadButton(kind)
                }
                eraseButton
            }
            Divider().frame(width: 142)
            levelPicker.frame(width: 146)
            correctionSlider.frame(width: 142)
        }
    }

    private func roadButton(_ kind: RoadKind) -> some View {
        RoadToolButton(kind: kind, isSelected: document.selectedKind == kind) {
            document.selectedKind = kind
            document.isErasing = false
        }
    }

    private var eraseButton: some View {
        Button {
            document.isErasing = true
        } label: {
            VStack(spacing: 5) {
                Image(systemName: "eraser.line.dashed")
                    .font(.body.weight(.semibold))
                Text("拆除").font(.caption2)
            }
            .frame(width: 62, height: 48)
            .background(
                document.isErasing ? Color.red.opacity(0.12) : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("erase-road-tool")
    }

    private var levelPicker: some View {
        Picker("道路层级", selection: $document.selectedLevel) {
            Text("隧道").tag(RoadLevel.tunnel)
            Text("地面").tag(RoadLevel.ground)
            Text("高架").tag(RoadLevel.elevated)
        }
        .pickerStyle(.segmented)
        .disabled(document.isErasing)
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
                Text(kind.displayName)
                    .font(.caption2)
            }
            .frame(width: 62, height: 48)
            .background(
                isSelected ? Color.accentColor.opacity(0.14) : .clear,
                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("road-tool-\(kind.rawValue)")
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

extension RoadKind {
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
        }
    }

    var previewBackground: Color {
        switch self {
        case .topographic: Color(red: 0.72, green: 0.82, blue: 0.59)
        case .planning: Color(red: 0.91, green: 0.92, blue: 0.85)
        case .ink: Color(white: 0.94)
        }
    }

    var previewForeground: Color {
        switch self {
        case .topographic: Color(red: 0.24, green: 0.34, blue: 0.22)
        case .planning: Color(red: 0.28, green: 0.34, blue: 0.35)
        case .ink: Color(white: 0.22)
        }
    }
}

#Preview("Road editor") {
    RoadEditorView(document: RoadDocumentStore())
}
