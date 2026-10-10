import Foundation
import Observation

@MainActor
@Observable
open class ScreenModel<Action>: ViewModel {
    private let effects = ViewModelEffects()

    public init() {}

    deinit {
        let effects = effects
        if Thread.isMainThread {
            effects.cancelAll()
        } else {
            DispatchQueue.main.async {
                effects.cancelAll()
            }
        }
    }

    /// Cancels every `.task` and runs every stored cleanup.
    /// A model owned by the view already does this when the view releases it.
    /// Call this only when the model stays alive after the view is gone.
    public func disappear() {
        effects.cancelAll()
    }

    public func send(_ action: Action) {
        deliver(action, forcedID: nil)
    }

    /// Stores the effect from this action under `identified.id`.
    public func send(_ identified: IdentifiedAction<Action>) {
        deliver(identified.action, forcedID: identified.id)
    }

    /// The id is created when `id` is nil, then the effect is stored under it.
    public func send(_ action: Action, id: inout EffectID?) {
        let resolved = id ?? EffectID()
        id = resolved
        deliver(action, forcedID: resolved)
    }

    /// Cancels the effect stored with this id.
    public func cancel(_ id: EffectID) {
        effects.cancel(id: id.raw)
    }

    public func cancel(_ id: some Hashable) {
        effects.cancel(id: id)
    }

    private func deliver(_ action: Action, forcedID: EffectID?) {
        effects.fireAnonymousOnNext()
        let ticket = EffectTicket()
        let cancel = Cancel(ticket: ticket, effects: effects)
        let effect = observable(action: action, cancel: cancel)
        guard !ticket.cancelled else { return }
        apply(effect, ticket: ticket, forcedID: forcedID, depth: 0)
    }

    open func observable(action: Action, cancel: Cancel) -> Effect<Action> {
        _ = cancel
        return .none
    }

    private func apply(
        _ effect: Effect<Action>,
        ticket: EffectTicket,
        forcedID: EffectID?,
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
            apply(followed, ticket: next, forcedID: forcedID, depth: depth + 1)
        case .onNext(let id, let cleanup):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, onNext: cleanup)
        case .onDisappear(let id, let cleanup):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, onDisappear: cleanup)
        case .task(let priority, let id, let work):
            effects.store(ticket: ticket, id: forcedID?.raw ?? id, task: Task(priority: priority) { [weak self] in
                await work { action in
                    self?.send(action)
                }
            })
        }
    }
}
