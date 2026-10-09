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

/// Screen view model. The view calls `send`. A screen overrides `observable(action:)`.
@MainActor
public protocol ViewModel: AnyObject {
    associatedtype Action
    func send(_ action: Action)
    func observable(action: Action) -> Effect<Action>
}

@MainActor
@Observable
open class ScreenModel<Action>: ViewModel {
    private let effects = ViewModelEffects()

    public init() {}

    /// Runs the disappear cleanup and cancels a `.task` still in flight.
    public func disappear() {
        effects.task?.cancel()
        effects.task = nil
        let cleanup = effects.onDisappear
        effects.onDisappear = nil
        cleanup?()
    }

    public func send(_ action: Action) {
        effects.onNext?()
        effects.onNext = nil
        apply(observable(action: action), depth: 0)
    }

    open func observable(action: Action) -> Effect<Action> { .none }

    private func apply(_ effect: Effect<Action>, depth: Int) {
        switch effect {
        case .none:
            break
        case .redirect(let action):
            guard depth < 16 else { return }
            effects.onNext?()
            effects.onNext = nil
            apply(observable(action: action), depth: depth + 1)
        case .onNext(let cleanup):
            effects.onNext = cleanup
        case .onDisappear(let cleanup):
            effects.onDisappear = cleanup
        case .task(let priority, let work):
            effects.task?.cancel()
            effects.task = Task(priority: priority) { [weak self] in
                await work { action in
                    self?.send(action)
                }
            }
        }
    }
}

/// Holds the latest `onNext`, the screen `onDisappear`, and the in-flight `.task`.
final class ViewModelEffects {
    var onNext: (() -> Void)?
    var onDisappear: (() -> Void)?
    var task: Task<Void, Never>?

    deinit {
        task?.cancel()
        onNext?()
        onDisappear?()
    }
}
