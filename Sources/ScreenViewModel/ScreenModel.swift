import Foundation
import Observation

/// One follow-up from an action. `send` performs the case that `observable` returns.
public enum Effect<Action> {
    case none
    /// Run this action after the current one. The previous anonymous `onNext` has already run.
    case redirect(Action)
    /// Without an id, runs when the next action arrives. With an id, runs when that id is cancelled or the view disappears.
    case onNext(id: AnyHashable? = nil, () -> Void)
    /// Without an id, runs once when the view disappears. A later `.none` does not clear it.
    /// With an id, `cancel(id)` runs it early.
    case onDisappear(id: AnyHashable? = nil, () -> Void)
    /// Async work, like SwiftUI `.task`. The same id replaces the previous task. Disappear cancels it too.
    case task(TaskPriority, id: AnyHashable? = nil, (_ send: (Action) -> Void) async -> Void)
}

/// Cancels effects returned from `observable`.
///
/// `cancel()` cancels the effect this call returned. `cancel(id)` cancels the effect stored under that id.
public struct Cancel {
    let ticket: EffectTicket
    let effects: ViewModelEffects

    public func callAsFunction() {
        effects.cancel(ticket)
    }

    public func callAsFunction(_ id: some Hashable) {
        effects.cancel(id: id)
    }
}

/// Screen view model. The view calls `send`. A screen overrides `observable(action:cancel:)`.
@MainActor
public protocol ViewModel: AnyObject {
    associatedtype Action
    func send(_ action: Action)
    func observable(action: Action, cancel: Cancel) -> Effect<Action>
}

@MainActor
@Observable
open class ScreenModel<Action>: ViewModel {
    fileprivate let effects = ViewModelEffects()

    public init() {}

    /// Runs every disappear cleanup and cancels every `.task` still in flight.
    public func disappear() {
        effects.cancelAll()
    }

    public func send(_ action: Action) {
        effects.fireAnonymousOnNext()
        let ticket = EffectTicket()
        let cancel = Cancel(ticket: ticket, effects: effects)
        let effect = observable(action: action, cancel: cancel)
        guard !ticket.cancelled else { return }
        apply(effect, ticket: ticket, depth: 0)
    }

    open func observable(action: Action, cancel: Cancel) -> Effect<Action> {
        _ = cancel
        return .none
    }

    private func apply(_ effect: Effect<Action>, ticket: EffectTicket, depth: Int) {
        switch effect {
        case .none:
            break
        case .redirect(let action):
            guard depth < 16 else { return }
            effects.fireAnonymousOnNext()
            let next = EffectTicket()
            let followed = observable(action: action, cancel: Cancel(ticket: next, effects: effects))
            guard !next.cancelled else { return }
            apply(followed, ticket: next, depth: depth + 1)
        case .onNext(let id, let cleanup):
            effects.store(ticket: ticket, id: id, onNext: cleanup)
        case .onDisappear(let id, let cleanup):
            effects.store(ticket: ticket, id: id, onDisappear: cleanup)
        case .task(let priority, let id, let work):
            effects.store(ticket: ticket, id: id, task: Task(priority: priority) { [weak self] in
                await work { action in
                    self?.send(action)
                }
            })
        }
    }
}

final class EffectTicket {
    var cancelled = false
}

final class EffectSlot {
    let ticket: EffectTicket
    var onNext: (() -> Void)?
    var onDisappear: (() -> Void)?
    var task: Task<Void, Never>?

    init(ticket: EffectTicket) {
        self.ticket = ticket
    }

    func finish() {
        task?.cancel()
        task = nil
        let next = onNext
        let gone = onDisappear
        onNext = nil
        onDisappear = nil
        next?()
        gone?()
    }
}

/// Holds anonymous effects and effects stored under an id.
final class ViewModelEffects {
    var anonymousOnNext: (() -> Void)?
    var anonymousOnNextTicket: EffectTicket?
    var anonymousOnDisappear: (() -> Void)?
    var anonymousOnDisappearTicket: EffectTicket?
    var anonymousTask: Task<Void, Never>?
    var anonymousTaskTicket: EffectTicket?
    var named: [AnyHashable: EffectSlot] = [:]

    func fireAnonymousOnNext() {
        let cleanup = anonymousOnNext
        anonymousOnNext = nil
        anonymousOnNextTicket = nil
        cleanup?()
    }

    func store(ticket: EffectTicket, id: AnyHashable?, onNext: @escaping () -> Void) {
        if let id {
            replaceNamed(id: id, ticket: ticket).onNext = onNext
        } else {
            fireAnonymousOnNext()
            anonymousOnNext = onNext
            anonymousOnNextTicket = ticket
        }
    }

    func store(ticket: EffectTicket, id: AnyHashable?, onDisappear: @escaping () -> Void) {
        if let id {
            replaceNamed(id: id, ticket: ticket).onDisappear = onDisappear
        } else {
            let previous = anonymousOnDisappear
            anonymousOnDisappear = onDisappear
            anonymousOnDisappearTicket = ticket
            _ = previous
        }
    }

    func store(ticket: EffectTicket, id: AnyHashable?, task: Task<Void, Never>) {
        if let id {
            let slot = replaceNamed(id: id, ticket: ticket)
            slot.task?.cancel()
            slot.task = task
        } else {
            anonymousTask?.cancel()
            anonymousTask = task
            anonymousTaskTicket = ticket
        }
    }

    func cancel(_ ticket: EffectTicket) {
        ticket.cancelled = true
        if anonymousOnNextTicket === ticket {
            fireAnonymousOnNext()
        }
        if anonymousOnDisappearTicket === ticket {
            let cleanup = anonymousOnDisappear
            anonymousOnDisappear = nil
            anonymousOnDisappearTicket = nil
            cleanup?()
        }
        if anonymousTaskTicket === ticket {
            anonymousTask?.cancel()
            anonymousTask = nil
            anonymousTaskTicket = nil
        }
        let keys = named.filter { $0.value.ticket === ticket }.map(\.key)
        for key in keys {
            named.removeValue(forKey: key)?.finish()
        }
    }

    func cancel(id: some Hashable) {
        named.removeValue(forKey: AnyHashable(id))?.finish()
    }

    func cancelAll() {
        fireAnonymousOnNext()
        let disappear = anonymousOnDisappear
        anonymousOnDisappear = nil
        anonymousOnDisappearTicket = nil
        anonymousTask?.cancel()
        anonymousTask = nil
        anonymousTaskTicket = nil
        let slots = named.values
        named.removeAll()
        for slot in slots { slot.finish() }
        disappear?()
    }

    private func replaceNamed(id: AnyHashable, ticket: EffectTicket) -> EffectSlot {
        named.removeValue(forKey: id)?.finish()
        let slot = EffectSlot(ticket: ticket)
        named[id] = slot
        return slot
    }

    deinit {
        anonymousTask?.cancel()
        anonymousOnNext?()
        anonymousOnDisappear?()
        for slot in named.values { slot.finish() }
    }
}
