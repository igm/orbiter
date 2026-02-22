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
