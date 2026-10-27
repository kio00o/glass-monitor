import SwiftUI

/// Pick which cards appear on the main panel. The mascot is always shown and is not listed.
struct SettingsPage: View {
    @EnvironmentObject var m: Monitor

    private func icon(_ w: Monitor.Widget) -> String {
        switch w {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .claude: return "sparkles"
        case .wifi: return "wifi"
        case .battery: return "battery.100percent"
        case .devices: return "dot.radiowaves.left.and.right"
        case .alerts: return "exclamationmark.triangle"
        }
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
                    Text("Widgets").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text("\(m.enabledWidgets.count) of \(Monitor.Widget.allCases.count)")
                        .font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62))
                }
                VStack(spacing: 0) {
                    ForEach(Array(Monitor.Widget.allCases.enumerated()), id: \.element) { i, w in
                        Button { m.toggle(w) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: icon(w)).font(.system(size: 14))
                                    .foregroundStyle(Color.primary).frame(width: 24)
                                Text(w.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
                                Spacer()
                                Image(systemName: m.isEnabled(w) ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16))
                                    .foregroundStyle(m.isEnabled(w) ? Color.primary : Color.primary.opacity(0.3))
                            }
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        if i != Monitor.Widget.allCases.count - 1 {
                            Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 48)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.rect(cornerRadius: 16))
                Text("The mascot is always shown. Changes apply right away.")
                    .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.45))
                    .padding(.horizontal, 4)
            }
            .padding(12)
        }
    }
}
