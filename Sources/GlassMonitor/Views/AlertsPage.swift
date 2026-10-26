import SwiftUI

// MARK: - Air-raid alert card

struct AirAlertCard: View {
    @EnvironmentObject var air: AirAlertMonitor
    @EnvironmentObject var m: Monitor

    private static let yellow = Color(red: 1, green: 0.84, blue: 0.04)
    private static let red = Color(red: 1, green: 0.27, blue: 0.23)

    var body: some View {
        let a = air.alert
        let accent = a.map { $0.red ? Self.red : Self.yellow }
        HStack(alignment: .top, spacing: 10) {
            Group {
                if a != nil {
                    Image(nsImage: FaceIcon.drone(size: 22, color: a!.red ? FaceIcon.alertRed : FaceIcon.alertColor))
                        .resizable().frame(width: 22, height: 22)
                } else {
                    Image(systemName: "checkmark.shield").font(.system(size: 18)).foregroundStyle(Color.primary.opacity(0.62))
                }
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Title(text: a == nil ? "Тривоги немає" : "Повітряна тривога")
                    Spacer(minLength: 6)
                    if let since = a?.since {
                        Text("з \(ukTime(since))")
                            .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(accent ?? Color.primary)
                    }
                }
                if let a {
                    Subtitle(text: a.regionName)
                    Text(a.reason ?? (a.red ? "Червоний рівень" : "Жовтий рівень"))
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(accent ?? Color.primary)
                    if !a.threats.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(a.threats, id: \.self) { t in
                                Text(t).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.75))
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.top, 4)
                    }
                } else {
                    Subtitle(text: air.watchedLabel ?? "Визначаю регіон…")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(.rect(cornerRadius: 16))
        .overlay {
            if let accent { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.55), lineWidth: 1) }
        }
        .contentShape(.rect(cornerRadius: 16))
        .onTapGesture { m.page = .alerts }
        .animation(.easeInOut(duration: 0.25), value: a)
    }
}

// MARK: - Alerts map page

private let alertColor = Color(nsColor: FaceIcon.alertColor)

/// 24-hour Ukrainian time ("21:56", or "25 жовт., 21:56" for older alerts) regardless of the system's 12-hour setting.
private func ukTime(_ d: Date, withDate: Bool = false) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "uk_UA")
    f.dateFormat = withDate ? "d MMM, HH:mm" : "HH:mm"
    return f.string(from: d)
}

struct AlertsPage: View {
    @EnvironmentObject var m: Monitor
    @EnvironmentObject var air: AirAlertMonitor

    var body: some View {
        let active = air.oblasts.filter { !$0.value.standing }.count
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
                    Text("Мапа тривог").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.primary)
                    Spacer()
                    Text(active == 0 ? "Тривог немає" : "Тривога в \(active) обл.")
                        .font(.system(size: 11.5)).foregroundStyle(active == 0 ? Color.primary.opacity(0.62) : alertColor)
                }
                HStack(alignment: .top, spacing: 10) {
                    EyesPanel().frame(width: 120, height: 84)
                    myRegionCard
                }
                VStack(alignment: .leading, spacing: 10) {
                    if let map = UkraineMap.shared {
                        // fixed size: a flexible map lets the window shrink when the hover label appears
                        AlertMap(map: map, oblasts: air.oblasts, mine: air.watchedOblast)
                            .frame(width: 408, height: (408 / map.aspect).rounded())
                    } else {
                        Subtitle(text: "Мапа недоступна")
                    }
                    HStack(spacing: 12) {
                        legend(alertColor.opacity(0.95), "уся область")
                        legend(alertColor.opacity(0.62), "частина")
                        legend(alertColor.opacity(0.22), "тривала")
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).strokeBorder(Color.primary, lineWidth: 1.4).frame(width: 10, height: 10)
                            Text("твій регіон")
                        }
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 10.5)).foregroundStyle(Color.primary.opacity(0.62))
                    if let t = air.updatedAt {
                        Text("Оновлено о \(ukTime(t)) · siren.pp.ua · не замінює офіційні сповіщення")
                            .font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.45))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glass(.rect(cornerRadius: 16))
            }
            .padding(12)
        }
    }

    /// Details about the user's own oblast, shown next to the mascot above the map.
    private var myRegionCard: some View {
        let a = air.alert
        let o = air.watchedOblast.flatMap { air.oblasts[$0] }
        let accent = a.map { $0.red ? Color(nsColor: FaceIcon.alertRed) : alertColor }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: a == nil ? "checkmark.shield" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(accent ?? Color.primary.opacity(0.55))
                Text(air.watchedLabel ?? "Регіон не визначено")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary).lineLimit(1).minimumScaleFactor(0.8)
            }
            if let a {
                Text(a.reason ?? (a.red ? "Ракетна небезпека" : "Повітряна тривога"))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent ?? Color.primary)
                HStack(spacing: 8) {
                    if let since = a.since { pill("з " + ukTime(since)) }
                    if let o, !o.whole, o.areas > 0 { pill("\(o.areas) р-н\(o.areas == 1 ? "" : "и")") }
                }
                if let t = a.threats.first {
                    Text(t).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.7))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true).padding(.top, 1)
                }
            } else {
                Text("Тривоги немає").font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.55))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
        .glass(.rect(cornerRadius: 16))
        .overlay { if let accent { RoundedRectangle(cornerRadius: 16).strokeBorder(accent.opacity(0.5), lineWidth: 1) } }
    }

    private func pill(_ text: String) -> some View {
        Text(text).font(.system(size: 10, weight: .medium)).monospacedDigit()
            .foregroundStyle(Color.primary.opacity(0.75))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color.primary.opacity(0.1), in: .capsule)
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10); Text(text) }
    }
}

