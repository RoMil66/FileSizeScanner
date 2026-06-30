import Foundation

/// Represents a file or directory node in the scanned tree
final class FileNode: Identifiable, ObservableObject {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    var size: Int64
    var children: [FileNode]
    var fileCount: Int
    var folderCount: Int
    var modifiedDate: Date?

    /// Percentage of parent's size (0-1)
    var percentage: Double = 0

    /// True when this folder was excluded from scanning because it is a cloud storage mount
    var isCloudSkipped: Bool = false

    var formattedSize: String {
        SizeFormatter.format(size)
    }

    init(url: URL, name: String, isDirectory: Bool, size: Int64 = 0, children: [FileNode] = [], modifiedDate: Date? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.children = children
        self.fileCount = isDirectory ? 0 : 1
        self.folderCount = isDirectory ? 1 : 0
        self.modifiedDate = modifiedDate
    }
    
    /// Recursively compute sizes and counts, then sort children by size descending
    func computeSizeAndSort() {
        guard isDirectory else { return }
        
        var totalSize: Int64 = 0
        var totalFiles = 0
        var totalFolders = 1 // count self
        
        for child in children {
            child.computeSizeAndSort()
            totalSize += child.size
            totalFiles += child.fileCount
            totalFolders += child.folderCount
        }
        
        self.size = totalSize
        self.fileCount = totalFiles
        self.folderCount = totalFolders
        
        // Sort children by size descending
        children.sort { $0.size > $1.size }
        
        // Compute percentages
        if totalSize > 0 {
            for child in children {
                child.percentage = Double(child.size) / Double(totalSize)
            }
        }
    }
    
    /// File extension (lowercase, without dot)
    var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    /// SF Symbol name for file type
    var iconName: String {
        if isDirectory {
            return "folder.fill"
        }
        switch fileExtension {
        case "swift", "py", "js", "ts", "c", "cpp", "h", "m", "java", "rb", "go", "rs":
            return "doc.text.fill"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "svg":
            return "photo.fill"
        case "mp4", "mov", "avi", "mkv", "wmv", "flv":
            return "film.fill"
        case "mp3", "wav", "aac", "flac", "m4a", "ogg":
            return "music.note"
        case "pdf":
            return "doc.richtext.fill"
        case "zip", "gz", "tar", "rar", "7z", "dmg":
            return "doc.zipper"
        case "app":
            return "app.fill"
        case "xcodeproj", "xcworkspace":
            return "hammer.fill"
        default:
            return "doc.fill"
        }
    }
    
    /// Color for the icon
    var iconColorName: String {
        if isDirectory { return "blue" }
        switch fileExtension {
        case "swift": return "orange"
        case "py": return "green"
        case "js", "ts": return "yellow"
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff", "heic", "webp", "svg": return "purple"
        case "mp4", "mov", "avi", "mkv": return "red"
        case "mp3", "wav", "aac", "flac", "m4a": return "pink"
        case "pdf": return "red"
        case "zip", "gz", "tar", "rar", "7z", "dmg": return "gray"
        default: return "secondary"
        }
    }
}

extension FileNode: Hashable {
    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
