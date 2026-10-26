import SwiftUI
import Combine
import ServiceManagement

private final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private struct PanelRoot: View {
    static let radius: CGFloat = 28
    var body: some View {
        ContentView()
            .clipShape(.rect(cornerRadius: Self.radius))
            .overlay(RoundedRectangle(cornerRadius: Self.radius).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
    }
}

/// Status-bar button + a borderless panel that slides in from the right edge of the screen.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let monitor = Monitor()
    private let eyes = EyesModel()
    private let menuIcon = MenuIconModel()
    private let airAlerts = AirAlertMonitor()
    private var droneItem: NSStatusItem?
    private var droneTask: Task<Void, Never>?
    private var alertRed = false

    private var statusItem: NSStatusItem!
    private var panel: Panel!
    private var host: NSHostingController<AnyView>!
    private var cancellables = Set<AnyCancellable>()
    private var clickMonitor: Any?
    private var visible = false
    private var lastHide = Date.distantPast

    private let edgeMargin: CGFloat = 8, topGap: CGFloat = 6

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Notifier.shared.setup()
        #if DEBUG
        setvbuf(stdout, nil, _IOLBF, 0)        // ./dev.sh with GM_LOG: lines reach the file as they are printed
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("dev.local.glassmonitor.debug"),
                                                            object: nil, queue: .main) { [weak self] n in
            let cmd = n.object as? String ?? ""
            MainActor.assumeIsolated { self?.debugCommand(cmd) }
        }
        #endif
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("dev.local.glassmonitor.test"),
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Notifier.shared.sendTest() }
        }

        // Start at login once; afterwards the right-click menu controls it.
        // Not for debug builds: they live in .build and would replace the installed app at login.
        #if !DEBUG
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }
        #endif

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.image = menuIcon.image
            b.target = self
            b.action = #selector(statusClicked)
            b.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        menuIcon.$image.receive(on: DispatchQueue.main).sink { [weak self] in
            self?.statusItem.button?.image = $0
        }.store(in: &cancellables)

        // Yellow menu-bar eyes while there is an air-raid alert in the user's area.
        airAlerts.$alert.receive(on: DispatchQueue.main).sink { [weak self] alert in
            self?.alertRed = alert?.red ?? false
            self?.showDrone(alert != nil)            // drone slides in next to them; dot shows severity
        }.store(in: &cancellables)
        // Angry, lowered eyes during an air-raid alert or while the CPU is hot.
        airAlerts.$alert.map { $0 != nil }.combineLatest(monitor.$cpuHot).receive(on: DispatchQueue.main)
            .sink { [weak self] alarm, hot in self?.menuIcon.alert = alarm || hot }.store(in: &cancellables)
        monitor.$cpuHot.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.eyes.nudge() }.store(in: &cancellables)
        // "92°" next to the eyes while hot or when enabled; cpuTemp changes on every refresh, so this follows it live.
        monitor.$cpuTemp.combineLatest(monitor.$cpuHot).receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &cancellables)
        // redraw the drone (black/white) when the menu-bar appearance flips
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDroneImage() }
        }
        airAlerts.start()
        eyes.alarmed = { [airAlerts] in airAlerts.alert != nil }
        airAlerts.$alert.map { $0 != nil }.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.eyes.nudge() }.store(in: &cancellables)

        // "14% · 3h" next to the icon: session usage and time until it resets.
        monitor.$claude.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.updateStatusTitle() }
            .store(in: &cancellables)
        Timer.publish(every: 30, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.updateStatusTitle() }.store(in: &cancellables)

        host = NSHostingController(rootView: AnyView(PanelRoot().environmentObject(monitor).environmentObject(eyes).environmentObject(airAlerts)))
        host.sizingOptions = [.preferredContentSize]
        host.view.wantsLayer = true
        host.view.layer?.backgroundColor = .clear

        panel = Panel(contentViewController: host)
        // Pages have different heights: keep the panel pinned to the top-right when its content resizes.
        host.publisher(for: \.preferredContentSize).receive(on: DispatchQueue.main).sink { [weak self] size in
            guard let self, self.visible, size.width > 0 else { return }
            self.panel.setFrame(self.finalFrame(size: size), display: true)
        }.store(in: &cancellables)
        panel.styleMask = [.borderless, .nonactivatingPanel]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    // MARK: Air-raid drone

    private func showDrone(_ on: Bool) {
        droneTask?.cancel()
        if on && droneItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: 0)   // created after the eyes → sits to their left
            item.button?.imageScaling = .scaleNone
            item.button?.target = self
            item.button?.action = #selector(openAlertsPage)
            droneItem = item
        }
        if on { refreshDroneImage() }
        guard let item = droneItem else { return }
        let from = item.length, to: CGFloat = on ? 24 : 0
        droneTask = Task {
            for i in 1...10 where !Task.isCancelled {
                let t = CGFloat(i) / 10
                item.length = from + (to - from) * (1 - pow(1 - t, 3))
                item.button?.alphaValue = on ? t : 1 - t
                try? await Task.sleep(for: .milliseconds(30))
            }
            if !on, !Task.isCancelled { NSStatusBar.system.removeStatusItem(item); droneItem = nil }
        }
    }

    /// Draw the drone black or white to match the current menu bar, with a red/yellow severity dot.
    private func refreshDroneImage() {
        guard let button = droneItem?.button else { return }
        let dark = button.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let dot = alertRed ? FaceIcon.alertRed : FaceIcon.alertColor
        button.image = FaceIcon.drone(size: 18, color: dark ? .white : .black, dot: dot)
    }

    @objc private func openAlertsPage() {
        monitor.page = .alerts
        if !visible { show() }
    }

    // MARK: Air-raid region

    private func alertRegionMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Air Alert Region", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let manual = airAlerts.manualRegionId
        let autoTitle = "Automatic — " + (airAlerts.autoPlace?.label ?? "locating…")
        let auto = NSMenuItem(title: autoTitle, action: #selector(pickAlertRegion(_:)), keyEquivalent: "")
        auto.target = self; auto.representedObject = nil
        auto.state = manual == nil ? .on : .off
        sub.addItem(auto)
        sub.addItem(.separator())
        for state in airAlerts.states {
            let item = NSMenuItem(title: state.name, action: nil, keyEquivalent: "")
            let districts = airAlerts.districtsByState[state.id] ?? []
            let sm = NSMenu()
            let whole = NSMenuItem(title: districts.isEmpty ? state.name : "Уся область", action: #selector(pickAlertRegion(_:)), keyEquivalent: "")
            whole.target = self; whole.representedObject = state.id
            whole.state = manual == state.id ? .on : .off
            sm.addItem(whole)
            if !districts.isEmpty { sm.addItem(.separator()) }
            for d in districts {
                let di = NSMenuItem(title: d.name, action: #selector(pickAlertRegion(_:)), keyEquivalent: "")
                di.target = self; di.representedObject = d.id
                di.state = manual == d.id ? .on : .off
                sm.addItem(di)
            }
            let chosenHere = manual.flatMap { airAlerts.region($0) }?.stateId == state.id
            item.state = chosenHere ? .mixed : .off
            item.submenu = sm
            sub.addItem(item)
        }
        root.submenu = sub
        return root
    }

    @objc private func pickAlertRegion(_ sender: NSMenuItem) {
        airAlerts.manualRegionId = sender.representedObject as? String
    }

    // MARK: Status-bar text

    private static let showLimitKey = "showLimitInBar", showTempKey = "showTempInBar"
    private var showLimit: Bool { UserDefaults.standard.object(forKey: Self.showLimitKey) as? Bool ?? true }
    private var showTemp: Bool { UserDefaults.standard.bool(forKey: Self.showTempKey) }

    private func updateStatusTitle() {
        guard let b = statusItem?.button else { return }
        var parts: [String] = []
        // the hot warning shows its reading even with the setting off
        if monitor.cpuHot || (showTemp && monitor.cpuTemp != nil) {
            parts.append(monitor.cpuTemp.map { "\(Int($0.rounded()))°" } ?? "CPU \(Int((monitor.cpuLoad * 100).rounded()))%")
        }
        if showLimit, let limits = monitor.claude {
            var text = "Session 0%"                                // no active session = nothing used yet
            if let w = limits.fiveHour, w.resetsAt > Date() {
                let mins = max(0, Int(w.resetsAt.timeIntervalSinceNow / 60))
                text = "Session \(Int(w.percent.rounded()))% · \(mins >= 60 ? "\(mins / 60)h" : "\(mins)m")"
            }
            parts.append(text)
        }
        let text = parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
        guard b.attributedTitle.string != text else { return }
        b.imagePosition = .imageLeft
        b.attributedTitle = NSAttributedString(
            string: text, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)])
    }

    @objc private func toggleShowLimit() {
        UserDefaults.standard.set(!showLimit, forKey: Self.showLimitKey)
        updateStatusTitle()
    }

    @objc private func toggleShowTemp() {
        UserDefaults.standard.set(!showTemp, forKey: Self.showTempKey)
        updateStatusTitle()
    }

    // MARK: Clicks

    @objc private func statusClicked() {
        let e = NSApp.currentEvent
        if e?.type == .rightMouseUp || e?.modifierFlags.contains(.control) == true { showMenu(); return }
        if visible { hide() }
        else if Date().timeIntervalSince(lastHide) > 0.25 { show() }   // the click that dismissed it must not reopen it
    }

    private func showMenu() {
        hide()
        let menu = NSMenu()
        #if DEBUG
        menu.addItem(debugMenu())
        menu.addItem(.separator())
        #else
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        #endif
        let limit = NSMenuItem(title: "Show Claude Limit in Menu Bar", action: #selector(toggleShowLimit), keyEquivalent: "")
        limit.target = self
        limit.state = showLimit ? .on : .off
        menu.addItem(limit)
        let temp = NSMenuItem(title: "Show CPU Temperature in Menu Bar", action: #selector(toggleShowTemp), keyEquivalent: "")
        temp.target = self
        temp.state = showTemp ? .on : .off
        menu.addItem(temp)
        menu.addItem(alertRegionMenu())
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Glass Monitor", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLogin() {
        let s = SMAppService.mainApp
        if s.status == .enabled { try? s.unregister() } else { try? s.register() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    #if DEBUG
    // MARK: Debug menu

    private func debugMenu() -> NSMenuItem {
        let root = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        func item(_ title: String, _ action: Selector, _ value: Any? = nil, on: Bool) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self; i.representedObject = value; i.state = on ? .on : .off
            return i
        }

        let sim = airAlerts.simulatedAlert
        sub.addItem(item("Air Alert: Real", #selector(debugAlert(_:)), on: sim == nil))
        sub.addItem(item("Air Alert: Yellow (drones)", #selector(debugAlert(_:)), "yellow", on: sim?.red == false))
        sub.addItem(item("Air Alert: Red (missiles)", #selector(debugAlert(_:)), "red", on: sim?.red == true))
        sub.addItem(.separator())

        let pct = monitor.simulatedSessionPercent
        sub.addItem(item("Claude Session: Real", #selector(debugClaude(_:)), on: pct == nil))
        for p in [30.0, 45, 85, 100] {
            sub.addItem(item("Claude Session: \(Int(p))%", #selector(debugClaude(_:)), p, on: pct == p))
        }
        sub.addItem(.separator())

        sub.addItem(item("Low Battery (10%)", #selector(debugBattery), on: monitor.simulateLowBattery))
        sub.addItem(item("Hot CPU (95%, 97 °C)", #selector(debugCPU), on: monitor.simulateHotCPU))
        sub.addItem(.separator())
        sub.addItem(item("Send Test Notification", #selector(debugNotify), on: false))

        root.submenu = sub
        return root
    }

    @objc private func debugAlert(_ sender: NSMenuItem) {
        let place = airAlerts.watchedLabel ?? "Київська область"
        switch sender.representedObject as? String {
        case "yellow":
            airAlerts.simulatedAlert = .init(regionName: place, red: false, since: Date().addingTimeInterval(-12 * 60),
                                             reason: "Дронова загроза (жовтий рівень)",
                                             threats: ["12:00 · ударні БпЛА — \(place): курсом на захід"])
        case "red":
            airAlerts.simulatedAlert = .init(regionName: place, red: true, since: Date().addingTimeInterval(-3 * 60),
                                             reason: "Ракетна небезпека (червоний рівень)",
                                             threats: ["12:00 · балістика — \(place): загроза застосування",
                                                       "11:58 · крилаті ракети — \(place): курсом на північ"])
        default:
            airAlerts.simulatedAlert = nil
        }
    }

    @objc private func debugClaude(_ sender: NSMenuItem) { monitor.simulatedSessionPercent = sender.representedObject as? Double }
    @objc private func debugBattery() { monitor.simulateLowBattery.toggle() }
    @objc private func debugCPU() { monitor.simulateHotCPU.toggle() }
    @objc private func debugNotify() { Notifier.shared.sendTest() }

    /// The Debug menu without clicking, for scripted checks: `./dev.sh cmd show`, `./dev.sh cmd hot-cpu`, …
    private func debugCommand(_ cmd: String) {
        switch cmd {
        case "show": if !visible { show() }
        case "hide": hide()
        case "hot-cpu": monitor.simulateHotCPU.toggle()
        case "low-battery": monitor.simulateLowBattery.toggle()
        case "alert-yellow", "alert-red", "alert-off":
            let item = NSMenuItem(); item.representedObject = cmd == "alert-off" ? nil : String(cmd.dropFirst(6))
            debugAlert(item)
        default:
            if cmd.hasPrefix("claude-") { monitor.simulatedSessionPercent = Double(cmd.dropFirst(7)) }
        }
    }
    #endif

    // MARK: Panel

    private func finalFrame(size: NSSize) -> NSRect {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        return NSRect(x: vf.maxX - size.width - edgeMargin, y: vf.maxY - size.height - topGap,
                      width: size.width, height: size.height)
    }

    private func show() {
        eyes.wake()
        host.view.layoutSubtreeIfNeeded()
        let size = host.view.fittingSize
        panel.setContentSize(size)
        let end = finalFrame(size: size)
        var start = end
        start.origin.x += size.width + 40          // begin off-screen to the right
        panel.setFrame(start, display: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        visible = true
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.32
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(end, display: true)
            panel.animator().alphaValue = 1
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
    }

    private func hide() {
        guard visible else { return }
        visible = false
        lastHide = Date()
        eyes.sleep()
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        var out = panel.frame
        out.origin.x += out.width + 40
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(out, display: true)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated { if self?.visible == false { self?.panel.orderOut(nil) } }
        })
    }
}
