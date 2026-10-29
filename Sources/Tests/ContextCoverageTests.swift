import XCTest
@testable import ScreenViewModel

enum EffectScreen: ScreenContext {
    struct State: DefaultScreenState, Equatable { var value = 0; var note = "" }
    enum Action { case start(String), stopViaEffect(String), stopAll, watch(String) }
}

final class EffectLogic: ViewModelContext<EffectScreen> {
    let tracker: Tracker
    init(tracker: Tracker) { self.tracker = tracker; super.init() }
    override func observable(action: EffectScreen.Action, state: inout EffectScreen.State, cancel: EffectCancel) -> ActionEffect<EffectScreen.Action> {
        let tracker = tracker
        switch action {
        case .start(let id):
            return .task(id: id) { _ in
                try? await Task.sleep(for: .seconds(10))
                if Task.isCancelled { tracker.cancelled += 1 }
            }
        case .stopViaEffect(let id):
            return .cancel(id: id)
        case .stopAll:
            cancel.all()
            return .none
        case .watch(let id):
            return .onDisappear(id: id) { tracker.log.append("cleanup \(id)") }
        }
    }
}

/// A context that overrides nothing: the default `observable` and `binding` hooks run.
final class PassiveLogic: ViewModelContext<EffectScreen> {}

final class ContextCoverageTests: XCTestCase {
    @MainActor
    func testDefaultHooksLeaveStateAsSentOrBound() {
        let model = ViewModel(context: PassiveLogic())
        model.send(.stopAll)                 // default observable -> .none, no change
        XCTAssertEqual(model.value, 0)
        model.value = 5                      // default binding hook -> keeps the write
        model.note = "n"
        XCTAssertEqual(model.value, 5)
        XCTAssertEqual(model.note, "n")
    }

    @MainActor
    func testCancelEffectStopsTheTaskWithThatId() async {
        let tracker = Tracker()
        let model = ViewModel(context: EffectLogic(tracker: tracker))
        model.send(.start("a"))
        model.send(.start("b"))
        XCTAssertEqual(model.runningTaskCount, 2)
        model.send(.stopViaEffect("a"))
        await waitUntil { tracker.cancelled == 1 }
        XCTAssertEqual(tracker.cancelled, 1)
        XCTAssertEqual(model.runningTaskCount, 1)
        model.send(.stopAll)
    }

    @MainActor
    func testCancelAllStopsTasksAndRunsCleanups() async {
        let tracker = Tracker()
        let model = ViewModel(context: EffectLogic(tracker: tracker))
        model.send(.start("a"))
        model.send(.start("b"))
        model.send(.watch("w"))
        model.send(.stopAll)
        await waitUntil { tracker.cancelled == 2 }
        XCTAssertEqual(tracker.cancelled, 2)
        XCTAssertEqual(tracker.log, ["cleanup w"])
        XCTAssertEqual(model.runningTaskCount, 0)
    }

    @MainActor
    func testDisappearCancelsAModelThatOutlivesItsView() async {
        let tracker = Tracker()
        let model = ViewModel(context: EffectLogic(tracker: tracker))
        model.send(.start("a"))
        model.send(.watch("w"))
        model.disappear()
        await waitUntil { tracker.cancelled == 1 }
        XCTAssertEqual(tracker.log, ["cleanup w"])
        XCTAssertEqual(model.runningTaskCount, 0)
    }

    @MainActor
    func testReleaseOffTheMainThreadCleansUpOnMain() async {
        let tracker = Tracker()
        final class Box: @unchecked Sendable { var model: ViewModel<EffectScreen>? }
        let box = Box()
        box.model = ViewModel(context: EffectLogic(tracker: tracker))
        box.model?.send(.watch("bg"))
        await Task.detached { box.model = nil }.value   // last reference dropped on a background thread
        await waitUntil { tracker.log == ["cleanup bg"] }
        XCTAssertEqual(tracker.log, ["cleanup bg"])
    }

    @MainActor
    func testContextStateReadBeforeAViewModelBuildsIt() {
        let logic = PassiveLogic()
        XCTAssertEqual(logic.state, EffectScreen.State())
    }
}
