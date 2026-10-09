import Foundation
import Observation

@MainActor
@Observable
@dynamicMemberLookup
open class ScreenModel<Action>: ViewModel {
    private let effects = ViewModelEffects()
    /// Effect stored by the latest `model.action` lookup, so `.id(&id)` can move it.
    private var rekeyTicket: EffectTicket?

    public init() {}

    /// Runs every disappear cleanup and cancels every `.task` still in flight.
    public func disappear() {
        effects.cancelAll()
    }

    public func send(_ action: Action) {
        deliver(action, forcedID: nil, capture: false)
    }

    /// Stores the effect from this action under `identified.id`.
    public func send(_ identified: IdentifiedAction<Action>) {
        deliver(identified.action, forcedID: identified.id, capture: false)
    }

    /// The id is created when `id` is nil, then the effect is stored under it.
    public func send(_ action: Action, id: inout EffectID?) {
        let resolved = id ?? EffectID()
        id = resolved
        deliver(action, forcedID: resolved, capture: false)
    }

    /// `model.load` sends `Action.load`. Chain `.id(&id)` to keep a cancel handle.
    /// `Action.load` must be a static member. A key path cannot refer to an enum case.
    public subscript(dynamicMember keyPath: KeyPath<Action.Type, Action>) -> Self {
        deliver(Action.self[keyPath: keyPath], forcedID: nil, capture: true)
        return self
    }

    /// Moves the effect from the preceding `model.action` lookup under `id`.
    @discardableResult
    public func id(_ id: inout EffectID?) -> Self {
        let resolved = id ?? EffectID()
        id = resolved
        if let ticket = rekeyTicket {
            effects.rekey(ticket, to: resolved.raw)
        }
        rekeyTicket = nil
        return self
    }

    /// Cancels the effect stored with this id.
    public func cancel(_ id: EffectID) {
        effects.cancel(id: id.raw)
    }

    public func cancel(_ id: some Hashable) {
        effects.cancel(id: id)
    }

    private func deliver(_ action: Action, forcedID: EffectID?, capture: Bool) {
        rekeyTicket = nil
        effects.fireAnonymousOnNext()
        let ticket = EffectTicket()
        let cancel = Cancel(ticket: ticket, effects: effects)
        let effect = observable(action: action, cancel: cancel)
        guard !ticket.cancelled else { return }
        apply(effect, ticket: ticket, forcedID: forcedID, capture: capture, depth: 0)
    }

    open func observable(action: Action, cancel: Cancel) -> Effect<Action> {
        _ = cancel
        return .none
    }

    private func apply(
        _ effect: Effect<Action>,
        ticket: EffectTicket,
        forcedID: EffectID?,
        capture: Bool,
        depth: Int
    ) {
        switch effect {
        case .none:
            break
        case .redirect(let action):
            guard depth < 16 else { return }
            effects.fireAnonymousOnNext()
            let next = EffectTicket()
            let followed = observable(action: action, cancel: Cancel(ticket: next, effects: effects))
            guard !next.cancelled else { return }
            apply(followed, ticket: next, forcedID: forcedID, capture: capture, depth: depth + 1)
        case .onNext(let id, let cleanup):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, onNext: cleanup)
            if capture { rekeyTicket = ticket }
        case .onDisappear(let id, let cleanup):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, onDisappear: cleanup)
            if capture { rekeyTicket = ticket }
        case .task(let priority, let id, let work):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, task: Task(priority: priority) { [weak self] in
                await work { action in
                    self?.send(action)
                }
            })
            if capture { rekeyTicket = ticket }
        }
    }
}
