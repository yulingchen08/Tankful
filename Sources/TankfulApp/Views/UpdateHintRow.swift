import AppKit
import SwiftUI

/// One line that only exists while a newer release is out; clicking opens its page.
struct UpdateHintRow: View {
    @Environment(UpdateChecker.self) private var updateChecker

    var body: some View {
        if let tag = updateChecker.availableTag {
            Button {
                NSWorkspace.shared.open(updateChecker.releasePage)
            } label: {
                Label("Update available → \(tag)", systemImage: "arrow.down.circle.fill")
                    .font(.footnote.weight(.medium))
            }
            .buttonStyle(.borderless)
            .tint(.orange)
        }
    }
}
