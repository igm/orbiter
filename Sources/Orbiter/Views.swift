import SwiftUI

// MARK: - Sunburst Slice Shape

struct SunburstSlice: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        var path = Path()

        let innerR = radius * innerRadius
        let outerR = radius * outerRadius

        path.move(to: CGPoint(
            x: center.x + innerR * CGFloat(cos(startAngle.radians)),
            y: center.y + innerR * CGFloat(sin(startAngle.radians))
        ))

        path.addArc(
            center: center,
            radius: innerR,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )

        path.addLine(to: CGPoint(
            x: center.x + outerR * CGFloat(cos(endAngle.radians)),
            y: center.y + outerR * CGFloat(sin(endAngle.radians))
        ))

        path.addArc(
            center: center,
            radius: outerR,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )

        path.closeSubpath()

        return path
    }
}

// MARK: - Sunburst Chart

struct SunburstChart: View {
    let root: FileNode
    let currentDirectory: FileNode
    @Binding var selectedNode: FileNode?
    let onDrillDown: (FileNode) -> Void

    @State private var hoveredNode: FileNode?
    @State private var animationProgress: CGFloat = 0
    @State private var expandedNodes: Set<UUID> = []

    private let centerRadius: CGFloat = 0.18
    private let outerPadding: CGFloat = 0.02
    private let baseDepth = 3

    private func ringWidth(for ringCount: Int) -> CGFloat {
        let count = max(ringCount, baseDepth)
        return (1.0 - centerRadius - outerPadding) / CGFloat(count)
    }

    private let colors: [Color] = [
        .blue, .purple, .pink, .red, .orange, .yellow,
        .green, .mint, .teal, .cyan, .indigo, .brown
    ]

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let chartRadius = min(geometry.size.width, geometry.size.height) / 2
            let allRings = buildRings()
            let rw = ringWidth(for: allRings.count)

