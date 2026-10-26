import Foundation
import os

/// There's no Xcode debugger for this project (builds run in cloud CI), so the app keeps its own
/// recent log, viewable and shareable from the debug screen. Never log tokens or message text.
enum AppLog {
    private static let logger = Logger(subsystem: "tj.safir.messenger", category: "app")
    private static let lock = NSLock()
    private static var lines: [String] = []
    private static let maxLines = 500

    static func write(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let stamp = Date().formatted(date: .omitted, time: .standard)
        lock.lock()
        lines.append("\(stamp) \(message)")
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
    }

    static func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
