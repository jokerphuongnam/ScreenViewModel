import XCTest
import SwiftUI
@testable import ScreenViewModel

// MARK: - Old ScreenModel paths

enum GapAction: Hashable { case watch, work, plain, keep, next }

/// Keeps each action's `Cancel` so a test can cancel the stored effect later.
@MainActor
final class GapModel: ScreenModel<GapAction> {
    var cancels: [GapAction: Cancel] = [:]
    var log: [String] = []
    override func observable(action: GapAction, cancel: Cancel) -> Effect<GapAction> {
        cancels[action] = cancel
        switch action {
        case .watch: return .onDisappear { [weak self] in self?.log.append("gone") }
        case .work: return .task(.medium) { [weak self] _ in
            try? await Task.sleep(for: .seconds(10))
            if Task.isCancelled { self?.log.append("work cancelled") }
        }
        case .keep: return .onNext(id: "keep") { [weak self] in self?.log.append("keep next") }
        case .next: return .onNext { [weak self] in self?.log.append("next ran") }
        case .plain: return .none
        }
    }
}

@MainActor final class SilentModel: ScreenModel<GapAction> {}

final class ScreenModelGapTests: XCTestCase {
    @MainActor
    func testCancelTicketForStoredAnonymousOnDisappearAndTask() async {
        let model = GapModel()
        model.send(.watch)
        model.send(.work)
        model.cancels[.watch]!()
        XCTAssertEqual(model.log, ["gone"])
        model.cancels[.work]!()
        await waitUntil { model.log.contains("work cancelled") }
        XCTAssertEqual(model.log, ["gone", "work cancelled"])
    }

    @MainActor
    func testCancelByIdThroughCancelHandle() {
        let model = GapModel()
        model.send(.keep)
        model.cancels[.keep]!("keep")
        XCTAssertEqual(model.log, ["keep next"])
    }

    @MainActor
    func testRekeyAfterSendMovesAnonymousOnDisappear() {
        let model = GapModel()
        var id: EffectID?
        model[.watch]().id(&id)
        XCTAssertNotNil(id)
        model.cancel(id!)
        XCTAssertEqual(model.log, ["gone"])
    }

    @MainActor
    func testRekeyAfterSendMovesAnonymousTask() async {
        let model = GapModel()
        var id: EffectID?
        model[.work]().id(&id)
        model.cancel(id!)
        await waitUntil { model.log == ["work cancelled"] }
        XCTAssertEqual(model.log, ["work cancelled"])
    }

    @MainActor
    func testRekeyMovesANamedEffectAndReplacesTheTarget() {
        let model = GapModel()
        var target: EffectID? = EffectID("target")
        model.send(.watch, id: &target)                 // something already stored at the target id
        let call = model[.keep]()                       // stored under "keep"
        call.id(&target)                                // move it to "target"; the old target finishes
        XCTAssertEqual(model.log, ["gone"])
        call.id(&target)                                // same key again: no-op
        model.cancel(target!)
        XCTAssertEqual(model.log, ["gone", "keep next"])
        let plain = model[.plain]()
        var none: EffectID?
        plain.id(&none)                                 // nothing stored for this ticket: no-op
        XCTAssertEqual(model.log, ["gone", "keep next"])
    }

    @MainActor
    func testSendIdentifiedActionAndEffectIDFromValue() {
        let model = GapModel()
        let id = EffectID("custom")
        XCTAssertEqual(id, EffectID("custom"))
        model.send(IdentifiedAction(action: .watch, id: id))
        model.cancel(id)
        XCTAssertEqual(model.log, ["gone"])
    }

    @MainActor
    func testDefaultObservableDoesNothing() {
        let model = SilentModel()
        model.send(.watch)
        model.disappear()
    }

    @MainActor
    func testCancelTicketRunsAnonymousOnNextAndNamedEffect() {
        let model = GapModel()
        model.send(.next)
        model.cancels[.next]!()
        XCTAssertEqual(model.log, ["next ran"])
        model.send(.keep)
        model.cancels[.keep]!()
        XCTAssertEqual(model.log, ["next ran", "keep next"])
    }

    @MainActor
    func testScreenModelReleasedOffMainCleansUpOnMain() async {
        final class Box: @unchecked Sendable { var model: Probe? }
        let ran = Flag()
        let box = Box()
        box.model = Probe()
        box.model?.effectsByAction[.arm] = .onDisappear { ran.set() }
        box.model?.send(.arm)
        await Task.detached { box.model = nil }.value   // last reference dropped on a background thread
        await waitUntil { ran.value }
        XCTAssertTrue(ran.value)
    }
}

