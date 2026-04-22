import Foundation

enum DebugLogger {
    private static let logURL = URL(fileURLWithPath: "/tmp/TextExpanderLite-debug.log")
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
        }

        try? data.write(to: logURL, options: [.atomic])
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }

    static func path() -> String {
        logURL.path
    }
}
