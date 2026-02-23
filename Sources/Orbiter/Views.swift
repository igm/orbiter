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
    let onMoveToTrash: (FileNode) -> Void

    @State private var hoveredNode: FileNode?
    @State private var animationProgress: CGFloat = 0
    @State private var expandedNodes: Set<UUID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                CenterCircle(
                    node: currentDirectory,
                    hoveredNode: hoveredNode,
                    selectedNode: selectedNode
                )

                ForEach(Array(allRings.enumerated()), id: \.offset) { ringIndex, slices in
                    ForEach(slices) { slice in
                        let isExpandable = slice.node.isDirectory
                            && slice.node.children?.isEmpty == false
                            && slice.depth >= baseDepth - 1
                            && !expandedNodes.contains(slice.node.id)

                        SliceView(
                            slice: slice,
                            ringIndex: ringIndex,
                            isHovered: hoveredNode?.id == slice.node.id,
                            isSelected: selectedNode?.id == slice.node.id,
                            isExpandable: isExpandable,
                            animationProgress: animationProgress,
                            ringWidth: rw,
                            centerRadius: centerRadius
                        )
                        .accessibilityElement()
                        .accessibilityLabel("\(slice.node.name), \(slice.node.formattedSize)")
                        .accessibilityHint(slice.node.isDirectory ? "Double-click to expand" : "")
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
                if reduceMotion {
                    toggleExpansion(node)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        toggleExpansion(node)
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
            .contextMenu {
                if let node = hoveredNode {
                    Button("Open in Finder") {
                        NSWorkspace.shared.open(node.isDirectory ? node.url : node.url.deletingLastPathComponent())
                    }
                    if node.isDirectory, let children = node.children, !children.isEmpty {
                        Button("Expand") { onDrillDown(node) }
                    }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(node.url.path, forType: .string)
                    }
                    Divider()
                    Button("Move to Trash", role: .destructive) {
                        onMoveToTrash(node)
                    }
                }
            }
            .onAppear {
                if reduceMotion {
                    animationProgress = 1
                } else {
                    withAnimation(.easeOut(duration: 0.6)) {
                        animationProgress = 1
                    }
                }
            }
            .onChange(of: currentDirectory.id) { _, _ in
                expandedNodes.removeAll()
            }
        }
    }

    private func toggleExpansion(_ node: FileNode) {
        if expandedNodes.contains(node.id) {
            collapseNode(node)
        } else {
            expandedNodes.insert(node.id)
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

        let firstRing = buildSlicesInArc(
            nodes: children,
            startAngle: .degrees(-90),
            arcSpan: 360.0,
            depth: 0,
            parentColorIndex: nil
        )
        result.append(firstRing)

        var parentSlices = firstRing
        var depth = 1
        let hardCap = 10

        while !parentSlices.isEmpty && depth < hardCap {
            var ringSlices: [SliceData] = []

            for parent in parentSlices {
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
    let isExpandable: Bool
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
            .overlay(
                Group {
                    if isExpandable {
                        SunburstSlice(
                            startAngle: slice.startAngle,
                            endAngle: slice.endAngle,
                            innerRadius: outerR - 0.005,
                            outerRadius: outerR
                        )
                        .fill(Color.primary.opacity(isHovered ? 0.3 : 0.12))
                    }
                }
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
    let navigationPath: [FileNode]
    let onSelectFolder: () -> Void
    let onNavigate: (Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelectFolder) {
                Image(systemName: "folder.badge.plus")
            }
            .disabled(isScanning)

            if !navigationPath.isEmpty {
                Divider().frame(height: 16)
                BreadcrumbView(path: navigationPath, onNavigate: onNavigate)
            }

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
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Breadcrumb View

struct BreadcrumbView: View {
    let path: [FileNode]
    let onNavigate: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(path.enumerated()), id: \.element.id) { index, node in
                    if index > 0 {
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                    }

                    Button(action: { onNavigate(index) }) {
                        Text(node.name)
                            .font(.subheadline)
                            .fontWeight(index == path.count - 1 ? .semibold : .regular)
                            .foregroundStyle(index == path.count - 1 ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(index == path.count - 1)
                }
            }
        }
    }
}

// MARK: - Disk Selection View

struct DiskSelectionView: View {
    let volumes: [VolumeInfo]
    let hasFullDiskAccess: Bool
    let onScan: (URL) -> Void
    let onSelectFolder: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 320))], spacing: 16) {
                ForEach(volumes) { volume in
                    VolumeCard(volume: volume, onScan: { onScan(volume.url) })
                }
            }
            .padding(.horizontal, 48)

            Spacer()

            VStack(spacing: 12) {
                Button(action: onSelectFolder) {
                    Label("Select Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                if !hasFullDiskAccess {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield")
                            .font(.caption)
                        Text("Grant Full Disk Access in System Settings for complete scanning")
                            .font(.caption)
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
                            )
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct VolumeCard: View {
    let volume: VolumeInfo
    let onScan: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: volume.icon)
                    .font(.title2)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(volume.name)
                        .font(.headline)
                    Text("\(volume.formattedAvailable) available of \(volume.formattedTotal)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .separatorColor))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(usageColor)
                        .frame(width: geo.size.width * volume.usageFraction)
                }
            }
            .frame(height: 8)

            Button(action: onScan) {
                Text("Scan")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(isHovered ? 0.15 : 0.05), radius: isHovered ? 8 : 4)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { isHovered = $0 }
    }

    private var usageColor: Color {
        if volume.usageFraction > 0.9 { return .red }
        if volume.usageFraction > 0.75 { return .orange }
        return .blue
    }
}
