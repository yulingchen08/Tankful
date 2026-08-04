import AppKit

@main
enum AppMain {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // A SwiftPM executable gets no Info.plist at runtime, so the delegate is wired by hand
        // and held here for the process lifetime.
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
    }
}