/// Ukraine with oblasts tinted by alert state; the watched oblast is outlined; hover shows details.
private struct AlertMap: View {
    let map: UkraineMap
    let oblasts: [String: AirAlertMonitor.OblastAlert]
    let mine: String?
    // @State is a macro in the new SDK and the Command Line Tools ship no plugin for it → keep hover in a tiny object
    private final class Hover: ObservableObject { @Published var value: (name: String, at: CGPoint)? }
    @StateObject private var hoverBox = Hover()
    private var hover: (name: String, at: CGPoint)? { hoverBox.value }

    private static func path(_ r: UkraineMap.Region, _ size: CGSize) -> Path {
        var p = Path()
        for poly in r.polys {
            guard let f = poly.first else { continue }
            p.move(to: CGPoint(x: f.x * size.width, y: f.y * size.height))
            for q in poly.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
            p.closeSubpath()
        }
        return p
    }

    private func label(_ name: String) -> String {
        guard let o = oblasts[name] else { return "\(name)\nТривоги немає" }
        var lines = [name]
        if o.standing { lines.append("Тривала тривога") }
        else { lines.append(o.whole ? "Тривога на всю область" : "Тривога в \(o.areas) \(o.areas == 1 ? "громаді/районі" : "громадах/районах")") }
        if let since = o.since {
            lines.append("з " + ukTime(since, withDate: !Calendar.current.isDateInToday(since)))
        }
        if o.red { lines.append("Червоний рівень") }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        GeometryReader { g in
            canvas
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let pt):
                        // last match wins: м. Київ is drawn over Київська область
                        hoverBox.value = map.regions.last { Self.path($0, g.size).contains(pt) }.map { ($0.name, pt) }
                    case .ended: hoverBox.value = nil
                    }
                }
        }
    }

    private var canvas: some View {
        Canvas { ctx, size in
            func path(_ r: UkraineMap.Region) -> Path { Self.path(r, size) }
            for r in map.regions {
                let p = path(r)
                let fill: Color
                if let o = oblasts[r.name] {
                    fill = o.standing ? alertColor.opacity(0.22) : alertColor.opacity(o.whole ? 0.95 : 0.62)
                } else {
                    fill = Color.primary.opacity(0.08)
                }
                ctx.fill(p, with: .color(fill))
                ctx.stroke(p, with: .color(Color.primary.opacity(0.28)), style: StrokeStyle(lineWidth: 0.6, lineJoin: .round))
            }
            if let mine, let r = map.regions.first(where: { $0.name == mine }) {
                ctx.stroke(path(r), with: .color(.primary), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            }
            if let h = hover, let r = map.regions.last(where: { $0.name == h.name }) {
                ctx.stroke(path(r), with: .color(alertColor), style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))

                // Hover label drawn inside the canvas with a solid background: a separate overlay view with a
                // material made the Liquid Glass card around the map re-render (streaks at the edges).
                let text = ctx.resolve(Text(label(h.name)).font(.system(size: 11)).foregroundStyle(Color.primary))
                let ts = text.measure(in: CGSize(width: 220, height: 200))
                let box = CGSize(width: ts.width + 16, height: ts.height + 12)
                let x = min(max(h.at.x + 12, 0), size.width - box.width)
                let y = h.at.y - box.height - 10 < 0 ? h.at.y + 16 : h.at.y - box.height - 10
                let rect = CGRect(x: x, y: min(y, size.height - box.height), width: box.width, height: box.height)
                ctx.fill(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color(nsColor: .windowBackgroundColor).opacity(0.96)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 8), with: .color(Color.primary.opacity(0.15)), lineWidth: 0.5)
                ctx.draw(text, in: rect.insetBy(dx: 8, dy: 6))
            }
        }
    }
}
