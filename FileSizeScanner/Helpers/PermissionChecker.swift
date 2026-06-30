import Foundation
import AppKit

struct PermissionChecker {

    /// Returns true if the app has sufficient disk access for scanning.
    /// First checks for Full Disk Access via TCC.db; falls back to probing
    /// protected paths that are inaccessible without FDA.
    static var hasFullDiskAccess: Bool {
        // Primary indicator: system TCC database is only readable with FDA
        if FileManager.default.isReadableFile(
            atPath: "/Library/Application Support/com.apple.TCC/TCC.db"
        ) { return true }

        // Secondary: probe a path that requires FDA but is not user-readable otherwise
        let fm = FileManager.default
        let protectedPaths = [
            "/private/var/folders",
            "/Library/Application Support/com.apple.TCC"
        ]
        for path in protectedPaths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue,
               (try? fm.contentsOfDirectory(atPath: path)) != nil {
                return true
            }
        }
        return false
    }

    /// Opens System Settings directly to the Full Disk Access pane.
    static func openFullDiskAccessSettings() {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }
}
