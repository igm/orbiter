import SwiftUI
import AppKit

struct ContentView: View {
    @StateObject private var scanner = FileScanner()
    @State private var selectedNode: FileNode?
    @State private var navigationPath: [FileNode] = []
    @State private var showFolderPicker = false
    @State private var volumes: [VolumeInfo] = []
    @State private var hasFullDiskAccess = false

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
            ToolbarView(
                isScanning: scanner.isScanning,
                progress: scanner.scanProgress,
                progressFraction: scanner.progressFraction,
                navigationPath: navigationPath,
                onSelectFolder: { showFolderPicker = true },
                onNavigate: navigateTo
            )

            Divider()

            if let root = scanner.rootNode {
                HSplitView {
                    SunburstChart(
                        root: root,
                        currentDirectory: currentDirectory,
                        selectedNode: $selectedNode,
                        onDrillDown: { node in
                            navigationPath.append(node)
                            selectedNode = nil
                        },
                        onMoveToTrash: moveToTrash
                    )
                    .frame(minWidth: 500)

                    FileInfoPanel(
                        node: selectedNode ?? currentDirectory,
                        onMoveToTrash: moveSelectedToTrash
                    )
                }
            } else if scanner.isScanning {
                VStack(spacing: 16) {
                    ProgressView(value: scanner.progressFraction)
                        .frame(width: 200)
                    Text("\(Int(scanner.progressFraction * 100))%")
                        .font(.title2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(scanner.scanProgress)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiskSelectionView(
                    volumes: volumes,
                    hasFullDiskAccess: hasFullDiskAccess,
                    onScan: requestAccessAndScan,
                    onSelectFolder: { showFolderPicker = true }
                )
            }
        }
        .onKeyPress(.escape) {
            selectedNode = nil
            return .handled
        }
        .onKeyPress(.delete) {
            if navigationPath.count > 1 {
                goBack()
                return .handled
            }
            return .ignored
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
        .onAppear {
            volumes = FileScanner.mountedVolumes()
            hasFullDiskAccess = FileScanner.hasFullDiskAccess
        }
    }

    // MARK: - Navigation

    private func goBack() {
        guard navigationPath.count > 1 else { return }
        navigationPath.removeLast()
        selectedNode = nil
    }

    private func navigateTo(index: Int) {
        guard index < navigationPath.count else { return }
        navigationPath = Array(navigationPath.prefix(index + 1))
        selectedNode = nil
    }

    // MARK: - Scanning

    private func scanURL(_ url: URL) {
        navigationPath = []
        selectedNode = nil
        scanner.scan(url: url)
    }

    private func requestAccessAndScan(_ url: URL) {
        let panel = NSOpenPanel()
        panel.directoryURL = url
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Grant access to scan this location"
        panel.prompt = "Scan"

        panel.begin { response in
            if response == .OK, let selectedURL = panel.url {
                scanURL(selectedURL)
            }
        }
    }

    // MARK: - Trash

    private func moveSelectedToTrash() {
        guard let node = selectedNode else { return }
        moveToTrash(node)
    }

    private func moveToTrash(_ node: FileNode) {
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
