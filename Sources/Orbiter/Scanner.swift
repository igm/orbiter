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
