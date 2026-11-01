import Foundation
import Testing
@testable import ScreenViewModel

/// Parent, share, global and cache lifetimes for the context-based ViewModel.
@Suite(.serialized) final class ContextLifecycleTests {
    // MARK: ParentState

    @MainActor
    @Test func testParentScopePublishesTheViewModelToChildrenNotSiblings() {
        let parent = ViewModel(context: CounterLogic(tracker: Tracker()))
        let sibling = ViewModel(context: GreetingLogic(name: "sib"))
        let root = ScreenScope().setting(parent)
        let left = root.setting(sibling)
        let right = root.setting(ParentModel())
        #expect(left.model(ViewModel<CounterScreen, ViewState>.self) === parent)
        #expect(right.model(ViewModel<CounterScreen, ViewState>.self) === parent)
        #expect(right.model(ViewModel<GreetingScreen, ViewState>.self) == nil)
    }

    @MainActor
    @Test func testChildSendsToParentViewModel() {
        let parent = ViewModel(context: CounterLogic(tracker: Tracker()))
        let scope = ScreenScope().setting(parent)
        scope.model(ViewModel<CounterScreen, ViewState>.self)?.send(.increment)
        #expect(parent.count == 1)
    }

    // MARK: ShareState

    @MainActor
    @Test func testShareStateReturnsOneInstancePerIdAndBuildsOnce() {
        let tracker = Tracker()
        let id = UUID().uuidString
        let first = ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker))
        let second = ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker))
        let other = ViewModel<CounterScreen, ShareScope>.make(id: id + "-other", context: CounterLogic(tracker: tracker))
        #expect(first === second)
        #expect(!(first === other))
        first.send(.increment)
        #expect(second.count == 1)
        #expect(other.count == 0)
        #expect(tracker.made == 2)
    }

    @MainActor
    @Test func testSharedViewModelIsReleasedWithTheLastScreen() {
        let tracker = Tracker()
        let id = UUID().uuidString
        weak var weakShared: ViewModel<CounterScreen, ShareScope>?
        do {
            var screenA: ViewModel<CounterScreen, ShareScope>? = ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker))
            var screenB: ViewModel<CounterScreen, ShareScope>? = ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker))
            weakShared = screenA
            screenA = nil
            #expect(weakShared != nil)
            _ = screenB
            screenB = nil
        }
        #expect(weakShared == nil)
        let fresh = ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker))
        #expect(fresh.count == 0)
    }

    @MainActor
    @Test func testShareViewModelWrapperJoinsTheGroupAndHoldsIt() {
        let tracker = Tracker()
        let id = UUID().uuidString
        let creator = ShareViewModel<CounterScreen>(wrappedValue: ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker)), id: id)
        let joiner = ShareViewModel<CounterScreen>(id: id)
        let duplicate = ShareViewModel<CounterScreen>(wrappedValue: ViewModel<CounterScreen, ShareScope>.make(id: id, context: CounterLogic(tracker: tracker)), id: id)
        creator.wrappedValue.send(.increment)
        #expect(joiner.wrappedValue === creator.wrappedValue)
        #expect(duplicate.wrappedValue === creator.wrappedValue)
        #expect(joiner.wrappedValue.count == 1)
        #expect(tracker.made == 1)
    }

    // MARK: GlobalState

    @MainActor
    @Test func testGlobalStateKeepsTheFirstInstanceAndSkipsLaterContexts() {
        let tracker = Tracker()
        let first = ViewModel<GlobalOnlyScreen, GlobalScope>.make(context: GlobalOnlyLogic(tracker: tracker))
        first.send(.increment)
        let again = ViewModel<GlobalOnlyScreen, GlobalScope>.make(context: GlobalOnlyLogic(tracker: tracker))
        #expect(first === again)
        #expect(GlobalViewModel<GlobalOnlyScreen>().wrappedValue.count == first.count)
        #expect(GlobalViewModel<GlobalOnlyScreen>().wrappedValue === first)
        #expect(tracker.made <= 1)
    }

    @MainActor
    @Test func testGlobalViewModelOutlivesItsScreens() {
        weak var weakGlobal: ViewModel<GlobalOnlyScreen, GlobalScope>?
        do {
            let screen = ViewModel<GlobalOnlyScreen, GlobalScope>.make(context: GlobalOnlyLogic(tracker: Tracker()))
            weakGlobal = screen
        }
        #expect(weakGlobal != nil)
    }

    // MARK: Cache

    @MainActor
    @Test func testTwoViewModelsShareOneCachedCall() async {
        let key = UUID().uuidString
        let service = FakeCounterService()
        service.value = 9
        service.delay = .milliseconds(50)
        let a = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        let b = ViewModel(context: CounterLogic(tracker: Tracker(), service: service))
        a.send(.cached(key))
        b.send(.cached(key))
        await waitUntil { a.loaded == 9 && b.loaded == 9 }
        #expect(a.loaded == 9)
        #expect(b.loaded == 9)
        #expect(service.calls == 1)
    }

    // MARK: Old path untouched

    @MainActor
    @Test func testScreenModelStillAdoptsTheOldContract() {
        let model: any ScreenModelProtocol = ParentModel()
        #expect(model != nil)
    }
}
