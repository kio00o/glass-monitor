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

    /// Alert state of every oblast, keyed by the map's region name ("Київська область", "м. Київ", …).
    struct OblastAlert: Equatable {
        var whole = false        // declared for the oblast itself
        var areas = 0            // raions / hromadas under alert inside it
        var red = false
        var standing = false     // older than a week: the administrative alert over occupied territory
        var since: Date?         // earliest start among its active alerts (fresh ones preferred)
        var freshSince: Date?
    }
    @Published private(set) var oblasts: [String: OblastAlert] = [:]
    @Published private(set) var updatedAt: Date?
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
        oblasts = oblastStatus(entries)
        updatedAt = Date()
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

    /// The API mixes "…T16:45:00Z" and "…T02:23:21.15503Z" (fractional seconds).
    nonisolated private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    // MARK: Map

    private func oblastStatus(_ entries: [EntryDTO]) -> [String: OblastAlert] {
        var out: [String: OblastAlert] = [:]
        var fresh = Set<String>()
        for e in entries {
            let air = e.activeAlerts.filter { $0.type == "AIR" }
            guard !air.isEmpty, let r = regions[e.regionId], let state = regions[r.stateId] else { continue }
            var name = state.name
            // cities that are their own top-level region (м. Харків та …, м. Запоріжжя та …) sit inside an oblast
            if name.hasPrefix("м. "), name != "м. Київ", let city = name.dropFirst(3).split(separator: " ").first {
                let stem = Self.norm(String(city)).prefix(5)
                if let oblast = states.first(where: { !$0.name.hasPrefix("м. ") && Self.norm($0.name).hasPrefix(stem) }) { name = oblast.name }
            }
            var o = out[name] ?? OblastAlert()
            if r.type == "State" && !state.name.hasPrefix("м. ") || state.name == "м. Київ" { o.whole = true } else { o.areas += 1 }
            let levels = air.flatMap { $0.activeAlertLevels ?? [] }
            if levels.isEmpty || levels.contains(where: { $0.alertLevel == "Red" }) { o.red = true }
            let since = (levels.compactMap { $0.createdAt } + air.compactMap { $0.lastUpdate }).compactMap(Self.parseDate).min()
            let old = since.map { Date().timeIntervalSince($0) > 7 * 86400 } ?? false
            if !old { fresh.insert(name) }
            // shown start time: the earliest fresh alert; weeks-old frontline ones only when there is nothing else
            if let since { if old { o.since = min(o.since ?? since, since) } else { o.freshSince = min(o.freshSince ?? since, since) } }
            out[name] = o
        }
        for (name, var o) in out {
            o.standing = !fresh.contains(name)          // only weeks-old alerts → administrative / occupied
            if let f = o.freshSince { o.since = f }
            out[name] = o
        }
        return out
    }

    /// Name of the oblast we watch, as on the map.
    var watchedOblast: String? {
        if let id = manualRegionId, let r = regions[id] { return regions[r.stateId]?.name }
        return autoPlace?.stateId.flatMap { regions[$0]?.name }
    }

    // MARK: Matching

    /// Which alert entries concern the chosen place.
    private func match(_ entries: [EntryDTO]) -> ActiveAlert? {
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
                .compactMap(Self.parseDate).min()
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

/// Oblast outlines (Natural Earth, public domain; simplified, normalised to 0…1, y down) from Assets/ukraine_map.json.
struct UkraineMap {
    struct Region { let name: String; let polys: [[CGPoint]] }
    let aspect: CGFloat
    let regions: [Region]

    static let shared: UkraineMap? = {
        struct DTO: Decodable { let aspect: Double; let regions: [R]; struct R: Decodable { let name: String; let polys: [[[Double]]] } }
        guard let url = Bundle.main.url(forResource: "ukraine_map", withExtension: "json"),
              let data = try? Data(contentsOf: url), let d = try? JSONDecoder().decode(DTO.self, from: data) else { return nil }
        return UkraineMap(aspect: CGFloat(d.aspect), regions: d.regions.map { r in
            Region(name: r.name, polys: r.polys.map { $0.map { CGPoint(x: $0[0], y: $0[1]) } })
        })
    }()
}
