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

/// Opt in so a call site can write `model.send(.load.id(&id))`.
/// Passing an id means that effect can be cancelled with `cancel(id)`.
public protocol ScreenAction {}

extension ScreenAction {
    /// Writes `id` when it is nil and returns the same action.
    /// The returned type stays `Self`, so Swift can infer `.load` inside `send`.
    @MainActor
    public func id(_ id: inout EffectID?) -> Self {
        let resolved = id ?? EffectID()
        id = resolved
        EffectIDClaim.current = resolved
        return self
    }
}

@MainActor
enum EffectIDClaim {
    static var current: EffectID?

    static func take() -> EffectID? {
        let value = current
        current = nil
        return value
    }
}
