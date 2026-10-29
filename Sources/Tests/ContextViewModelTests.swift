import Observation
import XCTest
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import ScreenViewModel

final class ContextViewModelTests: XCTestCase {
    // MARK: State access and send

    @MainActor
    func testDynamicMemberReadsState() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        XCTAssertEqual(model.count, 0)
        XCTAssertEqual(model.name, "")
        XCTAssertNil(model.loaded)
    }

    @MainActor
    func testSendRunsObservableAndUpdatesState() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.increment)
        model.send(.increment)
        model.send(.setName("Nailly"))
        XCTAssertEqual(model.count, 2)
        XCTAssertEqual(model.name, "Nailly")
    }

    @MainActor
    func testSendAndMergeEffectsRunInOrder() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.chain)
        XCTAssertEqual(model.count, 2)
        XCTAssertEqual(model.name, "chained")
    }

    @MainActor
    func testReplacingTheWholeStateIsVisible() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.send(.increment)
        let changed = Flag()
        withObservationTracking { _ = model.count } onChange: { changed.set() }
        model.send(.replaceState)
        XCTAssertTrue(changed.value)
        XCTAssertEqual(model.count, 100)
    }

    @MainActor
    func testObservationFiresThroughContextAndSkipsUnchangedEquatableState() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let countChanged = Flag()
        withObservationTracking { _ = model.count } onChange: { countChanged.set() }
        model.send(.stop("nothing-running"))   // state unchanged, Equatable -> no notification
        XCTAssertFalse(countChanged.value)
        model.send(.increment)
        XCTAssertTrue(countChanged.value)
    }

    @MainActor
    func testMakeStateOverrideUsesInjectedDependency() {
        let model = ViewModel(context: GreetingLogic(name: "Dung"))
        XCTAssertEqual(model.greeting, "Hi Dung")
        model.send(.shout)
        XCTAssertEqual(model.greeting, "HI DUNG")
    }

    @MainActor
    func testBindingReadsStateAndSendsAction() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let binding = model.binding(\.name, send: { .setName($0) })
        binding.wrappedValue = "typed"
        XCTAssertEqual(binding.wrappedValue, "typed")
        XCTAssertEqual(model.name, "typed")
    }

    // MARK: ScreenContext shape

    func testScreenContextNestsStateAndAction() {
        func shape<S: ScreenContext>(_: S.Type) -> (Any.Type, Any.Type) { (S.State.self, S.Action.self) }
        let (state, action) = shape(CounterScreen.self)
        XCTAssertTrue(state == CounterScreen.State.self)
        XCTAssertTrue(action == CounterScreen.Action.self)
    }

    // MARK: Once-only context autoclosure

    @MainActor
    func testContextIsNotBuiltUntilFirstUse() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        XCTAssertEqual(tracker.made, 0)
        _ = model.count
        XCTAssertEqual(tracker.made, 1)
    }

    @MainActor
    func testContextIsBuiltOncePerInstance() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        for _ in 0..<5 {
            model.send(.increment)
            _ = model.count
        }
        XCTAssertEqual(tracker.made, 1)
        XCTAssertEqual(model.count, 5)
    }

    /// What SwiftUI does with `@State private var model = ViewModel(context: ...)`: the initializer expression
    /// runs on every view init, but only the first instance is kept; later ones are dropped unread.
    @MainActor
    func testRebuiltInitializerExpressionsDoNotBuildMoreContexts() {
        let tracker = Tracker()
        var stored: ViewModel<CounterScreen>?
        for _ in 0..<3 {
            let candidate = ViewModel(context: CounterLogic(tracker: tracker))
            if stored == nil { stored = candidate }
        }
        stored?.send(.increment)
        XCTAssertEqual(tracker.made, 1)
        XCTAssertEqual(stored?.count, 1)
    }

    // MARK: ActionEffect tasks and cancel

    @MainActor
    func testTaskSendsResultBack() async {
        let service = FakeCounterService()
        service.value = 7
        let model = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        model.send(.load(id: nil))
        await waitUntil { model.loaded == 7 }
        XCTAssertEqual(model.loaded, 7)
        XCTAssertEqual(service.calls, 1)
        await waitUntil { model.runningTaskCount == 0 }
        XCTAssertEqual(model.runningTaskCount, 0)
    }

    @MainActor
    func testCancelByIdStopsTheTask() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(200)
        let model = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model.send(.load(id: "load"))
        model.send(.stop("load"))
        await waitUntil { tracker.cancelled == 1 }
        XCTAssertEqual(tracker.cancelled, 1)
        XCTAssertNil(model.loaded)
    }

    @MainActor
    func testSameIdReplacesThePreviousTask() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(100)
        let model = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model.send(.load(id: "load"))
        model.send(.load(id: "load"))
        await waitUntil { model.loaded != nil && tracker.cancelled == 1 }
        XCTAssertEqual(tracker.cancelled, 1)
        XCTAssertEqual(model.loaded, 42)
    }

    @MainActor
    func testReleasingTheModelCancelsTasksAndRunsCleanups() async {
        let tracker = Tracker()
        let service = FakeCounterService()
        service.delay = .milliseconds(200)
        var model: ViewModel<CounterScreen>? = ViewModel(context: CounterLogic(tracker: tracker, service: service))
        model?.send(.load(id: "load"))
        model?.send(.watch("w"))
        weak let weakModel = model
        model = nil
        XCTAssertNil(weakModel)
        XCTAssertEqual(tracker.log, ["cleanup w"])
        await waitUntil { tracker.cancelled == 1 }
        XCTAssertEqual(tracker.cancelled, 1)
    }

    @MainActor
    func testCancelIdRunsThatCleanupEarly() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        model.send(.watch("a"))
        model.send(.watch("b"))
        model.send(.stop("a"))
        XCTAssertEqual(tracker.log, ["cleanup a"])
    }

    // MARK: Struct state, observation through the context

    func testStateIsAPlainValueType() {
        XCTAssertEqual(Mirror(reflecting: CounterScreen.State()).displayStyle, .struct)
        XCTAssertEqual(Mirror(reflecting: GreetingScreen.State(greeting: "x")).displayStyle, .struct)
    }

    @MainActor
    func testNonEquatableStateNotifiesOnEverySend() {
        let model = ViewModel(context: GreetingLogic(name: "a"))
        let changed = Flag()
        withObservationTracking { _ = model.greeting } onChange: { changed.set() }
        model.send(.shout)
        XCTAssertTrue(changed.value)
        XCTAssertEqual(model.greeting, "HI A")
    }

    @MainActor
    func testContextIsTheObservableSourceAndStateReadOutsideIsACopy() {
        let logic = CounterLogic(tracker: Tracker())
        let model = ViewModel(context: logic)
        var snapshot = logic.state   // value copy; mutating it does not touch the model
        snapshot.count = 99
        XCTAssertEqual(model.count, 0)
        let changed = Flag()
        withObservationTracking { _ = logic.state } onChange: { changed.set() }
        model.send(.increment)
        XCTAssertTrue(changed.value)
        XCTAssertEqual(logic.state.count, 1)
    }

    #if canImport(SwiftUI)
    @MainActor
    func testBindableViewModelGivesBindings() {
        let bindable = Bindable(ViewModel(context: CounterLogic(tracker: Tracker())))
        let model = bindable.wrappedValue
        let name = model.binding(\.name, send: { .setName($0) })
        name.wrappedValue = "bound"
        XCTAssertEqual(bindable.wrappedValue.name, "bound")
    }
    #endif

    // MARK: Two-way binding

    @MainActor
    func testWritableDynamicMemberUpdatesStateAndNotifies() {
        let tracker = Tracker()
        let model = ViewModel(context: CounterLogic(tracker: tracker))
        let changed = Flag()
        withObservationTracking { _ = model.name } onChange: { changed.set() }
        model.name = "typed"
        XCTAssertTrue(changed.value)
        XCTAssertEqual(model.name, "typed")
        XCTAssertEqual(tracker.log, ["bound name"])
    }

    @MainActor
    func testBindingHookCanValidateTheWrite() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.count = -5
        XCTAssertEqual(model.count, 0)
        model.count = 7
        XCTAssertEqual(model.count, 7)
    }

    @MainActor
    func testSendAfterBindingSeesTheBoundValue() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        model.count = 10
        model.send(.increment)
        XCTAssertEqual(model.count, 11)
    }

    #if canImport(SwiftUI)
    @MainActor
    func testBindableProjectionIsTwoWay() {
        let model = ViewModel(context: CounterLogic(tracker: Tracker()))
        let bindable = Bindable(model)
        let name: Binding<String> = bindable.name          // what `$model.name` is in a view
        let changed = Flag()
        withObservationTracking { _ = model.name } onChange: { changed.set() }
        name.wrappedValue = "from TextField"                 // SwiftUI edit -> State
        XCTAssertEqual(model.name, "from TextField")
        XCTAssertTrue(changed.value)                         // -> view refresh
        model.send(.setName("from action"))                  // State change -> binding reads new value
        XCTAssertEqual(name.wrappedValue, "from action")
    }

    @MainActor
    func testStateWrapperProjectionIsTwoWay() {
        let state = State(initialValue: ViewModel(context: CounterLogic(tracker: Tracker())))
        let model = state.wrappedValue
        let bindable = Bindable(model)
        bindable.count.wrappedValue = 3
        XCTAssertEqual(model.count, 3)
    }
    #endif
}
