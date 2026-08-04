import TankfulCore
import SwiftUI

/// The caveat under a section's rows. Both services word it the same way, so the sections
/// differ only in which freshness they hand it.
struct FreshnessNote: View {
    let freshness: Freshness

    var body: some View {
        if let text = WindowFormat.freshnessNote(freshness) {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
