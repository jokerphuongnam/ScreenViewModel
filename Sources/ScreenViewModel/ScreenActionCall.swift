import Foundation

/// Result of `model[.load]`. Call it to send, or pass `.id` to keep a cancel handle.
@MainActor
public struct ScreenActionCall<Action> {
    private let model: ScreenModel<Action>
    private let action: Action
    private let sent: Sent

    private final class Sent {
        var ticket: EffectTicket?
    }

    init(model: ScreenModel<Action>, action: Action) {
        self.model = model
        self.action = action
        self.sent = Sent()
    }

    /// `model[.load]()` sends the action. The result can be ignored.
    @discardableResult
    public func callAsFunction() -> Self {
        if sent.ticket == nil {
            sent.ticket = model.deliver(action, forcedID: nil)
        }
        return self
    }

    /// `model[.load].id(&id)` and `model[.load]().id(&id)` store that effect under `id`.
    @discardableResult
    public func id(_ id: inout EffectID?) -> ScreenModel<Action> {
        let resolved = id ?? EffectID()
        id = resolved
        if let ticket = sent.ticket {
            model.rekey(ticket, to: resolved)
        } else {
            sent.ticket = model.deliver(action, forcedID: resolved)
        }
        return model
    }
}
