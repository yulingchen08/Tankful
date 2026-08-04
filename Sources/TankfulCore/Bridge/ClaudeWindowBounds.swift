import Foundation

/// Bounds every list of Claude windows that arrives from outside this process.
///
/// Any process can hand the status-line command a payload, and the snapshot file can be
/// hand-written, while each window downstream becomes a panel row whose id has to be unique.
/// Both ingest paths therefore go through here rather than trusting the count they were given.
enum ClaudeWindowBounds {
    /// Every extra window becomes a panel row whose id is drawn verbatim, so both the count and
    /// the id length are capped.
    static let extraWindowLimit = 16
    static let idCharacterLimit = 64

    static func extra(id: String, percent: Double, resetsAt: Date?) -> ExtraWindow {
        ExtraWindow(id: String(id.prefix(idCharacterLimit)), usedPercent: percent, resetsAt: resetsAt)
    }

    /// Keeps the busiest windows, which are the ones worth showing; the id breaks ties so the
    /// pick does not depend on dictionary order.
    static func cappedExtras(_ extras: [ExtraWindow]) -> [ExtraWindow] {
        guard extras.count > extraWindowLimit else { return extras }
        let ranked = extras.sorted { lhs, rhs in
            lhs.usedPercent == rhs.usedPercent ? lhs.id < rhs.id : lhs.usedPercent > rhs.usedPercent
        }
        return Array(ranked.prefix(extraWindowLimit))
    }

    /// A kind names exactly one window, so a second one of the same kind is a duplicate row
    /// sharing a `ForEach` id rather than new information. The busiest reading wins, since that
    /// is the one worth warning about; equal readings keep the first seen.
    static func insert(_ window: RateWindow, into windows: inout [RateWindow]) {
        guard let index = windows.firstIndex(where: { $0.kind == window.kind }) else {
            windows.append(window)
            return
        }
        if window.usedPercent > windows[index].usedPercent { windows[index] = window }
    }
}
