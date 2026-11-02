import Foundation
import Testing
@testable import ScreenViewModel

enum ParentOnlyScreen: ScreenContext {
    struct State: DefaultScreenState, Equatable { var count = 0 }
    enum Action { case increment }
}

final class ParentOnlyLogic: ViewModelContext<ParentOnlyScreen> {
    init(tracker: Tracker) {
        tracker.made += 1
        super.init()
    }

    override func observable(action: ParentOnlyScreen.Action, state: inout ParentOnlyScreen.State, cancel: EffectCancel) -> ActionEffect<ParentOnlyScreen.Action> {
        if case .increment = action { state.count += 1 }
        return .none
    }
}

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
    @Test func testChildSendsToParentViewModel() async {
        let parent = ViewModel(context: CounterLogic(tracker: Tracker()))
        let scope = ScreenScope().setting(parent)
        scope.model(ViewModel<CounterScreen, ViewState>.self)?.send(.increment)
        #expect(parent.count == 1)
    }

    @MainActor
    @Test func testParentScopeMakeReturnsTheLiveInstanceAndReleasesIt() async {
        let tracker = Tracker()
        weak var weakParent: ViewModel<ParentOnlyScreen, ParentScope>?
        do {
            let owner = ViewModel<ParentOnlyScreen, ParentScope>.make(context: ParentOnlyLogic(tracker: tracker))
            let child = ViewModel<ParentOnlyScreen, ParentScope>.make()
            #expect(owner === child)
            owner.send(.increment)
            #expect(child.count == 1)
            #expect(tracker.made == 1)
            weakParent = owner
        }
        #expect(weakParent == nil)
        let fresh = ViewModel<ParentOnlyScreen, ParentScope>.make(context: ParentOnlyLogic(tracker: Tracker()))
        #expect(fresh.count == 0)
    }

    // MARK: ShareState

    @MainActor
    @Test func testShareStateReturnsOneInstancePerIdAndBuildsOnce() async {
        let tracker = Tracker()
        let id = UUID().uuidString
        let first = ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker))
        let second = ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker))
        let other = ViewModel<CounterScreen, ShareScope>.make(id: id + "-other", CounterLogic(tracker: tracker))
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
            var screenA: ViewModel<CounterScreen, ShareScope>? = ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker))
            var screenB: ViewModel<CounterScreen, ShareScope>? = ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker))
            weakShared = screenA
            screenA = nil
            #expect(weakShared != nil)
            _ = screenB
            screenB = nil
        }
        #expect(weakShared == nil)
        let fresh = ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker))
        #expect(fresh.count == 0)
    }

    @MainActor
    @Test func testShareViewModelWrapperJoinsTheGroupAndHoldsIt() async {
        let tracker = Tracker()
        let id = UUID().uuidString
        let creator = ShareViewModel<CounterScreen>(wrappedValue: ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker)), id: id)
        let joiner = ShareViewModel<CounterScreen>(id: id)
        let duplicate = ShareViewModel<CounterScreen>(wrappedValue: ViewModel<CounterScreen, ShareScope>.make(id: id, CounterLogic(tracker: tracker)), id: id)
        creator.wrappedValue.send(.increment)
        #expect(joiner.wrappedValue === creator.wrappedValue)
        #expect(duplicate.wrappedValue === creator.wrappedValue)
        #expect(joiner.wrappedValue.count == 1)
        #expect(tracker.made == 1)
    }

    // MARK: GlobalState

    @MainActor
    @Test func testGlobalStateKeepsTheFirstInstanceAndSkipsLaterContexts() async {
        let tracker = Tracker()
        let id = UUID().uuidString
        let first = ViewModel<GlobalOnlyScreen, GlobalScope>.make(id: id, GlobalOnlyLogic(tracker: tracker))
        first.send(.increment)
        let again = ViewModel<GlobalOnlyScreen, GlobalScope>.make(id: id, GlobalOnlyLogic(tracker: tracker))
        let reader = ViewModel<GlobalOnlyScreen, GlobalScope>.make(id: id)
        #expect(first === again)
        #expect(reader === first)
        #expect(reader.count == first.count)
        #expect(tracker.made == 1)
    }

    @MainActor
    @Test func testGlobalViewModelOutlivesItsScreens() {
        weak var weakGlobal: ViewModel<GlobalOnlyScreen, GlobalScope>?
        let id = UUID().uuidString
        do {
            let screen = ViewModel<GlobalOnlyScreen, GlobalScope>.make(id: id, GlobalOnlyLogic(tracker: Tracker()))
            weakGlobal = screen
        }
        #expect(weakGlobal != nil)
        #expect(ViewModel<GlobalOnlyScreen, GlobalScope>.make(id: id) === weakGlobal)
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
