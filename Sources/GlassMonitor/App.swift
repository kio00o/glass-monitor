import SwiftUI
import ServiceManagement

@main
struct GlassMonitorApp: App {
    @StateObject private var monitor = Monitor()
    @StateObject private var eyes = EyesModel()
    @StateObject private var menuIcon = MenuIconModel()

    init() {
        // Start at login (macOS shows this under System Settings → General → Login Items).
        if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
    }

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(monitor)
                .environmentObject(eyes)
        } label: {
            Image(nsImage: menuIcon.image)
        }
        .menuBarExtraStyle(.window)
    }
}
