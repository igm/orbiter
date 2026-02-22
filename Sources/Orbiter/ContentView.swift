import SwiftUI

struct ContentView: View {
    @StateObject private var scanner = FileScanner()
    @State private var selectedNode: FileNode?
    @State private var navigationPath: [FileNode] = []
    @State private var showFolderPicker = false
    @State private var favorites: [URL] = []

    @AppStorage("favorites") private var favoritesData: Data = Data()

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
        NavigationSplitView {
            SidebarView(
                navigationPath: $navigationPath,
                selectedNode: $selectedNode,
                rootNode: scanner.rootNode,
                favorites: favorites,
                onScan: scanURL,
                onAddFavorite: addFavorite,
                onRemoveFavorite: removeFavorite,
                onSelectFolder: { showFolderPicker = true }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
        } detail: {
            VStack(spacing: 0) {
                // Toolbar
                ToolbarView(
                    isScanning: scanner.isScanning,
                    progress: scanner.scanProgress,
                    onSelectFolder: { showFolderPicker = true },
                    onGoBack: goBack,
                    canGoBack: navigationPath.count > 1
                )

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
                    FileInfoPanel(
                        node: selectedNode ?? currentDirectory,
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
                    scanURL(url)
                }
            case .failure(let error):
                scanner.error = error
            }
        }
        .onChange(of: scanner.rootNode) { oldValue, newNode in
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
        .onAppear { loadFavorites() }
    }

    // MARK: - Actions

    private func goBack() {
        guard navigationPath.count > 1 else { return }
        navigationPath.removeLast()
        selectedNode = nil
    }

    private func scanURL(_ url: URL) {
        navigationPath = []
        selectedNode = nil
        scanner.scan(url: url)
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

    // MARK: - Favorites

    private func loadFavorites() {
        if let decoded = try? JSONDecoder().decode([URL].self, from: favoritesData) {
            favorites = decoded
        }
    }

    private func saveFavorites() {
        if let encoded = try? JSONEncoder().encode(favorites) {
            favoritesData = encoded
        }
    }

    private func addFavorite(_ url: URL) {
        if !favorites.contains(url) {
            favorites.append(url)
            saveFavorites()
        }
    }

    private func removeFavorite(_ url: URL) {
        favorites.removeAll { $0 == url }
        saveFavorites()
    }
}

#Preview {
    ContentView()
        .frame(width: 1000, height: 700)
}
