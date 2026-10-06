import SwiftUI

@main
struct GlassMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // The UI lives in a custom panel owned by AppDelegate; SwiftUI only needs a scene.
    var body: some Scene { Settings { EmptyView() } }
}
