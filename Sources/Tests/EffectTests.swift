import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class EffectTests {
    @MainActor
    @Test func testNoneDoesNothing() async {
        let model = Probe()
        model.send(.plain)
        #expect(model.seen == [.plain])
        #expect(model.log.isEmpty)
    }

    @MainActor
    @Test func testRedirectRunsTheNextAction() async {
        let model = Probe()
        model.effectsByAction[.addTwo] = .redirect(.addOneThenOne)
        model.effectsByAction[.addOneThenOne] = .redirect(.addOne)
        model.send(.addTwo)
        #expect(model.seen == [.addTwo, .addOneThenOne, .addOne])
    }

    @MainActor
    @Test func testSendDoesNotReturnUntilRedirectUpdatesState() async {
        let model = Probe()
        model.effectsByAction[.addTwo] = .redirect(.addOne)
        model.send(.addTwo)
        #expect(model.seen == [.addTwo, .addOne])
    }

    @MainActor
    @Test func testRedirectStopsAfterSixteenSteps() async {
        let model = Probe()
        model.effectsByAction[.loop] = .redirect(.loop)
        model.send(.loop)
        #expect(model.seen.count == 17)
    }

    @MainActor
    @Test func testAnonymousOnNextRunsBeforeTheFollowingAction() async {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext { model.log.append("cleaned") }
        model.send(.arm)
        #expect(model.log.isEmpty)
        model.send(.plain)
        #expect(model.log == ["cleaned"])
        #expect(model.seen == [.arm, .plain])
    }

    @MainActor
    @Test func testEffectIdIsGeneratedAndReused() async {
        let model = Probe()
        var first: EffectID?
        var second: EffectID?
        model.effectsByAction[.arm] = .onNext { model.log.append("first") }.id(&first)
        model.effectsByAction[.reload] = .onNext { model.log.append("second") }.id(&second)
        let firstID = first
        model.effectsByAction[.arm] = .onNext { model.log.append("again") }.id(&first)

        #expect(first != nil)
        #expect(second != nil)
        #expect(first == firstID)
        #expect(first != second)

        model.send(.arm)
        model.send(.plain)
        #expect(model.log.isEmpty)
        model.cancel(first!)
        #expect(model.log == ["again"])
        model.cancel(second!)
        #expect(model.log == ["again"])
    }

    @MainActor
    @Test func testGeneratedIdWorksOnEveryEffect() async {
        var taskID: EffectID?
        var disappearID: EffectID?
        var redirectID: EffectID?
        var noneID: EffectID?
        _ = Effect<ProbeAction>.task(.userInitiated) { _ in }.id(&taskID)
        _ = Effect<ProbeAction>.onDisappear {}.id(&disappearID)
        _ = Effect<ProbeAction>.redirect(.plain).id(&redirectID)
        _ = Effect<ProbeAction>.none.id(&noneID)

        #expect(noneID == nil)
        let ids = [taskID, disappearID, redirectID]
        #expect(ids.compactMap { $0 }.count == 3)
        #expect(Set(ids.compactMap { $0 }).count == 3)

        let model = Probe()
        model.effectsByAction[.addTwo] = .redirect(.addOne).id(&redirectID)
        model.effectsByAction[.addOne] = .onNext { model.log.append("cleaned") }
        model.send(.addTwo)
        model.send(.plain)
        #expect(model.log.isEmpty)
        model.cancel(redirectID!)
        #expect(model.log == ["cleaned"])
    }

    @MainActor
    @Test func testNamedOnNextStaysUntilThatIdIsCancelled() async {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext(id: "clock") { model.log.append("cleaned") }
        model.send(.arm)
        model.send(.plain)
        #expect(model.log.isEmpty)
        model.cancel("clock")
        #expect(model.log == ["cleaned"])
    }

    @MainActor
    @Test func testNoneDoesNotClearOnDisappear() async {
        let model = Probe()
        model.effectsByAction[.appear] = .onDisappear { model.log.append("gone") }
        model.send(.appear)
        model.send(.plain)
        #expect(model.log.isEmpty)
        model.disappear()
        #expect(model.log == ["gone"])
    }

    @MainActor
    @Test func testOnDisappearWithIdCanBeCancelledEarly() async {
        let model = Probe()
        model.effectsByAction[.appear] = .onDisappear(id: "watch") { model.log.append("gone") }
        model.send(.appear)
        model.cancel("watch")
        #expect(model.log == ["gone"])
        model.disappear()
        #expect(model.log == ["gone"])
    }

    @MainActor
    @Test func testTaskSendsItsResult() async {
        let model = Probe()
        let done = expectation(description: "loaded")
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            await send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded(1) = action { done.fulfill() }
        }
        model.send(.load)
        await wait(for: [done], timeout: 1)
    }

    @MainActor
    @Test func testNewAnonymousTaskCancelsThePreviousOne() async {
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
                await send(.loaded(1))
            } else {
                await send(.loaded(2))
            }
        }
        model.send(.load)
        await wait(for: [firstStarted], timeout: 1)
        model.onEvent = { action in
            if case .loaded(2) = action { secondFinished.fulfill() }
        }
        model.send(.load)
        releaseFirst?.resume()
        await wait(for: [secondFinished], timeout: 1)
        #expect(!(model.seen.contains(.loaded(1))))
    }

    @MainActor
    @Test func testTasksWithDifferentIdsBothRun() async {
        let model = Probe()
        let done = expectation(description: "both")
        done.expectedFulfillmentCount = 2
        model.effectsByAction[.load] = .task(.userInitiated, id: "a") { send in
            await send(.loaded(1))
        }
        model.effectsByAction[.reload] = .task(.userInitiated, id: "b") { send in
            await send(.loaded(2))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        model.send(.reload)
        await wait(for: [done], timeout: 1)
    }

    @MainActor
    @Test func testSameIdReplacesThePreviousEffect() async {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext(id: "job") { model.log.append("first") }
        model.effectsByAction[.reload] = .onNext(id: "job") { model.log.append("second") }
        model.send(.arm)
        model.send(.reload)
        #expect(model.log == ["first"])
        model.cancel("job")
        #expect(model.log == ["first", "second"])
    }

    @MainActor
    @Test func testCancelInsideObservableDropsTheEffect() async {
        let model = Probe()
        let done = expectation(description: "not loaded")
        done.isInverted = true
        model.dropLoad = true
        model.effectsByAction[.load] = .task(.userInitiated) { send in
            await send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        await wait(for: [done], timeout: 0.3)
    }

    @MainActor
    @Test func testSendWithIdStoresTheEffectUnderThatId() async throws {
        let model = Probe()
        model.effectsByAction[.arm] = .onNext { model.log.append("held") }
        var id: EffectID?
        model.send(.arm, id: &id)
        model.send(.plain)
        #expect(model.log.isEmpty)
        model.cancel(try #require(id))
        #expect(model.log == ["held"])
    }

    @MainActor
    @Test func testDisappearCancelsAnAnonymousTask() async {
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
            await send(.loaded(1))
        }
        model.onEvent = { action in
            if case .loaded = action { done.fulfill() }
        }
        model.send(.load)
        await wait(for: [started], timeout: 1)
        model.disappear()
        release?.resume()
        await wait(for: [done], timeout: 0.3)
    }

    @MainActor
    @Test func testReleasingTheModelRunsOnNext() async {
        let box = LogBox()
        do {
            let model = Probe()
            model.effectsByAction[.arm] = .onNext { box.lines.append("dead") }
            model.send(.arm)
        }
        #expect(box.lines == ["dead"])
    }
}
