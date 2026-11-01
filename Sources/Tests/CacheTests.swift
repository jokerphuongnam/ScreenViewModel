import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class CacheTests {
    deinit {
        CacheClock.now = { Date() }
    }

    @MainActor
    @Test func testSameKeyWithDifferentResultsAreDifferentCaches() async throws {
        let text = try await cache(key: "fact", staleTime: .seconds(60), gcTime: .seconds(60)) { "A" }
        let number = try await cache(key: "fact", staleTime: .seconds(60), gcTime: .seconds(60)) { 1 }
        let textAgain = try await cache(key: "fact", staleTime: .seconds(60), gcTime: .seconds(60)) { "B" }
        let numberAgain = try await cache(key: "fact", staleTime: .seconds(60), gcTime: .seconds(60)) { 2 }
        #expect(text == "A")
        #expect(number == 1)
        #expect(textAgain == "A")
        #expect(numberAgain == 1)
    }

    @MainActor
    @Test func testCacheKeepsTheValueUntilStaleTime() async throws {
        let key = UUID().uuidString
        let calls = CallCount()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        CacheClock.now = { start }
        let first = try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(3600)) {
            calls.value += 1
            return "A"
        }
        CacheClock.now = { start.addingTimeInterval(59) }
        let second = try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(3600)) {
            calls.value += 1
            return "B"
        }
        #expect(first == "A")
        #expect(second == "A")
        #expect(calls.value == 1)
    }

    @MainActor
    @Test func testCacheFetchesAgainAtStaleTime() async throws {
        let key = UUID().uuidString
        let calls = CallCount()
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        CacheClock.now = { start }
        _ = try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(3600)) {
            calls.value += 1
            return "A"
        }
        CacheClock.now = { start.addingTimeInterval(60) }
        let second = try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(3600)) {
            calls.value += 1
            return "B"
        }
        #expect(second == "B")
        #expect(calls.value == 2)
    }

    @MainActor
    @Test func testViewModelSharesOneAPICall() async throws {
        let key = UUID().uuidString
        let calls = CallCount()
        let ready = Ready()
        let gate = Gate()
        let first = Task { @MainActor in
            try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
                calls.value += 1
                await ready.signal()
                await gate.wait()
                return "A"
            }
        }
        await ready.wait()
        let second = Task { @MainActor in
            try await cache(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
                calls.value += 1
                return "B"
            }
        }
        await Task.yield()
        #expect(calls.value == 1)
        gate.open()
        let firstValue = try await first.value
        let secondValue = try await second.value
        #expect(firstValue == "A")
        #expect(secondValue == "A")
        #expect(calls.value == 1)
    }

    @MainActor
    @Test func testSameKeySharesOneFetch() async {
        let key = UUID().uuidString
        let calls = CallCount()
        let gate = Gate()
        let started = expectation(description: "started")
        let first = cached(key: key, gcTime: .zero) {
            calls.value += 1
            started.fulfill()
            await gate.wait()
            return "A"
        }
        let second = cached(key: key, gcTime: .zero) {
            calls.value += 1
            return "B"
        }
        let reader = CacheState<String>(key: key)
        await wait(for: [started], timeout: 1)
        #expect(calls.value == 1)
        #expect(first.isPending)
        #expect(reader.wrappedValue.isFetching)
        gate.open()
        await waitUntil { first.data != nil }
        #expect(first.data == "A")
        #expect(second.data == "A")
        #expect(first.isSuccess)
        #expect(!(first.isFetching))
    }

    @MainActor
    @Test func testFreshCacheDoesNotFetchAgain() async {
        let key = UUID().uuidString
        let calls = CallCount()
        let first = cached(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
            calls.value += 1
            return "A"
        }
        await waitUntil { first.data != nil }
        let second = cached(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
            calls.value += 1
            return "B"
        }
        #expect(second.data == "A")
        #expect(calls.value == 1)
    }

    @MainActor
    @Test func testStaleObserverFetchesAgainAndKeepsData() async {
        let key = UUID().uuidString
        let calls = CallCount()
        let first = cached(key: key, staleTime: .zero, gcTime: .seconds(60)) {
            calls.value += 1
            return calls.value == 1 ? "A" : "B"
        }
        await waitUntil { first.data == "A" }
        let second = cached(key: key, staleTime: .zero, gcTime: .seconds(60)) {
            calls.value += 1
            return "B"
        }
        #expect(second.data == "A")
        #expect(second.isFetching)
        await waitUntil { second.data == "B" }
        #expect(first.data == "B")
        #expect(calls.value == 2)
    }

    @MainActor
    @Test func testLastObserverDropsTheCacheAfterGcTime() async {
        let key = UUID().uuidString
        var held: Cached<String>? = cached(key: key, staleTime: .seconds(60), gcTime: .zero) {
            "A"
        }
        await waitUntil { held?.data == "A" }
        held = nil
        let again = cached(key: key, staleTime: .seconds(60), gcTime: .zero) {
            "B"
        }
        #expect(again.isPending)
        await waitUntil { again.data == "B" }
    }

    @MainActor
    @Test func testFailureIsVisibleAndRefetchReplacesIt() async {
        let key = UUID().uuidString
        let calls = CallCount()
        let query = cached(key: key, gcTime: .seconds(60)) {
            calls.value += 1
            if calls.value == 1 {
                throw TestError.failed
            }
            return "A"
        }
        await waitUntil { query.isError }
        #expect(query.data == nil)
        query.refetch()
        await waitUntil { query.data == "A" }
        #expect(query.isSuccess)
        #expect(query.error == nil)
    }

    @MainActor
    private func waitUntil(_ ready: @escaping @MainActor () -> Bool) async {
        let done = expectation(description: "ready")
        Task { @MainActor in
            while !ready() {
                await Task.yield()
            }
            done.fulfill()
        }
        await wait(for: [done], timeout: 2)
    }
}

private enum TestError: Error {
    case failed
}

private final class CallCount: @unchecked Sendable {
    var value = 0
}

private final class Ready: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?
    private var signaled = false

    func signal() async {
        signaled = true
        continuation?.resume()
        continuation = nil
    }

    func wait() async {
        if signaled { return }
        await withCheckedContinuation { continuation = $0 }
    }
}

private final class Gate: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
