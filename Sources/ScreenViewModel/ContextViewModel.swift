import Foundation
import Observation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// The screen's view model. The view only sees `State` fields (through dynamic member lookup) and `send(_:)`.
///
/// `context` is an autoclosure that runs at most once per instance, on the first read or send.
/// SwiftUI evaluates `@State private var model = ViewModel(context: CounterLogic())` again on each parent rebuild,
/// but it keeps the first instance and drops the new one unread, so `CounterLogic()` runs exactly once.
@MainActor
@Observable
@dynamicMemberLookup
public final class ViewModel<Screen: ScreenContext, Source: ViewModelSource> {
    @ObservationIgnored private var factory: (() -> ViewModelContext<Screen>)?
    @ObservationIgnored private var core: ViewModelContext<Screen>?
    @ObservationIgnored private let runner = ActionEffectRunner()

    init(factory: (() -> ViewModelContext<Screen>)?) {
        self.factory = factory
    }

    deinit {
        let runner = runner
        if Thread.isMainThread {
            runner.cancelAll()
        } else {
            nonisolated(unsafe) let queued = runner
            DispatchQueue.main.async { queued.cancelAll() }
        }
    }

    private func resolved() -> ViewModelContext<Screen> {
        if let core { return core }
        guard let factory else { fatalError("ViewModel context already released.") }
        self.factory = nil
        let context = factory()
        context.installInitialState()
        core = context
        return context
    }

    /// Reads a `State` field. Observation tracks `state` on the `@Observable` context, so the reading view
    /// re-renders when a send changes the state value.
    public subscript<Value>(dynamicMember keyPath: KeyPath<Screen.State, Value>) -> Value {
        resolved().state[keyPath: keyPath]
    }

    /// Two-way access for SwiftUI: `$model.name` (with `@Bindable` or `@State`) gives a `Binding` whose writes update
    /// `State` on the observable context and then run `ViewModelContext.binding(changed:state:cancel:)`.
    public subscript<Value>(dynamicMember keyPath: WritableKeyPath<Screen.State, Value>) -> Value {
        get { resolved().state[keyPath: keyPath] }
        set {
            let effect = resolved().write(keyPath, newValue, cancel: EffectCancel(runner: runner))
            apply(effect, depth: 0)
        }
    }

    public func send(_ action: Screen.Action) {
        deliver(action, depth: 0)
    }

    #if canImport(SwiftUI)
    /// A binding that reads a `State` field and sends `action` on writes, for `TextField`, `Toggle`, etc.
    public func binding<Value>(
        _ keyPath: KeyPath<Screen.State, Value>,
        send action: @escaping (Value) -> Screen.Action
    ) -> Binding<Value> {
        Binding(get: { self[dynamicMember: keyPath] }, set: { newValue in
            self.send(action(newValue))
        })
    }
    #endif

    /// Number of running tasks (tests).
    var runningTaskCount: Int { runner.runningTaskCount }

    /// Cancels tasks and runs cleanups now, for a model that outlives its view (global or shared).
    func disappear() { runner.cancelAll() }

    private func deliver(_ action: Screen.Action, depth: Int) {
        let effect = resolved().reduce(action, cancel: EffectCancel(runner: runner))
        apply(effect, depth: depth)
    }

    private func apply(_ effect: ActionEffect<Screen.Action>, depth: Int) {
        switch effect {
        case .none:
            return
        case .send(let next):
            guard depth < 16 else { return }
            deliver(next, depth: depth + 1)
        case .task(let priority, let id, let work):
            let send: @MainActor (Screen.Action) async -> Void = { [weak self] action in
                self?.send(action)
            }
            let task = Task(priority: priority) { @MainActor in
                await work(send)
            }
            let key = runner.store(task: task, id: id)
            let runner = runner
            Task { @MainActor in
                await task.value
                runner.finished(id: id, key: key, task: task)
            }
        case .cancel(let id):
            runner.cancel(id: id)
        case .onDisappear(let id, let body):
            runner.onDisappear(id: id, body)
        case .merge(let effects):
            for effect in effects {
                apply(effect, depth: depth)
            }
        }
    }
}