// MARK: - Cache paths

final class CacheGapTests: XCTestCase {
    override func tearDown() { CacheClock.now = { Date() }; super.tearDown() }

    @MainActor
    func testSyncCacheStoresThenReturnsFresh() {
        let key = UUID().uuidString
        var calls = 0
        let first: String = cache(key: key, staleTime: .seconds(60)) { calls += 1; return "A" }
        let second: String = cache(key: key, staleTime: .seconds(60)) { calls += 1; return "B" }
        XCTAssertEqual([first, second], ["A", "A"])
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testSyncCacheRefetchesWhenStaleAndUpdatesTheEntry() {
        let key = UUID().uuidString
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        CacheClock.now = { start }
        let a: Int = cache(key: key, staleTime: .seconds(10)) { 1 }
        CacheClock.now = { start.addingTimeInterval(11) }
        let b: Int = cache(key: key, staleTime: .seconds(10)) { 2 }
        XCTAssertEqual([a, b], [1, 2])
    }

    @MainActor
    func testSyncCacheWithZeroGcTimeEvicts() {
        let key = UUID().uuidString
        let a: Int = cache(key: key, staleTime: .seconds(60), gcTime: .zero) { 1 }
        let b: Int = cache(key: key, staleTime: .seconds(60), gcTime: .zero) { 2 }
        XCTAssertEqual([a, b], [1, 2])
    }

    @MainActor
    func testSyncCacheAndCachedFromABackgroundThread() async {
        let key = UUID().uuidString
        let result = await Task.detached { () -> (Int, Int) in
            let a: Int = cache(key: key, staleTime: .seconds(60)) { 7 }
            let b: Int = cache(key: key, staleTime: .seconds(60)) { 8 }
            return (a, b)
        }.value
        XCTAssertEqual(result.0, 7)
        XCTAssertEqual(result.1, 7)

        final class Box: @unchecked Sendable { var cached: Cached<String>? }
        let box = Box()
        let ckey = UUID().uuidString
        await Task.detached { box.cached = cached(key: ckey, staleTime: .seconds(60)) { "bg" } }.value
        await waitUntil { box.cached?.data == "bg" }
        XCTAssertEqual(box.cached?.data, "bg")
        await Task.detached { box.cached = nil }.value   // observer released off main
        try? await Task.sleep(for: .milliseconds(50))
    }

    @MainActor
    func testCacheStateHoldsItsObserver() async {
        let key = UUID().uuidString
        let seed = cached(key: key, staleTime: .seconds(60)) { 5 }
        await waitUntil { seed.data == 5 }
        let state = CacheState<Int>(key: key)
        let first = state.wrappedValue
        XCTAssertTrue(state.wrappedValue === first)
        XCTAssertEqual(first.data, 5)
    }
}

// MARK: - SwiftUI host: ParentState and the environment scope

@MainActor @Observable final class ParentProbe { var title = "parent" }
@MainActor var parentSeen: [String] = []

struct ParentStateChild: View {
    @ParentState var parent: ParentProbe
    @ParentState var screen: ViewModel<CounterScreen>
    var body: some View {
        let _ = parentSeen.append("\(parent.title) count=\(screen.count)")
        Text(parent.title)
    }
}

struct ParentStateRoot: View {
    let parent: ParentProbe
    let screen: ViewModel<CounterScreen>
    var body: some View {
        ParentStateChild()
            .parentState(parent)
            .parentState(screen)
    }
}

final class SwiftUIHostTests: XCTestCase {
    @MainActor
    func testParentStateReadsModelsProvidedAboveInARealHostingView() {
        parentSeen = []
        let parent = ParentProbe()
        let screen = ViewModel(context: CounterLogic(tracker: Tracker()))
        autoreleasepool {
            let host = NSHostingView(rootView: ParentStateRoot(parent: parent, screen: screen))
            let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertEqual(parentSeen.last, "parent count=0")
            parent.title = "changed"
            screen.send(.increment)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            host.layoutSubtreeIfNeeded()
            XCTAssertEqual(parentSeen.last, "changed count=1")
            window.contentView = nil
        }
    }

    @MainActor
    func testScreenScopeEnvironmentRoundTrips() {
        var env = EnvironmentValues()
        let parent = ParentProbe()
        env.screenScope = env.screenScope.setting(parent)
        XCTAssertTrue(env.screenScope.model(ParentProbe.self) === parent)
    }
}
