import SwiftUI

private func formatMemory(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    return gb >= 1 ? String(format: "%.1f GB", gb).replacingOccurrences(of: ".", with: ",")
                   : String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

struct MemoryPage: View {
    @EnvironmentObject var m: Monitor

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
                    Text("Memory").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text("Pressure: \(m.memoryPressure)%").font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62))
                }
                VStack(spacing: 0) {
                    if m.memoryApps.isEmpty {
                        Subtitle(text: "Loading…").padding(14)
                    }
                    ForEach(m.memoryApps) { a in
                        HStack(spacing: 10) {
                            Image(nsImage: a.icon).resizable().frame(width: 28, height: 28)
                            Text(a.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(formatMemory(a.bytes)).font(.system(size: 11.5)).monospacedDigit()
                                .foregroundStyle(Color.primary.opacity(0.62))
                            Button { m.quit(a) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(Color.primary).frame(width: 24, height: 24)
                                    .glass(.circle)
                                    .contentShape(.circle)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(a.name)")
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        if a.id != m.memoryApps.last?.id {
                            Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 52)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.rect(cornerRadius: 16))
                .animation(.easeInOut(duration: 0.2), value: m.memoryApps.map(\.id))
            }
            .padding(12)
        }
    }
}