            ZStack {
                // Center circle
                CenterCircle(
                    node: currentDirectory,
                    hoveredNode: hoveredNode,
                    selectedNode: selectedNode
                )

                // Render rings
                ForEach(Array(allRings.enumerated()), id: \.offset) { ringIndex, slices in
                    ForEach(slices) { slice in
                        SliceView(
                            slice: slice,
                            ringIndex: ringIndex,
                            isHovered: hoveredNode?.id == slice.node.id,
                            isSelected: selectedNode?.id == slice.node.id,
                            animationProgress: animationProgress,
                            ringWidth: rw,
                            centerRadius: centerRadius
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hoveredNode = hitTest(
                        location: location, center: center,
                        chartRadius: chartRadius, rings: allRings, rw: rw
                    )
                case .ended:
                    hoveredNode = nil
                }
            }
            .onTapGesture(count: 2) {
                guard let node = hoveredNode, node.isDirectory else { return }
                guard let children = node.children, !children.isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    if expandedNodes.contains(node.id) {
                        collapseNode(node)
                    } else {
                        expandedNodes.insert(node.id)
                    }
                }
            }
            .onTapGesture {
                if let node = hoveredNode {
                    selectedNode = node
                } else {
                    selectedNode = nil
                }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    animationProgress = 1
                }
            }
            .onChange(of: currentDirectory.id) { _, _ in
                expandedNodes.removeAll()
            }
        }
    }

    private func collapseNode(_ node: FileNode) {
        expandedNodes.remove(node.id)
        for child in node.children ?? [] {
            if expandedNodes.contains(child.id) {
                collapseNode(child)
            }
        }
    }

    private func hitTest(
        location: CGPoint, center: CGPoint,
        chartRadius: CGFloat, rings: [[SliceData]], rw: CGFloat
    ) -> FileNode? {
        let dx = Double(location.x - center.x)
        let dy = Double(location.y - center.y)
        let dist = sqrt(dx * dx + dy * dy) / Double(chartRadius)

        var angleDeg = atan2(dy, dx) * 180.0 / .pi
        if angleDeg < -90 { angleDeg += 360 }

        for (ringIndex, slices) in rings.enumerated() {
            let inner = Double(centerRadius + rw * CGFloat(ringIndex))
            let outer = Double(centerRadius + rw * CGFloat(ringIndex + 1))
            guard dist >= inner && dist <= outer else { continue }

            for slice in slices {
                if angleDeg >= slice.startAngle.degrees && angleDeg < slice.endAngle.degrees {
                    return slice.node
                }
            }
            return nil
        }
        return nil
    }

    private func buildRings() -> [[SliceData]] {
        var result: [[SliceData]] = []

        guard let children = currentDirectory.children, !children.isEmpty else {
            return result
        }

        // Ring 1: direct children span the full circle
        let firstRing = buildSlicesInArc(
            nodes: children,
            startAngle: .degrees(-90),
            arcSpan: 360.0,
            depth: 0,
            parentColorIndex: nil
        )
        result.append(firstRing)

        // Ring 2+: each child subdivides within its parent's arc
        var parentSlices = firstRing
        var depth = 1
        let hardCap = 10

        while !parentSlices.isEmpty && depth < hardCap {
            var ringSlices: [SliceData] = []

            for parent in parentSlices {
                // Beyond base depth, only expand if explicitly expanded
                if depth >= baseDepth && !expandedNodes.contains(parent.node.id) {
                    continue
                }
                guard let children = parent.node.children, !children.isEmpty else { continue }
                let arc = parent.endAngle.degrees - parent.startAngle.degrees
                guard arc > 0.5 else { continue }

                let childSlices = buildSlicesInArc(
                    nodes: children,
                    startAngle: parent.startAngle,
                    arcSpan: arc,
                    depth: depth,
                    parentColorIndex: parent.colorIndex
                )
                ringSlices.append(contentsOf: childSlices)
            }

            if ringSlices.isEmpty { break }
            result.append(ringSlices)
            parentSlices = ringSlices
            depth += 1
        }

        return result
    }

    private func buildSlicesInArc(
        nodes: [FileNode],
        startAngle: Angle,
        arcSpan: Double,
        depth: Int,
        parentColorIndex: Int?
    ) -> [SliceData] {
        let total = nodes.reduce(Int64(0)) { $0 + $1.size }
        guard total > 0 else { return [] }

        var currentAngle = startAngle
        var slices: [SliceData] = []

        // Offset child colors so siblings of different parents don't start on the same hue
        let colorOffset = parentColorIndex.map { ($0 + 1) % colors.count } ?? 0

        for (index, node) in nodes.enumerated() {
            let fraction = Double(node.size) / Double(total)
            let sliceAngle = Angle.degrees(arcSpan * fraction)
            let endAngle = currentAngle + sliceAngle

            let ci = (index + colorOffset) % colors.count
            let baseColor = colors[ci]
            let opacity = max(0.4, 1.0 - 0.15 * Double(depth))
            let color = baseColor.opacity(opacity)

            slices.append(SliceData(
                node: node,
                startAngle: currentAngle,
                endAngle: endAngle,
                color: color,
                depth: depth,
                colorIndex: ci
            ))

            currentAngle = endAngle
        }

        return slices
    }
}

// MARK: - Center Circle

struct CenterCircle: View {
    let node: FileNode
    let hoveredNode: FileNode?
    let selectedNode: FileNode?

    private let centerRadius: CGFloat = 0.18

    var body: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height) * centerRadius

            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(radius: 4)
                    .frame(width: diameter, height: diameter)

                VStack(spacing: 6) {
                    if let displayNode = hoveredNode ?? selectedNode {
                        Image(systemName: displayNode.icon)
                            .font(.title2)
                            .foregroundStyle(.blue)
                        Text(displayNode.name)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(displayNode.formattedSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if displayNode.percentage > 0 {
                            Text(String(format: "%.1f%%", displayNode.percentage))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    } else {
                        Image(systemName: node.icon)
                            .font(.title)
                            .foregroundStyle(.blue)
                        Text(node.name)
                            .font(.headline)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)

                        Text(node.formattedSize)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: diameter * 0.85)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
}

// MARK: - Slice View

struct SliceView: View {
    let slice: SliceData
    let ringIndex: Int
    let isHovered: Bool
    let isSelected: Bool
    let animationProgress: CGFloat
    let ringWidth: CGFloat
    let centerRadius: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let innerR = centerRadius + ringWidth * CGFloat(ringIndex)
            let outerR = centerRadius + ringWidth * CGFloat(ringIndex + 1)

            SunburstSlice(
                startAngle: slice.startAngle,
                endAngle: slice.endAngle,
                innerRadius: innerR,
                outerRadius: outerR
            )
            .fill(slice.color)
            .overlay(
                SunburstSlice(
                    startAngle: slice.startAngle,
                    endAngle: slice.endAngle,
                    innerRadius: innerR,
                    outerRadius: outerR
                )
                .stroke(
                    isSelected ? Color.primary :
                    isHovered ? Color.primary.opacity(0.5) :
                    Color(nsColor: .windowBackgroundColor),
                    lineWidth: isSelected ? 2.5 : isHovered ? 1.5 : 1
                )
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .opacity(animationProgress)
            .allowsHitTesting(false)
        }
    }
}

