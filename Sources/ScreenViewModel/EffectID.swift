import Foundation

/// An id the caller can keep and later pass to `cancel(_:)`.
public struct EffectID: Hashable {
    public let raw: AnyHashable

    public init() {
        raw = AnyHashable(UUID())
    }

    public init(_ value: some Hashable) {
        raw = AnyHashable(value)
    }
}

/// An action plus the id its effect should be stored under.
public struct IdentifiedAction<Action> {
    public let action: Action
    public let id: EffectID
}

/// Marker for an action enum used with `ScreenModel`.
public protocol ScreenAction {}
