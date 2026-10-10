import XCTest
@testable import ScreenViewModel

final class ScreenModelTests: XCTestCase {
    @MainActor
    func testNoneDoesNothing() {
        let model = Probe()
        model.send(.plain)
        XCTAssertEqual(model.seen, [.plain])
        XCTAssertTrue(model.log.isEmpty)
    }

    @MainActor
    func testRedirectRunsTheNextAction() {
        let model = Probe()
        model.effectsByAction[.addTwo] = .redirect(.addOneThenOne)
        model.effectsByAction[.addOneThenOne] = .redirect(.addOne)
        model.send(.addTwo)
        XCTAssertEqual(model.seen, [.addTwo, .addOneThenOne, .addOne])
    }

    @MainActor
    func testRedirectStopsAfterSixteenSteps() {
        let model = Probe()
        model.effectsByAction[.loop] = .redirect(.loop)
        model.send(.loop)
        XCTAssertEqual(model.seen.count, 17)
    }

    @MainActor
    func testAnonymousOnNextRunsBeforeTheFollowingAction() {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext { model.log.append("cleaned") }
        model.send(.arm)
        XCTAssertTrue(model.log.isEmpty)
        model.send(.plain)
        XCTAssertEqual(model.log, ["cleaned"])
        XCTAssertEqual(model.seen, [.arm, .plain])
    }

    @MainActor
    func testNamedOnNextStaysUntilThatIdIsCancelled() {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext(id: "clock") { model.log.append("cleaned") }
        model.send(.arm)
        model.send(.plain)
        XCTAssertTrue(model.log.isEmpty)
        model.cancel("clock")
        XCTAssertEqual(model.log, ["cleaned"])
    }

    @MainActor
    func testNoneDoesNotClearOnDisappear() {
        let model = Probe()
        model.effectsByAction[.appear] = .onDisappear { model.log.append("gone") }
        model.send(.appear)
        model.send(.plain)
        XCTAssertTrue(model.log.isEmpty)
        model.disappear()
        XCTAssertEqual(model.log, ["gone"])
    }

    @MainActor
    func testOnDisappearWithIdCanBeCancelledEarly() {
        let model = Probe()
        model.effectsByAction[.appear] = .onDisappear(id: "watch") { model.log.append("gone") }
        model.send(.appear)
        model.cancel("watch")
        XCTAssertEqual(model.log, ["gone"])
        model.disappear()
        XCTAssertEqual(model.log, ["gone"])
    }

    @MainActor
    func testTaskSendsItsResult() {
        let model = Probe()
        let done = expectation(description: "loaded")
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded(1) = action { done.fulfill() }
        }
        model.send(.load)
        wait(for: [done], timeout: 1)
    }

    @MainActor
    func testNewAnonymousTaskCancelsThePreviousOne() {
        let model = Probe()
        let firstStarted = expectation(description: "first")
        let secondFinished = expectation(description: "second")
        var releaseFirst: CheckedContinuation<Void, Never>?
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            if releaseFirst == nil {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    releaseFirst = continuation
                    firstStarted.fulfill()
                }
                guard !Task.isCancelled else { return }
                send(.loaded(1))
            } else {
                send(.loaded(2))
            }
        }
        model.send(.load)
        wait(for: [firstStarted], timeout: 1)
        model.onEvent = { action in
            if case .loaded(2) = action { secondFinished.fulfill() }
        }
        model.send(.load)
        releaseFirst?.resume()
        wait(for: [secondFinished], timeout: 1)
        XCTAssertFalse(model.seen.contains(.loaded(1)))
    }

    @MainActor
    func testTasksWithDifferentIdsBothRun() {
        let model = Probe()
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        model.effectsByAction[.load] = .task(.userInitiated, id: "a") { send in
            send(.loaded(1))
        }
        model.effectsByAction[.reload] = .task(.userInitiated, id: "b") { send in
            send(.loaded(2))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        model.send(.reload)
        wait(for: [done], timeout: 1)
    }

    @MainActor
    func testSameIdReplacesThePreviousEffect() {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext(id: "job") { model.log.append("first") }
        model.effectsByAction[.reload] = .onNext(id: "job") { model.log.append("second") }
        model.send(.arm)
        model.send(.reload)
        XCTAssertEqual(model.log, ["first"])
        model.cancel("job")
        XCTAssertEqual(model.log, ["first", "second"])
    }

    @MainActor
    func testCancelInsideObservableDropsTheEffect() {
        let model = Probe()
        let done = expectation(description: "not loaded")
        done.isInverted = true
        model.dropLoad = true
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        wait(for: [done], timeout: 0.3)
    }

    @MainActor
    func testSendWithIdStoresTheEffectUnderThatId() throws {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext { model.log.append("held") }
        var id: EffectID?
        model.send(.arm, id: &id)
        model.send(.plain)
        XCTAssertTrue(model.log.isEmpty)
        model.cancel(try XCTUnwrap(id))
        XCTAssertEqual(model.log, ["held"])
    }

    @MainActor
    func testSendWithIdReusesTheStoredId() throws {
        let model = StaticProbe()
        var id: EffectID?
        model.send(.arm, id: &id)
        let saved = try XCTUnwrap(id)
        model.send(.arm, id: &id)
        XCTAssertEqual(id, saved)
        XCTAssertEqual(model.log, ["held"])
        model.cancel(saved)
        XCTAssertEqual(model.log, ["held", "held"])
    }

    @MainActor
    func testDisappearCancelsAnAnonymousTask() {
        let model = Probe()
        let started = expectation(description: "started")
        let done = expectation(description: "not loaded")
        done.isInverted = true
        var release: CheckedContinuation<Void, Never>?
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                release = continuation
                started.fulfill()
            }
            guard !Task.isCancelled else { return }
            send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        wait(for: [started], timeout: 1)
        model.disappear()
        release?.resume()
        wait(for: [done], timeout: 0.3)
    }

    @MainActor
    func testReleasingTheModelRunsOnNext() {
        let box = LogBox()
        do {
            let model = Probe()
            model.effectsByAction[.arm] = .onNext { box.lines.append("dead") }
            model.send(.arm)
        }
        XCTAssertEqual(box.lines, ["dead"])
    }
}

private final class LogBox {
    var lines: [String] = []
}

@MainActor
private final class Probe: ScreenModel<ProbeAction> {
    var effectsByAction: [ProbeAction: Effect<ProbeAction>] = [:]
    var seen: [ProbeAction] = []
    var log: [String] = []
    var dropLoad = false
    var onEvent: ((ProbeAction) -> Void)?

    override func observable(action: ProbeAction, cancel: Cancel) -> Effect<ProbeAction> {
        seen.append(action)
        onEvent?(action)
        if dropLoad, action == .load {
            cancel()
        }
        return effectsByAction[action] ?? .none
    }
}

private struct StaticAction: Hashable {
    var name: String
    static let arm = StaticAction(name: "arm")
    static let plain = StaticAction(name: "plain")
}

@MainActor
private final class StaticProbe: ScreenModel<StaticAction> {
    var seen: [StaticAction] = []
    var log: [String] = []

    override func observable(action: StaticAction, cancel: Cancel) -> Effect<StaticAction> {
        seen.append(action)
        if action == .arm {
            return .onNext { self.log.append("held") }
        }
        return .none
    }
}

private enum ProbeAction: ScreenAction, Hashable {
    case plain
    case addOne
    case addOneThenOne
    case addTwo
    case arm
    case appear
    case load
    case reload
    case loop
    case loaded(Int)
}
