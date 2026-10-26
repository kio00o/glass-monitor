import SwiftUI

// MARK: - Formatting

func formatSpeed(_ bytesPerSec: Double) -> String {
    let kb = bytesPerSec / 1024
    if kb < 1024 { return String(format: "%.0f KB/sec", kb) }
    return String(format: "%.1f MB/sec", kb / 1024)
}

// MARK: - Building blocks

struct Card<Content: View>: View {
    var fill = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: fill ? .infinity : nil, alignment: .topLeading)
            .glass(.rect(cornerRadius: 16))
    }
}

struct Title: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8) }
}

struct Subtitle: View {
    let text: String
    var body: some View { Text(text).font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62)).lineLimit(1).minimumScaleFactor(0.8) }
}

struct ActionLink: View {
    let text: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
        }
        .buttonStyle(.plain)
    }
}
