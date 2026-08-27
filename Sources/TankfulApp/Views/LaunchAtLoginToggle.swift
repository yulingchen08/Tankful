import ServiceManagement
import SwiftUI

/// Registers the app as a login item through SMAppService, so the state shown is always
/// the system's own answer rather than a stored preference that can drift from it.
struct LaunchAtLoginToggle: View {
    @State private var isEnabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle("Launch at login", isOn: binding)
            .toggleStyle(.checkbox)
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isEnabled },
            set: { wantsEnabled in
                do {
                    if wantsEnabled {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    // The re-read below reports what actually happened.
                }
                isEnabled = SMAppService.mainApp.status == .enabled
            }
        )
    }
}
