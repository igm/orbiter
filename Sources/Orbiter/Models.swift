import Foundation
import SwiftUI

struct FileNode: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64
    var children: [FileNode]?

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var percentage: Double = 0

    var icon: String {
        if isDirectory {
            return "folder.fill"
        }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv":
            return "video.fill"
        case "mp3", "wav", "flac", "aac":
            return "music.note"
        case "pdf":
            return "doc.fill"
        case "zip", "rar", "7z", "tar", "gz":
            return "doc.zipper"
        case "app":
            return "app.fill"
        case "dmg":
            return "externaldrive.fill"
        default:
            return "doc.fill"
        }
    }

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension FileNode {
    mutating func calculatePercentages(total: Int64) {
        if total > 0 {
            percentage = Double(size) / Double(total) * 100
        }
        if var children = children {
            for i in children.indices {
                children[i].calculatePercentages(total: total)
            }
            self.children = children
        }
    }
}

struct SliceData: Identifiable {
    var id: UUID { node.id }
    let node: FileNode
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let depth: Int
    let colorIndex: Int
}

// MARK: - Trash Item

struct TrashItem: Identifiable, Hashable {
    let id = UUID()
    let node: FileNode
    let trashedAt: Date
}

// MARK: - Volume Info

struct VolumeInfo: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let totalCapacity: Int64
    let availableCapacity: Int64
    let isRemovable: Bool
    let isInternal: Bool

    var usedCapacity: Int64 { totalCapacity - availableCapacity }

    var usageFraction: Double {
        guard totalCapacity > 0 else { return 0 }
        return Double(usedCapacity) / Double(totalCapacity)
    }

    var formattedTotal: String { ByteCountFormatter.string(fromByteCount: totalCapacity, countStyle: .file) }
    var formattedUsed: String { ByteCountFormatter.string(fromByteCount: usedCapacity, countStyle: .file) }
    var formattedAvailable: String { ByteCountFormatter.string(fromByteCount: availableCapacity, countStyle: .file) }

    var icon: String {
        if url.path == "/" { return "internaldrive.fill" }
        if isRemovable { return "externaldrive.fill" }
        return "externaldrive.fill"
    }
}

