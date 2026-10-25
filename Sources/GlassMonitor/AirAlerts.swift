import AppKit
import CoreLocation

/// Air-raid alerts for the user's area, from siren.pp.ua (a public, cached mirror of the
/// official "Повітряна тривога" / ukrainealarm.com API). No key needed; only a generic GET is sent —
/// the user's location never leaves the Mac, it is matched against the region list locally.
/// Not an official warning system: the official app and sirens come first.
@MainActor
final class AirAlertMonitor: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Region {
        let id: String
        let name: String
        let type: String          // State / District / Community
        let stateId: String
        let districtId: String?
    }

    struct ActiveAlert: Equatable {
        let regionName: String
        let red: Bool             // Red = missiles / mass strike, Yellow = drones
        let since: Date?
        var reason: String? = nil         // "Дронова загроза (жовтий рівень)"
        var threats: [String] = []        // what is flying near you, newest first
    }

    /// Where we look for alerts: automatic (location) or a region picked in the menu.
    struct Place {
        var stateId: String?
        var districtId: String?
        var communityId: String?
        var extraIds: [String] = []   // e.g. the oblast around a city that has its own region (Харків, Запоріжжя)
        var label: String
    }

    @Published private(set) var alert: ActiveAlert?
    @Published private(set) var autoPlace: Place?
    @Published private(set) var manualChanged = 0      // bumps the UI when the region is picked by hand

    private(set) var states: [Region] = []
    private(set) var districtsByState: [String: [Region]] = [:]
    private var communitiesByDistrict: [String: [Region]] = [:]
    private var regions: [String: Region] = [:]

    private static let base = "https://siren.pp.ua/api/v3"
    private static let manualKey = "airAlertRegion"      // region id, or nil = automatic
    private static let pollEvery: TimeInterval = 15

    private let location = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var timers: [Timer] = []
    private var threatLines: [String] = []
    private var lastThreatFetch = Date.distantPast

    var manualRegionId: String? {
        get { UserDefaults.standard.string(forKey: Self.manualKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.manualKey)
            manualChanged += 1
            Task { await poll() }
        }
    }

    func region(_ id: String) -> Region? { regions[id] }

    /// Human label of the watched place (manual pick or detected location).
    var watchedLabel: String? {
        if let id = manualRegionId, let r = regions[id] {
            return r.type == "State" ? r.name : "\(r.name), \(regions[r.stateId]?.name ?? "")"
        }
        return autoPlace?.label
    }

    func start() {
        guard timers.isEmpty else { return }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyKilometer
        Task {
            await loadRegions()
            requestLocation()
            await poll()
        }
        timers.append(Timer.scheduledTimer(withTimeInterval: Self.pollEvery, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.requestLocation() }
        })
    }

    // MARK: Network

    private func get(_ path: String) async -> Data? {
        var req = URLRequest(url: URL(string: Self.base + path)!, timeoutInterval: 10)
        req.setValue("GlassMonitor (github.com/kio00o/glass-monitor)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private struct RegionDTO: Decodable {
        let regionId: String
        let regionName: String
        let regionType: String
        let regionChildIds: [RegionDTO]?
    }
    private struct RegionsDTO: Decodable { let states: [RegionDTO] }
    private struct LevelDTO: Decodable { let alertLevel: String; let reason: String?; let createdAt: String? }
    private struct ActiveDTO: Decodable { let type: String; let lastUpdate: String?; let activeAlertLevels: [LevelDTO]? }
    private struct EntryDTO: Decodable { let regionId: String; let regionName: String; let activeAlerts: [ActiveDTO] }

    private func loadRegions() async {
        guard states.isEmpty, let data = await get("/regions"),
              let dto = try? JSONDecoder().decode(RegionsDTO.self, from: data) else { return }
        for s in dto.states where !s.regionName.lowercased().contains("тестов") {
            let state = Region(id: s.regionId, name: s.regionName, type: "State", stateId: s.regionId, districtId: nil)
            states.append(state); regions[state.id] = state
            for d in s.regionChildIds ?? [] {
                let district = Region(id: d.regionId, name: d.regionName, type: d.regionType, stateId: s.regionId, districtId: d.regionId)
                districtsByState[s.regionId, default: []].append(district); regions[district.id] = district
                for c in d.regionChildIds ?? [] {
                    let community = Region(id: c.regionId, name: c.regionName, type: c.regionType, stateId: s.regionId, districtId: d.regionId)
                    communitiesByDistrict[d.regionId, default: []].append(community); regions[community.id] = community
                }
            }
        }
        states.sort { $0.name < $1.name }
        if let loc = location.location { await resolve(loc) }
    }

    func poll() async {
        if states.isEmpty { await loadRegions() }
        guard let data = await get("/alerts"),
              let entries = try? JSONDecoder().decode([EntryDTO].self, from: data) else { return }   // keep last state on failure
        var a = match(entries)
        if a != nil {
            await refreshThreats()
            a?.threats = threatLines
        } else {
            threatLines = []
        }
        alert = a
    }

    // MARK: What is flying (alerts.in.ua live report)

    /// alerts.in.ua publishes a Markdown situation report that its robots.txt/llms.txt says is
    /// fine to fetch without a token. Only fetched while an alert is active, at most once a minute.
    private func refreshThreats() async {
        guard Date().timeIntervalSince(lastThreatFetch) > 60 else { return }
        lastThreatFetch = Date()
        var req = URLRequest(url: URL(string: "https://alerts.in.ua/llm")!, timeoutInterval: 10)
        req.setValue("GlassMonitor (github.com/kio00o/glass-monitor)", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200, let text = String(data: data, encoding: .utf8) else { return }
        threatLines = Self.threats(in: text, near: myNames())
    }

    /// Ukrainian names of the place we watch, normalised, split on " та " ("м. Буча та Бучанська …").
    private func myNames() -> Set<String> {
        var ids: [String] = []
        if let id = manualRegionId, let r = regions[id] { ids = [r.stateId, r.id] }
        else if let p = autoPlace { ids = [p.stateId, p.districtId, p.communityId].compactMap { $0 } + p.extraIds }
        var names = Set<String>()
        for id in ids { for part in (regions[id]?.name ?? "").components(separatedBy: " та ") { names.insert(Self.norm(part)) } }
        names.remove("")
        return names
    }

    nonisolated private static let threatWords: [(String, String)] = [
        ("ballistic", "балістика"), ("cruise missile", "крилаті ракети"), ("missile", "ракети"),
        ("guided aerial bomb", "КАБи"), ("jet", "реактивні БпЛА"), ("attack drone", "ударні БпЛА"),
        ("drone", "БпЛА"), ("aircraft", "авіація"), ("aviation", "авіація"),
    ]

    /// Lines like: "- **20:30 — attack drones (1 tracked)** over Lozova (Лозова) — 🛵 strike drone to Lozova …"
    nonisolated static func threats(in report: String, near names: Set<String>) -> [String] {
        guard let start = report.range(of: "## 4. THREAT ACTIVITY") else { return [] }
        let section = report[start.upperBound...].prefix { _ in true }
        let body = section.components(separatedBy: "\n## ").first ?? ""
        let rx = try! NSRegularExpression(pattern: #"^- \*\*(\d{1,2}:\d{2}) — ([^*]+)\*\* over .*?\(([^()]+)\)\s*—\s*(.*)$"#)
        var out: [String] = []
        for line in body.components(separatedBy: "\n") {
            let ns = line as NSString
            guard let m = rx.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let time = ns.substring(with: m.range(at: 1)), kind = ns.substring(with: m.range(at: 2)).lowercased()
            let place = ns.substring(with: m.range(at: 3))
            var detail = ns.substring(with: m.range(at: 4))
            detail = detail.unicodeScalars.drop { !$0.properties.isAlphabetic }.map(String.init).joined()   // strip leading emoji
            guard names.contains(norm(place)) else { continue }
            let what = threatWords.first { kind.contains($0.0) }?.1 ?? kind
            out.append("\(time) · \(what) — \(place): \(detail)")
            if out.count == 3 { break }
        }
        return out
    }

    // MARK: Matching

    /// Which alert entries concern the chosen place.
    private func match(_ entries: [EntryDTO]) -> ActiveAlert? {
        let iso = ISO8601DateFormatter()
        var relevant: (String) -> Bool = { _ in false }

        if let id = manualRegionId, let r = regions[id] {
            if r.type == "State" {   // "whole oblast": any alert anywhere inside it
                relevant = { [regions] eid in regions[eid]?.stateId == r.id }
            } else {                 // a district: the oblast itself or that district
                relevant = { eid in eid == r.stateId || eid == r.id }
            }
        } else if let p = autoPlace {
            let ids = Set([p.stateId, p.districtId, p.communityId].compactMap { $0 } + p.extraIds)
            relevant = { ids.contains($0) }
        }

        var found: ActiveAlert?
        for e in entries where relevant(e.regionId) {
            let air = e.activeAlerts.filter { $0.type == "AIR" }
            guard !air.isEmpty else { continue }
            let levels = air.flatMap { $0.activeAlertLevels ?? [] }
            let red = levels.isEmpty || levels.contains { $0.alertLevel == "Red" }   // no level reported = red
            let since = (levels.compactMap { $0.createdAt } + air.compactMap { $0.lastUpdate })
                .compactMap { iso.date(from: $0) }.min()
            let reason = levels.sorted { ($0.alertLevel == "Red" ? 0 : 1) < ($1.alertLevel == "Red" ? 0 : 1) }
                .compactMap { $0.reason }.first { !$0.isEmpty }
            let a = ActiveAlert(regionName: e.regionName, red: red, since: since, reason: reason)
            if found == nil || (a.red && !(found!.red)) { found = a }               // prefer the stronger one
        }
        return found
    }

    // MARK: Location → region

    private func requestLocation() {
        switch location.authorizationStatus {
        case .notDetermined: location.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways: location.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.requestLocation() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in await self.resolve(loc) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}

    nonisolated private static func norm(_ s: String?) -> String {
        var t = (s ?? "").lowercased()
        for junk in ["’", "'", "ʼ", "`"] { t = t.replacingOccurrences(of: junk, with: "") }
        for word in ["територіальна громада", "область", "обл.", "район", "місто ", "м. "] {
            t = t.replacingOccurrences(of: word, with: "")
        }
        return t.trimmingCharacters(in: .whitespaces)
    }

    private func resolve(_ loc: CLLocation) async {
        guard !states.isEmpty,
              let pm = try? await geocoder.reverseGeocodeLocation(loc, preferredLocale: Locale(identifier: "uk_UA")).first
        else { return }
        let adm = Self.norm(pm.administrativeArea), sub = Self.norm(pm.subAdministrativeArea)
        let city = Self.norm(pm.locality)
        let cityStem = city.count > 4 ? String(city.dropLast()) : city

        // Cities with their own top-level region ("м. Київ", "м. Харків та …") win over the oblast.
        let state = states.first { !city.isEmpty && $0.name.lowercased().hasPrefix("м. \(city)") }
            ?? states.first { Self.norm($0.name) == adm }
        guard let state else { autoPlace = Place(label: pm.administrativeArea ?? "Unknown"); return }

        let districts = districtsByState[state.id] ?? []
        var district = districts.first { !sub.isEmpty && Self.norm($0.name) == sub }
        func cityMatch(_ c: Region) -> Bool {
            !cityStem.isEmpty && (c.name.lowercased().hasPrefix("м. \(city)") || Self.norm(c.name).hasPrefix(cityStem))
        }
        var community = district.flatMap { d in communitiesByDistrict[d.id]?.first(where: cityMatch) }
        if district == nil {    // geocoder gave no raion: find the city's community, then its district
            for d in districts { if let c = communitiesByDistrict[d.id]?.first(where: cityMatch) { district = d; community = c; break } }
        }

        // A city region (м. Харків …) sits inside an oblast whose oblast-wide / raion alerts also apply.
        var extra: [String] = []
        if let oblast = states.first(where: { Self.norm($0.name) == adm }), oblast.id != state.id {
            extra.append(oblast.id)
            if let d = districtsByState[oblast.id]?.first(where: { !sub.isEmpty && Self.norm($0.name) == sub }) { extra.append(d.id) }
        }

        let label = [community?.name ?? district?.name, state.type == "State" ? state.name : nil]
            .compactMap { $0 }.removingDuplicates().joined(separator: ", ")
        autoPlace = Place(stateId: state.id, districtId: district?.id, communityId: community?.id, extraIds: extra, label: label)
        await poll()
    }
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

/// Yellow rocket for the menu bar (coloured on purpose, so not a template image).
enum RocketIcon {
    static func image() -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let t = NSAffineTransform()
            t.translateX(by: 9, yBy: 9); t.rotate(byDegrees: -45); t.translateX(by: -9, yBy: -9)
            t.concat()
            let yellow = NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)

            // flame
            yellow.withAlphaComponent(0.5).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7.6, y: 0.8, width: 2.8, height: 3.6)).fill()
            // fins
            yellow.setFill()
            for side: CGFloat in [-1, 1] {
                let f = NSBezierPath()
                f.move(to: NSPoint(x: 9 + 2.7 * side, y: 4.6)); f.line(to: NSPoint(x: 9 + 4.9 * side, y: 2.8))
                f.line(to: NSPoint(x: 9 + 4.9 * side, y: 6.4)); f.line(to: NSPoint(x: 9 + 2.7 * side, y: 8.4)); f.close()
                f.fill()
            }
            // body with a pointed nose
            let b = NSBezierPath()
            b.move(to: NSPoint(x: 6.3, y: 4.2)); b.line(to: NSPoint(x: 6.3, y: 10.4))
            b.curve(to: NSPoint(x: 9, y: 16.6), controlPoint1: NSPoint(x: 6.3, y: 13.6), controlPoint2: NSPoint(x: 8, y: 15.6))
            b.curve(to: NSPoint(x: 11.7, y: 10.4), controlPoint1: NSPoint(x: 10, y: 15.6), controlPoint2: NSPoint(x: 11.7, y: 13.6))
            b.line(to: NSPoint(x: 11.7, y: 4.2)); b.close()
            b.fill()
            // window (cut out)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: NSRect(x: 7.75, y: 9.2, width: 2.5, height: 2.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            return true
        }
        img.isTemplate = false
        return img
    }
}
