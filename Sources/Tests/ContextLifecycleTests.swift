import XCTest
@testable import ScreenViewModel

/// Parent, share, global and cache lifetimes for the context-based ViewModel.
final class ContextLifecycleTests: XCTestCase {
    // MARK: ParentState

    @MainActor
    func testParentScopePublishesTheViewModelToChildrenNotSiblings() {
        let parent = ViewModel(context: CounterLogic(tracker: Tracker()))
        let sibling = ViewModel(context: GreetingLogic(name: "sib"))
        let root = ScreenScope().setting(parent)
        let left = root.setting(sibling)
        let right = root.setting(ParentModel())
        XCTAssertTrue(left.model(ViewModel<CounterScreen>.self) === parent)
        XCTAssertTrue(right.model(ViewModel<CounterScreen>.self) === parent)
        XCTAssertNil(right.model(ViewModel<GreetingScreen>.self))
    }

    @MainActor
    func testChildSendsToParentViewModel() {
        let parent = ViewModel(context: CounterLogic(tracker: Tracker()))
        let scope = ScreenScope().setting(parent)
        scope.model(ViewModel<CounterScreen>.self)?.send(.increment)
        XCTAssertEqual(parent.count, 1)
    }

    // MARK: ShareState

    @MainActor
    func testShareStateReturnsOneInstancePerIdAndBuildsOnce() {
        let tracker = Tracker()
        let id = UUID().uuidString
        let first = shareState(id: id, ViewModel(context: CounterLogic(tracker: tracker)))
        let second = shareState(id: id, ViewModel(context: CounterLogic(tracker: tracker)))
        let other = shareState(id: id + "-other", ViewModel(context: CounterLogic(tracker: tracker)))
        XCTAssertTrue(first === second)
        XCTAssertFalse(first === other)
        first.send(.increment)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(other.count, 0)
        XCTAssertEqual(tracker.made, 2)
    }

    @MainActor
    func testSharedViewModelIsReleasedWithTheLastScreen() {
        let tracker = Tracker()
        let id = UUID().uuidString
        weak var weakShared: ViewModel<CounterScreen>?
        do {
            var screenA: ViewModel<CounterScreen>? = shareState(id: id, ViewModel(context: CounterLogic(tracker: tracker)))
            var screenB: ViewModel<CounterScreen>? = shareState(id: id, ViewModel(context: CounterLogic(tracker: tracker)))
            weakShared = screenA
            screenA = nil
            XCTAssertNotNil(weakShared)
            _ = screenB
            screenB = nil
        }
        XCTAssertNil(weakShared)
        let fresh = shareState(id: id, ViewModel(context: CounterLogic(tracker: tracker)))
        XCTAssertEqual(fresh.count, 0)
    }

    @MainActor
    func testShareViewModelWrapperJoinsTheGroupAndHoldsIt() {
        let tracker = Tracker()
        let id = UUID().uuidString
        let creator = ShareViewModel<CounterScreen>(wrappedValue: ViewModel(context: CounterLogic(tracker: tracker)), id: id)
        let joiner = ShareViewModel<CounterScreen>(id: id)
        let duplicate = ShareViewModel<CounterScreen>(wrappedValue: ViewModel(context: CounterLogic(tracker: tracker)), id: id)
        creator.wrappedValue.send(.increment)
        XCTAssertTrue(joiner.wrappedValue === creator.wrappedValue)
        XCTAssertTrue(duplicate.wrappedValue === creator.wrappedValue)
        XCTAssertEqual(joiner.wrappedValue.count, 1)
        XCTAssertEqual(tracker.made, 1)
    }

    // MARK: GlobalState

    @MainActor
    func testGlobalStateKeepsTheFirstInstanceAndSkipsLaterContexts() {
        let tracker = Tracker()
        let first = globalState(ViewModel(context: GlobalOnlyLogic(tracker: tracker)))
        first.send(.increment)
        let again = globalState(ViewModel(context: GlobalOnlyLogic(tracker: tracker)))
        XCTAssertTrue(first === again)
        XCTAssertEqual(GlobalViewModel<GlobalOnlyScreen>().wrappedValue.count, first.count)
        XCTAssertTrue(GlobalViewModel<GlobalOnlyScreen>().wrappedValue === first)
        XCTAssertLessThanOrEqual(tracker.made, 1)
    }

    @MainActor
    func testGlobalViewModelOutlivesItsScreens() {
        weak var weakGlobal: ViewModel<GlobalOnlyScreen>?
        do {
            let screen = globalState(ViewModel(context: GlobalOnlyLogic(tracker: Tracker())))
            weakGlobal = screen
        }
        XCTAssertNotNil(weakGlobal)
    }

    // MARK: Cache

    @MainActor
    func testTwoViewModelsShareOneCachedCall() async {
        let key = UUID().uuidString
        let service = FakeCounterService()
        service.value = 9
        service.delay = .milliseconds(50)
        let a = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        let b = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        a.send(.cached(key))
        b.send(.cached(key))
        await waitUntil { a.loaded == 9 && b.loaded == 9 }
        XCTAssertEqual(a.loaded, 9)
        XCTAssertEqual(b.loaded, 9)
        XCTAssertEqual(service.calls, 1)
    }

    // MARK: Old path untouched

    @MainActor
    func testScreenModelStillAdoptsTheOldContract() {
        let model: any ScreenModelProtocol = ParentModel()
        XCTAssertNotNil(model)
    }
}
