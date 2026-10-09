import Foundation
import Observation

/// One follow-up from an action. `send` performs the case that `observable` returns.
public enum Effect<Action> {
    case none
    /// Run this action after the current one. The previous `onNext` has already run.
    case redirect(Action)
    /// Runs when the next action arrives, and when the view model is released.
    case onNext(() -> Void)
    /// Runs once when the view disappears. A later `.none` does not clear it.
    case onDisappear(() -> Void)
    /// Async work, like SwiftUI `.task`. A new `.task` cancels the previous one. Disappear cancels it too.
    case task(TaskPriority, (_ send: (Action) -> Void) async -> Void)
}

/// Screen view model. The view calls `send`. A screen overrides `observable(action:cancel:)`.
@MainActor
public protocol ViewModel: AnyObject {
    associatedtype Action
    func send(_ action: Action)
    /// `cancel` drops the effect this call returns: it cancels `.task`, and runs `.onNext` or `.onDisappear` once.
    func observable(action: Action, cancel: @escaping () -> Void) -> Effect<Action>
}

@MainActor
@Observable
open class ScreenModel<Action>: ViewModel {
    private let effects = ViewModelEffects()

    public init() {}

    /// Runs the disappear cleanup and cancels a `.task` still in flight.
    public func disappear() {
        if let ticket = effects.taskTicket { effects.cancel(ticket) }
        if let ticket = effects.onDisappearTicket { effects.cancel(ticket) }
        if let ticket = effects.onNextTicket { effects.cancel(ticket) }
    }

    public func send(_ action: Action) {
        effects.onNext?()
        effects.onNext = nil
        effects.onNextTicket = nil
        let ticket = EffectTicket()
        let effect = observable(action: action) { [weak self] in
            self?.effects.cancel(ticket)
        }
        guard !ticket.cancelled else { return }
        apply(effect, ticket: ticket, depth: 0)
    }

    open func observable(action: Action, cancel: @escaping () -> Void) -> Effect<Action> {
        _ = cancel
        return .none
    }

    private func apply(_ effect: Effect<Action>, ticket: EffectTicket, depth: Int) {
        switch effect {
        case .none:
            break
        case .redirect(let action):
            guard depth < 16 else { return }
            effects.onNext?()
            effects.onNext = nil
            effects.onNextTicket = nil
            let next = EffectTicket()
            let followed = observable(action: action) { [weak self] in
                self?.effects.cancel(next)
            }
            guard !next.cancelled else { return }
            apply(followed, ticket: next, depth: depth + 1)
        case .onNext(let cleanup):
            effects.onNext = cleanup
            effects.onNextTicket = ticket
        case .onDisappear(let cleanup):
            effects.onDisappear = cleanup
            effects.onDisappearTicket = ticket
        case .task(let priority, let work):
            effects.task?.cancel()
            effects.taskTicket = ticket
            effects.task = Task(priority: priority) { [weak self] in
                await work { action in
                    self?.send(action)
                }
            }
        }
    }
}

final class EffectTicket {
    var cancelled = false
}

/// Holds the latest `onNext`, the screen `onDisappear`, and the in-flight `.task`.
final class ViewModelEffects {
    var onNext: (() -> Void)?
    var onNextTicket: EffectTicket?
    var onDisappear: (() -> Void)?
    var onDisappearTicket: EffectTicket?
    var task: Task<Void, Never>?
    var taskTicket: EffectTicket?

    func cancel(_ ticket: EffectTicket) {
        ticket.cancelled = true
        if onNextTicket === ticket {
            let cleanup = onNext
            onNext = nil
            onNextTicket = nil
            cleanup?()
        }
        if onDisappearTicket === ticket {
            let cleanup = onDisappear
            onDisappear = nil
            onDisappearTicket = nil
            cleanup?()
        }
        if taskTicket === ticket {
            task?.cancel()
            task = nil
            taskTicket = nil
        }
    }

    deinit {
        task?.cancel()
        onNext?()
        onDisappear?()
    }
}
