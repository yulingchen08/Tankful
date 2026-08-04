import Foundation

/// How much to trust the numbers currently on screen.
public enum Freshness: Sendable, Equatable {
    case fresh
    case stale(age: TimeInterval)
    case unavailable(reason: String)
}
