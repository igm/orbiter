import Foundation

private actor ProgressCounter {
    private var count = 0
    func increment() -> Int {
        count += 1
        return count
    }
}

@MainActor
class FileScanner: ObservableObject {
    @Published var rootNode: FileNode?
    @Published var isScanning = false
    @Published var scanProgress: String = ""
    @Published var progressFraction: Double = 0
    @Published var error: Error?

    private var scanningTask: Task<FileNode?, Never>?
    private var accessedURL: URL?

    func scan(url: URL) {
        cancelScan()

        let granted = url.startAccessingSecurityScopedResource()
        if granted {
            accessedURL = url
        }

        scanningTask = Task {
            isScanning = true
            scanProgress = "Starting scan..."
            progressFraction = 0
            error = nil

            let node = await scanDirectory(url: url, depth: 0)

            if var node = node, !Task.isCancelled {
                node.calculatePercentages(total: node.size)
                rootNode = node
                isScanning = false
                scanProgress = ""
                progressFraction = 1.0
            }

            return node
        }
    }

    func cancelScan() {
        scanningTask?.cancel()
        scanningTask = nil
        stopAccessingCurrentURL()
        isScanning = false
        scanProgress = ""
        progressFraction = 0
    }

    private func stopAccessingCurrentURL() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }

    private nonisolated func scanDirectory(url: URL, depth: Int) async -> FileNode? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return nil }

        let name = (try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? url.lastPathComponent

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            let size = Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
            return FileNode(url: url, name: name, isDirectory: false, size: size, children: nil)
        }


        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey, .fileSizeKey, .isPackageKey],
            options: []
        ) else {
            return FileNode(url: url, name: name, isDirectory: true, size: 0, children: [])
        }

        if Task.isCancelled { return nil }

        let isRoot = depth == 0
        let totalItems = contents.count
        let completed: ProgressCounter? = isRoot ? ProgressCounter() : nil

        return await withTaskGroup(of: FileNode?.self, returning: FileNode?.self) { group in
            for itemURL in contents {
                group.addTask {
                    if Task.isCancelled { return nil }

                    let result: FileNode?
                    if let isPackage = try? itemURL.resourceValues(forKeys: [.isPackageKey]).isPackage,
                       isPackage {
                        let size = self.directorySize(at: itemURL)
                        let pkgName = (try? itemURL.resourceValues(forKeys: [.localizedNameKey]).localizedName) ?? itemURL.lastPathComponent
                        result = FileNode(url: itemURL, name: pkgName,
                                        isDirectory: true, size: size, children: nil)
                    } else {
                        result = await self.scanDirectory(url: itemURL, depth: depth + 1)
                    }

                    if isRoot, let counter = completed {
                        let itemName = result?.name ?? itemURL.lastPathComponent
                        let count = await counter.increment()
                        let fraction = Double(count) / Double(totalItems)
                        await MainActor.run {
                            if fraction > self.progressFraction {
                                self.progressFraction = fraction
                                self.scanProgress = itemName
                            }
                        }
                    }

                    return result
                }
            }

            var children: [FileNode] = []
            var totalSize: Int64 = 0
            for await child in group {
                if Task.isCancelled { return nil }
                if let child = child {
                    children.append(child)
                    totalSize += child.size
                }
            }
            children.sort { $0.size > $1.size }
            return FileNode(url: url, name: name, isDirectory: true, size: totalSize, children: children)
        }
    }

    private nonisolated func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey])
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileSize ?? 0)
        }
        return total
    }

    // MARK: - Full Disk Access Detection

    static var hasFullDiskAccess: Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    // MARK: - Volume Detection

    static func mountedVolumes() -> [VolumeInfo] {
        let fm = FileManager.default
        var volumes: [VolumeInfo] = []
        let keys: Set<URLResourceKey> = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeIsRemovableKey, .volumeIsInternalKey
        ]

        // Root volume
        let rootURL = URL(fileURLWithPath: "/")
        if let values = try? rootURL.resourceValues(forKeys: keys) {
            volumes.append(VolumeInfo(
                url: rootURL,
                name: values.volumeName ?? "Macintosh HD",
                totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
                availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
                isRemovable: values.volumeIsRemovable ?? false,
                isInternal: values.volumeIsInternal ?? true
            ))
        }

        // External/other volumes
        if let mounted = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) {
            for url in mounted where url.path != "/" && !url.path.hasPrefix("/System/Volumes") {
                if let values = try? url.resourceValues(forKeys: keys) {
                    volumes.append(VolumeInfo(
                        url: url,
                        name: values.volumeName ?? url.lastPathComponent,
                        totalCapacity: Int64(values.volumeTotalCapacity ?? 0),
                        availableCapacity: Int64(values.volumeAvailableCapacity ?? 0),
                        isRemovable: values.volumeIsRemovable ?? false,
                        isInternal: values.volumeIsInternal ?? true
                    ))
                }
            }
        }

        return volumes
    }

    func moveToTrash(node: FileNode) async -> Bool {
        let fileManager = FileManager.default
        do {
            var resultURL: NSURL?
            try fileManager.trashItem(at: node.url, resultingItemURL: &resultURL)
            return true
        } catch {
            await MainActor.run { self.error = error }
            return false
        }
    }
}

// MARK: - Trash Manager

@MainActor
class TrashManager: ObservableObject {
    @Published var items: [TrashItem] = []
    @Published var isPurging = false

    var totalSize: Int64 {
        items.reduce(0) { $0 + $1.node.size }
    }

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var trashedURLs: Set<URL> {
        Set(items.map(\.node.url))
    }

    func addToTrash(_ node: FileNode) {
        guard !isDirectlyTrashed(node.url) else { return }
        items.append(TrashItem(node: node, trashedAt: Date()))
    }

    func removeFromTrash(_ item: TrashItem) {
        items.removeAll { $0.id == item.id }
    }

    func removeAll() {
        items.removeAll()
    }

    func isDirectlyTrashed(_ url: URL) -> Bool {
        trashedURLs.contains(url)
    }

    func isAffectedByTrash(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        return items.contains { item in
            let trashedPath = item.node.url.standardizedFileURL.path
            return path == trashedPath || path.hasPrefix(trashedPath + "/")
        }
    }

    func toggleTrash(_ node: FileNode) {
        if let existing = items.first(where: { $0.node.url == node.url }) {
            removeFromTrash(existing)
        } else {
            addToTrash(node)
        }
    }

    func purgeAll() async -> Bool {
        isPurging = true
        let fm = FileManager.default
        var allSuccess = true

        for item in items {
            do {
                var resultURL: NSURL?
                try fm.trashItem(at: item.node.url, resultingItemURL: &resultURL)
            } catch {
                allSuccess = false
            }
        }

        items.removeAll()
        isPurging = false
        return allSuccess
    }
}
