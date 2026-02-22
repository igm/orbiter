import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = FileScanner()
    @State private var selectedNode: FileNode?
    @State private var navigationPath: [FileNode] = []
    @State private var showFolderPicker = false

    private var currentDirectory: FileNode {
        if let last = navigationPath.last {
            return last
        }
        if let root = scanner.rootNode {
            return root
        }
        return FileNode(
            url: URL(fileURLWithPath: "/"),
            name: "Root",
            isDirectory: true,
            size: 0,
            children: []
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            ToolbarView(
                isScanning: scanner.isScanning,
                progress: scanner.scanProgress,
                onSelectFolder: { showFolderPicker = true },
                onGoBack: goBack,
                canGoBack: navigationPath.count > 1
            )

            // Breadcrumb
            if !navigationPath.isEmpty {
                BreadcrumbView(
                    path: navigationPath,
                    onSelect: { node in
                        if let index = navigationPath.firstIndex(where: { $0.id == node.id }) {
                            navigationPath = Array(navigationPath.prefix(through: index))
                            selectedNode = nil
                        }
                    }
                )
                .padding(.vertical, 8)
                .background(Color(nsColor: .windowBackgroundColor))
            }

            Divider()

            // Main Content
            HSplitView {
                // Chart Area
                Group {
                    if let root = scanner.rootNode {
                        SunburstChart(
                            root: root,
                            currentDirectory: currentDirectory,
                            selectedNode: $selectedNode,
                            onDrillDown: { node in
                                navigationPath.append(node)
                                selectedNode = nil
                            }
                        )
                    } else if scanner.isScanning {
                        ProgressView(scanner.scanProgress)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        EmptyStateView(onSelectFolder: { showFolderPicker = true })
                    }
                }
                .frame(minWidth: 500)

                // Info Panel
                if let selected = selectedNode {
                    FileInfoPanel(
                        node: selected,
                        onMoveToTrash: moveSelectedToTrash
                    )
                }
            }
        }
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    navigationPath = []
                    selectedNode = nil
                    scanner.scan(url: url)
                }
            case .failure(let error):
                scanner.error = error
            }
        }
        .onChange(of: scanner.rootNode) { newNode in
            if let node = newNode, navigationPath.isEmpty {
                navigationPath = [node]
            }
        }
        .alert("Error", isPresented: .init(
            get: { scanner.error != nil },
            set: { if !$0 { scanner.error = nil } }
        )) {
            Button("OK") { scanner.error = nil }
        } message: {
            Text(scanner.error?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Actions

    private func goBack() {
        guard navigationPath.count > 1 else { return }
        navigationPath.removeLast()
        selectedNode = nil
    }

    private func moveSelectedToTrash() {
        guard let node = selectedNode else { return }
        Task {
            if await scanner.moveToTrash(node: node) {
                if let root = scanner.rootNode {
                    navigationPath = []
                    scanner.scan(url: root.url)
                }
                selectedNode = nil
            }
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
