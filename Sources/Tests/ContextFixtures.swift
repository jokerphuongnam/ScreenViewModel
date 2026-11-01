import Foundation
import Observation
@testable import ScreenViewModel

enum CounterScreen: ScreenContext {
    struct State: DefaultScreenState, Equatable {
        var count = 0
        var name = ""
        var loaded: Int?
    }

    enum Action: Equatable {
        case increment
        case setName(String)
        case chain
        case load(id: String?)
        case loaded(Int)
        case stop(String)
        case watch(String)
        case replaceState
        case cached(String)
    }
}

/// Records how often the context autoclosure built a context, and what effects saw.
@MainActor
final class Tracker {
    var made = 0
    var log: [String] = []
    var cancelled = 0
}

/// A fake dependency injected through the context's init.
final class FakeCounterService: @unchecked Sendable {
    var value = 42
    var calls = 0
    var delay: Duration = .zero
    func fetch() async -> Int {
        calls += 1
        if delay > .zero { try? await Task.sleep(for: delay) }
        return value
    }
}

final class CounterLogic: ViewModelContext<CounterScreen> {
    let tracker: Tracker
    let service: FakeCounterService

    init(tracker: Tracker, service: FakeCounterService = FakeCounterService()) {
        self.tracker = tracker
        self.service = service
        tracker.made += 1
        super.init()
    }

    override func binding(
        changed keyPath: PartialKeyPath<CounterScreen.State>,
        state: inout CounterScreen.State,
        cancel: EffectCancel
    ) -> ActionEffect<CounterScreen.Action> {
        tracker.log.append("bound \(keyPath == \CounterScreen.State.name ? "name" : "other")")
        if keyPath == \CounterScreen.State.count, state.count < 0 { state.count = 0 }   // validation
        return .none
    }

    override func observable(
        action: CounterScreen.Action,
        state: inout CounterScreen.State,
        cancel: EffectCancel
    ) -> ActionEffect<CounterScreen.Action> {
        switch action {
        case .increment:
            state.count += 1
            return .none
        case .setName(let name):
            state.name = name
            return .none
        case .chain:
            state.count += 1
            return .merge([.send(.increment), .send(.setName("chained"))])
        case .load(let id):
            let service = service
            let tracker = tracker
            return .task(id: id) { send in
                let value = await service.fetch()
                if Task.isCancelled {
                    tracker.cancelled += 1
                    return
                }
                send(.loaded(value))
            }
        case .loaded(let value):
            state.loaded = value
            return .none
        case .stop(let id):
            cancel(id)
            return .none
        case .watch(let id):
            let tracker = tracker
            return .onDisappear(id: id) { tracker.log.append("cleanup \(id)") }
        case .replaceState:
            state = CounterScreen.State(count: 100)
            return .none
        case .cached(let key):
            let service = service
            return .task { send in
                let value = try? await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
                    await service.fetch()
                }
                send(.loaded(value ?? -1))
            }
        }
    }
}

/// A screen whose State has no init(); the context builds it from a dependency.
enum GreetingScreen: ScreenContext {
    struct State { var greeting: String }
    enum Action { case shout }
}

final class GreetingLogic: ViewModelContext<GreetingScreen> {
    let name: String
    init(name: String) { self.name = name; super.init() }
    override func makeState() -> GreetingScreen.State { .init(greeting: "Hi \(name)") }
    override func observable(
        action: GreetingScreen.Action,
        state: inout GreetingScreen.State,
        cancel: EffectCancel
    ) -> ActionEffect<GreetingScreen.Action> {
        state.greeting = state.greeting.uppercased()
        return .none
    }
}

/// Distinct screens per lifecycle test, because the global registry lives for the whole process.
enum GlobalOnlyScreen: ScreenContext {
    struct State: DefaultScreenState { var count = 0 }
    enum Action { case increment }
}

final class GlobalOnlyLogic: ViewModelContext<GlobalOnlyScreen> {
    let tracker: Tracker
    init(tracker: Tracker) { self.tracker = tracker; tracker.made += 1; super.init() }
    override func observable(
        action: GlobalOnlyScreen.Action,
        state: inout GlobalOnlyScreen.State,
        cancel: EffectCancel
    ) -> ActionEffect<GlobalOnlyScreen.Action> {
        state.count += 1
        return .none
    }
}

@MainActor
func waitUntil(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while !condition(), clock.now < end {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    var value: Bool { lock.withLock { raised } }
    func set() { lock.withLock { raised = true } }
}

#if canImport(SwiftUI)
import SwiftUI

/// Compile-time proof that `$model.field` works in real views, both for an owned `@State` model and a passed-in `@Bindable` one.
struct CounterOwnerView: View {
    @State private var model = ViewModel(context: CounterLogic(tracker: Tracker()))
    var body: some View {
        VStack {
            TextField("Name", text: $model.name)
            Stepper("\(model.count)", value: $model.count)
            CounterEditorView(model: model)
        }
    }
}

struct CounterEditorView: View {
    @Bindable var model: ViewModel<CounterScreen, ViewState>
    var body: some View {
        TextField("Name", text: $model.name)
    }
}
#endif