// MARK: - File Info Panel

struct FileInfoPanel: View {
    let node: FileNode
    let onMoveToTrash: () -> Void

    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: node.icon)
                    .font(.largeTitle)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(node.name)
                        .font(.headline)
                        .lineLimit(2)

                    Text(node.isDirectory ? "Folder" : "File")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Size Info
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Size")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(node.formattedSize)
                        .fontWeight(.medium)
                }

                HStack {
                    Text("Percentage")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f%%", node.percentage))
                        .fontWeight(.medium)
                }

                if node.isDirectory, let children = node.children {
                    HStack {
                        Text("Contents")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(children.count) items")
                            .fontWeight(.medium)
                    }
                }
            }
            .font(.subheadline)

            Divider()

            // Path
            VStack(alignment: .leading, spacing: 4) {
                Text("Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(node.url.path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }

            Spacer()

            // Actions
            VStack(spacing: 8) {
                if node.isDirectory {
                    Button(action: {
                        NSWorkspace.shared.open(node.url)
                    }) {
                        Label("Open in Finder", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive, action: {
                    showDeleteConfirmation = true
                }) {
                    Label("Move to Trash", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
        .confirmationDialog(
            "Move to Trash?",
            isPresented: $showDeleteConfirmation,
            presenting: node
        ) { node in
            Button("Move to Trash", role: .destructive) {
                onMoveToTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: { node in
            Text("Are you sure you want to move '\(node.name)' to the trash?")
        }
    }
}

// MARK: - Toolbar

struct ToolbarView: View {
    let isScanning: Bool
    let progress: String
    let progressFraction: Double
    let onSelectFolder: () -> Void
    let onGoBack: () -> Void
    let canGoBack: Bool

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onGoBack) {
                Image(systemName: "chevron.left")
            }
            .disabled(!canGoBack || isScanning)

            Button(action: onSelectFolder) {
                Label("Select Folder", systemImage: "folder.badge.plus")
            }
            .disabled(isScanning)

            Spacer()

            if isScanning {
                Text(progress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                ProgressView(value: progressFraction)
                    .frame(width: 120)

                Text("\(Int(progressFraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 36, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "externaldrive.fill.badge.icloud")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Disk Space Analyzer")
                    .font(.title2)
                    .fontWeight(.medium)

                Text("Select a folder to visualize its contents")
                    .foregroundStyle(.secondary)
            }

            Button(action: onSelectFolder) {
                Label("Select Folder", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 20)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Sidebar View

struct SidebarView: View {
    @Binding var navigationPath: [FileNode]
    @Binding var selectedNode: FileNode?
    let rootNode: FileNode?
    let favorites: [URL]
    let onScan: (URL) -> Void
    let onAddFavorite: (URL) -> Void
    let onRemoveFavorite: (URL) -> Void
    let onSelectFolder: () -> Void

    @State private var mountedVolumes: [URL] = []
    @State private var expandedNodes: Set<UUID> = []

    private static let defaultFavorites: [(name: String, icon: String, url: URL?)] = [
        ("Home", "house.fill", FileManager.default.homeDirectoryForCurrentUser as URL?),
        ("Desktop", "menubar.dock.rectangle", FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first),
        ("Documents", "doc.fill", FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first),
        ("Downloads", "arrow.down.circle.fill", FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first),
        ("Applications", "app.dashed", URL(fileURLWithPath: "/Applications")),
    ]

    var body: some View {
        List(selection: Binding(
            get: { navigationPath.last?.id },
            set: { newId in
                guard let id = newId else { return }
                if let node = findNode(withId: id, in: rootNode) {
                    navigateToNode(node)
                }
            }
        )) {
            // Drives Section
            Section("Drives") {
                ForEach(mountedVolumes, id: \.self) { url in
                    DriveRow(url: url, isFavorite: favorites.contains(url)) {
                        onScan(url)
                    } onAddFavorite: {
                        onAddFavorite(url)
                    } onRemoveFavorite: {
                        onRemoveFavorite(url)
                    }
                }
            }

            // Favourites Section
            Section("Favourites") {
                ForEach(Self.defaultFavorites, id: \.name) { fav in
                    if let url = fav.url {
                        HStack(spacing: 8) {
                            Image(systemName: fav.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 16)
                            Text(fav.name)
                                .lineLimit(1)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { onScan(url) }
                    }
                }

                // User-added favourites
                ForEach(favorites, id: \.self) { url in
                    FavoriteRow(url: url) {
                        onRemoveFavorite(url)
                    } onScan: {
                        onScan(url)
                    }
                }
            }

            // Current Scan Section
            if let root = rootNode {
                Section("Current Scan") {
                    OutlineGroup(root, children: \.children) { node in
                        SidebarNodeRow(
                            node: node,
                            isSelected: navigationPath.last?.id == node.id,
                            onSelect: { navigateToNode(node) },
                            onAddFavorite: { onAddFavorite(node.url) }
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .onAppear { refreshVolumes() }
        .contextMenu(forSelectionType: UUID.self) { items in
            if let id = items.first,
               let node = findNode(withId: id, in: rootNode) {
                Button("Add to Favorites") {
                    onAddFavorite(node.url)
                }
            }
        }
    }

    private func refreshVolumes() {
        var volumes: [URL] = [URL(fileURLWithPath: "/")]
        if let mounted = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.localizedNameKey],
            options: [.skipHiddenVolumes]
        ) {
            let external = mounted.filter {
                $0.path != "/" && !$0.path.hasPrefix("/System/Volumes")
            }
            volumes.append(contentsOf: external)
        }
        mountedVolumes = volumes
    }

    private func navigateToNode(_ node: FileNode) {
        var path: [FileNode] = []
        _ = buildPath(to: node, from: rootNode, path: &path)
        navigationPath = path
        selectedNode = node
    }

    private func buildPath(to target: FileNode, from current: FileNode?, path: inout [FileNode]) -> Bool {
        guard let current = current else { return false }
        path.append(current)
        if current.id == target.id { return true }
        for child in current.children ?? [] {
            if buildPath(to: target, from: child, path: &path) { return true }
        }
        path.removeLast()
        return false
    }

    private func findNode(withId id: UUID, in node: FileNode?) -> FileNode? {
        guard let node = node else { return nil }
        if node.id == id { return node }
        for child in node.children ?? [] {
            if let found = findNode(withId: id, in: child) { return found }
        }
        return nil
    }
}

// MARK: - Sidebar Row Views

struct DriveRow: View {
    let url: URL
    let isFavorite: Bool
    let onScan: () -> Void
    let onAddFavorite: () -> Void
    let onRemoveFavorite: () -> Void

    private var volumeName: String {
        (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.fill")
                .foregroundStyle(.secondary)
            Text(volumeName)
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onScan() }
        .contextMenu {
            Button("Scan") { onScan() }
            Divider()
            if isFavorite {
                Button("Remove from Favorites", role: .destructive) { onRemoveFavorite() }
            } else {
                Button("Add to Favorites") { onAddFavorite() }
            }
        }
    }
}

struct FavoriteRow: View {
    let url: URL
    let onRemove: () -> Void
    let onScan: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.yellow)
            Text(url.lastPathComponent)
                .lineLimit(1)
            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture { onScan() }
        .contextMenu {
            Button("Scan") { onScan() }
            Divider()
            Button("Remove from Favorites", role: .destructive) { onRemove() }
        }
    }
}

struct SidebarNodeRow: View {
    let node: FileNode
    let isSelected: Bool
    let onSelect: () -> Void
    let onAddFavorite: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: node.icon)
                .foregroundStyle(isSelected ? .blue : .secondary)
                .frame(width: 16)
            Text(node.name)
                .lineLimit(1)
            Spacer()
            Text(node.formattedSize)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu {
            Button("Add to Favorites") { onAddFavorite() }
            if node.isDirectory {
                Button("Open in Finder") {
                    NSWorkspace.shared.open(node.url)
                }
            }
        }
    }
}
