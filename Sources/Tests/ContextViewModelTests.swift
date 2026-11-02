import Foundation
import Observation
import Testing
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import ScreenViewModel

@Suite(.serialized) final class ContextViewModelTests {
    // MARK: State access and send

    @MainActor
    @Test func testDynamicMemberReadsState() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        #expect(model.count == 0)
        #expect(model.name == "")
        #expect(model.loaded == nil)
    }

    @MainActor
    @Test func testSendRunsObservableAndUpdatesState() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.increment)
        model.send(.increment)
        model.send(.setName("Nailly"))
        #expect(model.count == 2)
        #expect(model.name == "Nailly")
    }

    @MainActor
    @Test func testSendAndMergeEffectsRunInOrder() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.chain)
        #expect(model.count == 2)
        #expect(model.name == "chained")
    }

    @MainActor
    @Test func testReplacingTheWholeStateIsVisible() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.increment)
        let changed = Flag()
        withObservationTracking { _ = model.count } onChange: { changed.set() }
        model.send(.replaceState)
        #expect(changed.value)
        #expect(model.count == 100)
    }

    @MainActor
    @Test func testObservationFiresThroughContextAndSkipsUnchangedEquatableState() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let countChanged = Flag()
        withObservationTracking { _ = model.count } onChange: { countChanged.set() }
        model.send(.stop("nothing-running"))   // state unchanged, Equatable -> no notification
        #expect(!(countChanged.value))
        model.send(.increment)
        #expect(countChanged.value)
    }

    @MainActor
    @Test func testMakeStateOverrideUsesInjectedDependency() async {
        let model = ViewModel(context: GreetingLogic(name: "Dung"))
        #expect(model.greeting == "Hi Dung")
        model.send(.shout)
        #expect(model.greeting == "HI DUNG")
    }

    @MainActor
    @Test func testBindingReadsStateAndSendsAction() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let binding = model.binding(\.name, send: { .setName($0) })
        binding.wrappedValue = "typed"
        await waitUntil { model.name == "typed" }
        #expect(binding.wrappedValue == "typed")
        #expect(model.name == "typed")
    }

    // MARK: ScreenContext shape

    @Test func testScreenContextNestsStateAndAction() {
        func shape<S: ScreenContext>(_: S.Type) -> (Any.Type, Any.Type) { (S.State.self, S.Action.self) }
        let (state, action) = shape(CounterScreen.self)
        #expect(state == CounterScreen.State.self)
        #expect(action == CounterScreen.Action.self)
    }

    // MARK: Once-only context autoclosure

    @MainActor
    @Test func testContextIsNotBuiltUntilFirstUse() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        #expect(tracker.made == 0)
        _ = model.count
        #expect(tracker.made == 1)
    }

    @MainActor
    @Test func testContextIsBuiltOncePerInstance() async {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        for _ in 0..<5 {
            model.send(.increment)
            _ = model.count
        }
        #expect(tracker.made == 1)
        #expect(model.count == 5)
    }

    /// What SwiftUI does with `@State private var model = ViewModel(context: ...)`: the initializer expression
    /// runs on every view init, but only the first instance is kept; later ones are dropped unread.
    @MainActor
    @Test func testRebuiltInitializerExpressionsDoNotBuildMoreContexts() async {
        let tracker = Tracker()
        var stored: ViewModel<CounterScreen, ViewState>?
        for _ in 0..<3 {
            let candidate = ViewModel(context: CounterLogic(tracker: tracker))
            if stored == nil { stored = candidate }
        }
        stored?.send(.increment)
        #expect(tracker.made == 1)
        #expect(stored?.count == 1)
    }

    // MARK: ActionEffect tasks and cancel

    @MainActor
    @Test func testSendReturnsWhileTaskIsStillRunning() async {
        let service = FakeCounterService()
        service.delay = .seconds(5)
        let model = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        model.send(.load(id: "slow"))
        #expect(model.runningTaskCount == 1)
        #expect(model.loaded == nil)
        model.send(.stop("slow"))
    }

    @MainActor
    @Test func testSendDoesNotReturnUntilRedirectUpdatesState() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.chain)
        #expect(model.count == 2)
        #expect(model.name == "chained")
    }

    @MainActor
    @Test func testTaskSendsResultBack() async {
        let service = FakeCounterService()
        service.value = 7
        let model = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        model.send(.load(id: nil))
        await waitUntil { model.loaded == 7 }
        #expect(model.loaded == 7)
        #expect(service.calls == 1)
        await waitUntil { model.runningTaskCount == 0 }
        #expect(model.runningTaskCount == 0)
    }

    @MainActor
    @Test func testCancelByIdStopsTheTask() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(200)
        let model = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model.send(.load(id: "load"))
        model.send(.stop("load"))
        await waitUntil { tracker.cancelled == 1 }
        #expect(tracker.cancelled == 1)
        #expect(model.loaded == nil)
    }

    @MainActor
    @Test func testSameIdReplacesThePreviousTask() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(100)
        let model = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model.send(.load(id: "load"))
        model.send(.load(id: "load"))
        await waitUntil { model.loaded != nil && tracker.cancelled == 1 }
        #expect(tracker.cancelled == 1)
        #expect(model.loaded == 42)
    }

    @MainActor
    @Test func testReleasingTheModelCancelsTasksAndRunsCleanups() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(200)
        var model: ViewModel<CounterScreen, ViewState>? = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model?.send(.load(id: "load"))
        model?.send(.watch("w"))
        weak let weakModel = model
        model = nil
        #expect(weakModel == nil)
        #expect(tracker.log == ["cleanup w"])
        await waitUntil { tracker.cancelled == 1 }
        #expect(tracker.cancelled == 1)
    }

    @MainActor
    @Test func testCancelIdRunsThatCleanupEarly() async {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        model.send(.watch("a"))
        model.send(.watch("b"))
        model.send(.stop("a"))
        #expect(tracker.log == ["cleanup a"])
    }

    // MARK: Struct state, observation through the context

    @Test func testStateIsAPlainValueType() {
        #expect(Mirror(reflecting: CounterScreen.State()).displayStyle == .struct)
        #expect(Mirror(reflecting: GreetingScreen.State(greeting: "x")).displayStyle == .struct)
    }

    @MainActor
    @Test func testNonEquatableStateNotifiesOnEverySend() async {
        let model = ViewModel(context: GreetingLogic(name: "a"))
        let changed = Flag()
        withObservationTracking { _ = model.greeting } onChange: { changed.set() }
        model.send(.shout)
        #expect(changed.value)
        #expect(model.greeting == "HI A")
    }

    @MainActor
    @Test func testContextIsTheObservableSourceAndStateReadOutsideIsACopy() async {
        let logic = CounterLogic(tracker: Tracker())
        let model = ViewModel(context: logic)
        var snapshot = logic.state   // value copy; mutating it does not touch the model
        snapshot.count = 99
        #expect(model.count == 0)
        let changed = Flag()
        withObservationTracking { _ = logic.state } onChange: { changed.set() }
        model.send(.increment)
        #expect(changed.value)
        #expect(logic.state.count == 1)
    }

    #if canImport(SwiftUI)
    @MainActor
    @Test func testBindableViewModelGivesBindings() async {
        let bindable = Bindable(ViewModel(context: CounterLogic(tracker: Tracker())))
        let model = bindable.wrappedValue
        let name = model.binding(\.name, send: { .setName($0) })
        name.wrappedValue = "bound"
        await waitUntil { bindable.wrappedValue.name == "bound" }
        #expect(bindable.wrappedValue.name == "bound")
    }
    #endif

    // MARK: Two-way binding

    @MainActor
    @Test func testWritableDynamicMemberUpdatesStateAndNotifies() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        let changed = Flag()
        withObservationTracking { _ = model.name } onChange: { changed.set() }
        model.name = "typed"
        #expect(changed.value)
        #expect(model.name == "typed")
        #expect(tracker.log == ["bound name"])
    }

    @MainActor
    @Test func testBindingHookCanValidateTheWrite() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.count = -5
        #expect(model.count == 0)
        model.count = 7
        #expect(model.count == 7)
    }

    @MainActor
    @Test func testSendAfterBindingSeesTheBoundValue() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.count = 10
        model.send(.increment)
        #expect(model.count == 11)
    }

    #if canImport(SwiftUI)
    @MainActor
    @Test func testBindableProjectionIsTwoWay() async {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let bindable = Bindable(model)
        let name: Binding<String> = bindable.name          // what `$model.name` is in a view
        let changed = Flag()
        withObservationTracking { _ = model.name } onChange: { changed.set() }
        name.wrappedValue = "from TextField"                 // SwiftUI edit -> State
        #expect(model.name == "from TextField")
        #expect(changed.value)                         // -> view refresh
        model.send(.setName("from action"))                  // State change -> binding reads new value
        #expect(name.wrappedValue == "from action")
    }

    @MainActor
    @Test func testStateWrapperProjectionIsTwoWay() {
        let state = State(initialValue: ViewModel(context: CounterLogic(tracker: Tracker())))
        let model = state.wrappedValue
        let bindable = Bindable(model)
        bindable.count.wrappedValue = 3
        #expect(model.count == 3)
    }
    #endif
}
