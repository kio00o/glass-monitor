import SwiftUI

/// Show/hide and reorder the panel cards. The mascot is always shown and is not listed.
/// Drag a row by its handle to reorder; up to `maxWidgets` can be on at once.
struct SettingsPage: View {
    @EnvironmentObject var m: Monitor

    private func icon(_ w: Monitor.Widget) -> String {
        switch w {
        case .disk: return "internaldrive"
        case .memory: return "memorychip"
        case .cpu: return "cpu"
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
                    Text("\(m.enabledWidgets.count) of \(Monitor.maxWidgets)")
                        .font(.system(size: 11.5)).foregroundStyle(Color.primary.opacity(0.62))
                }
                List {
                    ForEach(m.widgetOrder, id: \.self) { w in
                        row(w)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onMove { m.moveWidgets(from: $0, to: $1) }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(Monitor.Widget.allCases.count) * 44)
                .glass(.rect(cornerRadius: 16))
                Text("The mascot is always shown. Up to \(Monitor.maxWidgets) cards; turn one off to add another. Drag the handle to reorder.")
                    .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.45))
                    .padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
        }
    }

    private func row(_ w: Monitor.Widget) -> some View {
        let on = m.isEnabled(w)
        let locked = !m.canEnable(w)   // at the cap and this one is off
        return HStack(spacing: 10) {
            Image(systemName: icon(w)).font(.system(size: 14)).foregroundStyle(Color.primary).frame(width: 24)
            Text(w.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
            Spacer()
            Button { m.toggle(w) } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(.system(size: 16))
                    .foregroundStyle(on ? Color.primary : Color.primary.opacity(0.3))
            }
            .buttonStyle(.plain).disabled(locked)
            Image(systemName: "line.3.horizontal").font(.system(size: 13))
                .foregroundStyle(Color.primary.opacity(0.35))
        }
        .padding(.horizontal, 14).frame(height: 44)
        .opacity(locked ? 0.4 : 1)
        .overlay(alignment: .bottom) { Divider().overlay(Color.primary.opacity(0.08)).padding(.leading, 48) }
    }
}
