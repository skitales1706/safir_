import SwiftUI

/// The app's own recent log (AppLog) - the only way to see what happened on the phone without a
/// Mac. The share button sends it via Telegram/mail for debugging.
struct LogView: View {
    @State private var lines: [String] = []

    var body: some View {
        List(Array(lines.enumerated().reversed()), id: \.offset) { _, line in
            Text(line)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
        }
        .navigationTitle("Журнал")
        .toolbar {
            ShareLink(item: lines.joined(separator: "\n"))
        }
        .onAppear { lines = AppLog.snapshot() }
        .refreshable { lines = AppLog.snapshot() }
    }
}
