import SwiftUI

private func formatReset(_ date: Date, long: Bool = false) -> String {
    let mins = max(0, Int(date.timeIntervalSinceNow / 60))
    if mins >= 1440 { return "\(mins / 1440)d \((mins % 1440) / 60)h" }
    if mins >= 60 { return long ? "\(mins / 60)h \(mins % 60)m" : "\(mins / 60)h" }
    return "\(mins)m"
}

struct UsageBar: View {
    let title: String
    let percent: Double?
    let resetsAt: Date?
    var compact = false
    var emptyText = "No data yet"

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer()
                Text(percent.map { "\(Int($0.rounded()))%" } ?? "–").font(.system(size: 13, weight: .semibold)).monospacedDigit()
            }
            .foregroundStyle(Color.primary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.14))
                    if let percent {
                        Capsule().fill(Color.primary.opacity(0.7))
                            .frame(width: max(g.size.height, g.size.width * min(percent, 100) / 100))
                    }
                }
            }
            .frame(height: compact ? 6 : 8)
            Subtitle(text: resetsAt.map { "Resets in \(formatReset($0, long: !compact))" } ?? emptyText)
        }
    }
}

struct ClaudePage: View {
    @EnvironmentObject var m: Monitor

    private func box<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glass(.rect(cornerRadius: 16))
    }

    var body: some View {
        GlassGroup {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Button { m.page = .main } label: {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.primary).frame(width: 28, height: 28)
                            .glass(.circle)
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    Text("Claude").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                }
                EyesPanel().frame(height: 84)
                box {
                    let w = m.claude?.fiveHour
                    UsageBar(title: "Session (5hr)", percent: m.claude == nil ? nil : (w?.percent ?? 0), resetsAt: w?.resetsAt,
                             emptyText: m.claude == nil ? "No data yet" : "No active session")
                }
                box {
                    let w = m.claude?.sevenDay
                    UsageBar(title: "Weekly (7 days)", percent: m.claude == nil ? nil : (w?.percent ?? 0), resetsAt: w?.resetsAt,
                             emptyText: m.claude == nil ? "No data yet" : "No active window")
                }
            }
            .padding(12)
        }
    }
}
