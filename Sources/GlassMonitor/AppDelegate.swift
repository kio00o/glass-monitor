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
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("dev.local.glassmonitor.test"),
                                                            object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Notifier.shared.sendTest() }
        }

        // Start at login once; afterwards the right-click menu controls it.
        if !UserDefaults.standard.bool(forKey: "loginItemOffered") {
            UserDefaults.standard.set(true, forKey: "loginItemOffered")
            try? SMAppService.mainApp.register()
        }

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

        host = NSHostingController(rootView: AnyView(PanelRoot().environmentObject(monitor).environmentObject(eyes)))
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
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
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
