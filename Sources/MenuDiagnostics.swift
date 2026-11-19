import Foundation

/// Records menu dispatch failures without recording menu contents or user input.
enum MenuDiagnostics {
    private static let LOG_PATH = "/tmp/tuck-menu-diagnostics.log"

    /// Appends one timestamped event to the local diagnostic file.
    static func record(_ message: String) {
        let line = "\(Date()): \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: LOG_PATH) {
            FileManager.default.createFile(atPath: LOG_PATH, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        guard let handle = FileHandle(forWritingAtPath: LOG_PATH) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            NSLog("Tuck: cannot append menu diagnostics: %@", error.localizedDescription)
        }
    }
}
