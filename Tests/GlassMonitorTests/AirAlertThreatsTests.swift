import Testing
@testable import GlassMonitor

@Suite struct AirAlertThreats {
    let report = """
    # Situation report

    ## 3. ALERTS
    - **20:10 — attack drones (2 tracked)** over Lozova (Лозова) — 🛵 not in the threat section

    ## 4. THREAT ACTIVITY
    - **20:30 — attack drones (1 tracked)** over Lozova (Лозова) — 🛵 strike drone to Lozova
    - **20:28 — ballistic missile** over Kyiv (Київ) — 🚀 launch from the north
    - **20:25 — cruise missiles (4)** over Lozova (Лозова) — moving west
    - **20:20 — guided aerial bombs** over Lozova (Лозова) — ✈️ KAB launches
    - **20:15 — jet drones** over Lozova (Лозова) — fourth match, over the limit

    ## 5. NEXT
    - **21:00 — attack drones** over Lozova (Лозова) — after the section
    """

    @Test func keepsOnlyNearbyThreatsFromTheSection() {
        let lines = AirAlertMonitor.threats(in: report, near: ["лозова"])
        #expect(lines == [
            "20:30 · ударні БпЛА — Лозова: strike drone to Lozova",
            "20:25 · крилаті ракети — Лозова: moving west",
            "20:20 · КАБи — Лозова: KAB launches",
        ])
    }

    @Test func ballisticIsNamedAsSuch() {
        let lines = AirAlertMonitor.threats(in: report, near: ["київ"])
        #expect(lines == ["20:28 · балістика — Київ: launch from the north"])
    }

    @Test func noSectionNoThreats() {
        #expect(AirAlertMonitor.threats(in: "## 3. ALERTS\n- nothing", near: ["лозова"]).isEmpty)
    }

    @Test func otherPlacesAreIgnored() {
        #expect(AirAlertMonitor.threats(in: report, near: ["одеса"]).isEmpty)
    }
}
