import Foundation
import Observation

/// Describes one screen: exactly a `State` and an `Action`, nested in the context type.
///
/// ```swift
/// enum CounterScreen: ScreenContext {
///     struct State: DefaultScreenState, Equatable { var count = 0 }
///     enum Action { case increment }
/// }
/// ```
/// `State` is a plain value type. Observation lives on `ViewModelContext` (which stores the state) and `ViewModel`.
public protocol ScreenContext {
    associatedtype State
    associatedtype Action
}

/// A `State` that `ViewModelContext` can create with `init()` when `makeState()` is not overridden.
public protocol DefaultScreenState {
    init()
}

/// The logic of one screen. Subclass it, take dependencies (use cases, fakes in tests) in `init`,
/// and override `observable(action:state:cancel:)`. Only `ViewModel` calls it, so a screen has no public business methods.
///
/// The context is `@Observable` and owns the current `State` value. Every view read goes through
/// `state`, so a view re-renders when a send changes the state. If `State` is `Equatable`,
/// a send that leaves the state unchanged notifies nobody.
@MainActor
@Observable
open class ViewModelContext<Screen: ScreenContext> {
    /// Set once by `ViewModel` from `makeState()`, then replaced after each action.
    private var storage: Screen.State?

    public init() {}

    /// The current state. Built from `makeState()` on first read.
    public var state: Screen.State {
        if let storage { return storage }
        let first = makeState()
        storage = first
        return first
    }

    /// The first state. Override it when `State` has no `init()` or needs values from dependencies.
    open func makeState() -> Screen.State {
        guard let type = Screen.State.self as? DefaultScreenState.Type,
              let state = type.init() as? Screen.State else {
            fatalError("\(Screen.State.self) has no init(). Override makeState() in \(Self.self) or adopt DefaultScreenState.")
        }
        return state
    }

    /// Handles one action: change `state`, then return the follow-up work.
    open func observable(
        action: Screen.Action,
        state: inout Screen.State,
        cancel: EffectCancel
    ) -> ActionEffect<Screen.Action> {
        .none
    }

    /// Called after a SwiftUI binding (`$model.field`) wrote `keyPath`. `state` already holds the new value;
    /// change it further (validate, derive) or return follow-up work. Default: nothing.
    open func binding(
        changed keyPath: PartialKeyPath<Screen.State>,
        state: inout Screen.State,
        cancel: EffectCancel
    ) -> ActionEffect<Screen.Action> {
        .none
    }

    /// Applies a binding write and runs the `binding(changed:)` hook, storing the result once.
    func write<Value>(_ keyPath: WritableKeyPath<Screen.State, Value>, _ value: Value, cancel: EffectCancel) -> ActionEffect<Screen.Action> {
        let before = state
        var next = before
        next[keyPath: keyPath] = value
        let effect = binding(changed: keyPath, state: &next, cancel: cancel)
        if !stateEqual(before, next) { storage = next }
        return effect
    }

    func installInitialState() {
        if storage == nil { storage = makeState() }
    }

    /// Runs `observable` on a copy and stores it back only when it changed (Equatable) or always (non-Equatable).
    func reduce(_ action: Screen.Action, cancel: EffectCancel) -> ActionEffect<Screen.Action> {
        let before = state
        var next = before
        let effect = observable(action: action, state: &next, cancel: cancel)
        if !stateEqual(before, next) { storage = next }
        return effect
    }
}

private func stateEqual<S>(_ a: S, _ b: S) -> Bool {
    guard let a = a as? any Equatable else { return false }
    return a.isEqualTo(b)
}

private extension Equatable {
    func isEqualTo(_ other: Any) -> Bool { (other as? Self) == self }
}

/// Follow-up work returned from `ViewModelContext.observable`.
public enum ActionEffect<Action> {
    case none
    /// Sends this action right after the current one.
    case send(Action)
    /// Async work. The same id replaces (cancels) the previous task. The view model's release cancels it.
    case task(TaskPriority? = nil, id: AnyHashable? = nil, (_ send: @MainActor (Action) async -> Void) async -> Void)
    /// Cancels the task or cleanup stored under `id`.
    case cancel(id: AnyHashable)
    /// Runs when the view model is released, or early through `.cancel(id:)` when it has an id.
    case onDisappear(id: AnyHashable? = nil, () -> Void)
    /// Runs every effect in order.
    case merge([ActionEffect])
}

/// Cancel handle passed to `observable`. `cancel(id)` cancels the task or cleanup stored under `id`; `cancel.all()` cancels everything.
@MainActor
public struct EffectCancel {
    let runner: ActionEffectRunner

    public func callAsFunction(_ id: some Hashable) {
        runner.cancel(id: AnyHashable(id))
    }

    public func all() {
        runner.cancelAll()
    }
}

/// Runs `ActionEffect`s for one `ViewModel`. Main thread only.
final class ActionEffectRunner {
    private var tasks: [AnyHashable: Task<Void, Never>] = [:]
    private var anonymous: [UUID: Task<Void, Never>] = [:]
    private var cleanups: [AnyHashable: () -> Void] = [:]
    private var anonymousCleanups: [() -> Void] = []

    var runningTaskCount: Int { tasks.count + anonymous.count }

    @MainActor
    func store(task: Task<Void, Never>, id: AnyHashable?) -> UUID? {
        if let id {
            tasks[id]?.cancel()
            tasks[id] = task
            return nil
        }
        let key = UUID()
        anonymous[key] = task
        return key
    }

    @MainActor
    func finished(id: AnyHashable?, key: UUID?, task: Task<Void, Never>) {
        if let key { anonymous[key] = nil }
        if let id, tasks[id] == task { tasks[id] = nil }
    }

    func onDisappear(id: AnyHashable?, _ body: @escaping () -> Void) {
        if let id { cleanups[id] = body } else { anonymousCleanups.append(body) }
    }

    func cancel(id: AnyHashable) {
        tasks.removeValue(forKey: id)?.cancel()
        cleanups.removeValue(forKey: id)?()
    }

    func cancelAll() {
        let running = Array(tasks.values) + Array(anonymous.values)
        tasks.removeAll(); anonymous.removeAll()
        running.forEach { $0.cancel() }
        let pending = Array(cleanups.values) + anonymousCleanups
        cleanups.removeAll(); anonymousCleanups.removeAll()
        pending.forEach { $0() }
    }
}
