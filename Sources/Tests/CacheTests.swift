import XCTest
@testable import ScreenViewModel

final class CacheTests: XCTestCase {
    override func tearDown() {
        CacheClock.now = { Date() }
        super.tearDown()
    }

    @MainActor
    func testCacheKeepsTheValueUntilStaleTime() async throws {
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
        XCTAssertEqual(first, "A")
        XCTAssertEqual(second, "A")
        XCTAssertEqual(calls.value, 1)
    }

    @MainActor
    func testCacheFetchesAgainAtStaleTime() async throws {
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
        XCTAssertEqual(second, "B")
        XCTAssertEqual(calls.value, 2)
    }

    @MainActor
    func testViewModelSharesOneAPICall() async throws {
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
        XCTAssertEqual(calls.value, 1)
        gate.open()
        let firstValue = try await first.value
        let secondValue = try await second.value
        XCTAssertEqual(firstValue, "A")
        XCTAssertEqual(secondValue, "A")
        XCTAssertEqual(calls.value, 1)
    }

    @MainActor
    func testSameKeySharesOneFetch() {
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
        wait(for: [started], timeout: 1)
        XCTAssertEqual(calls.value, 1)
        XCTAssertTrue(first.isPending)
        XCTAssertTrue(reader.wrappedValue.isFetching)
        gate.open()
        waitUntil { first.data != nil }
        XCTAssertEqual(first.data, "A")
        XCTAssertEqual(second.data, "A")
        XCTAssertTrue(first.isSuccess)
        XCTAssertFalse(first.isFetching)
    }

    @MainActor
    func testFreshCacheDoesNotFetchAgain() {
        let key = UUID().uuidString
        let calls = CallCount()
        let first = cached(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
            calls.value += 1
            return "A"
        }
        waitUntil { first.data != nil }
        let second = cached(key: key, staleTime: .seconds(60), gcTime: .seconds(60)) {
            calls.value += 1
            return "B"
        }
        XCTAssertEqual(second.data, "A")
        XCTAssertEqual(calls.value, 1)
    }

    @MainActor
    func testStaleObserverFetchesAgainAndKeepsData() {
        let key = UUID().uuidString
        let calls = CallCount()
        let first = cached(key: key, staleTime: .zero, gcTime: .seconds(60)) {
            calls.value += 1
            return calls.value == 1 ? "A" : "B"
        }
        waitUntil { first.data == "A" }
        let second = cached(key: key, staleTime: .zero, gcTime: .seconds(60)) {
            calls.value += 1
            return "B"
        }
        XCTAssertEqual(second.data, "A")
        XCTAssertTrue(second.isFetching)
        waitUntil { second.data == "B" }
        XCTAssertEqual(first.data, "B")
        XCTAssertEqual(calls.value, 2)
    }

    @MainActor
    func testLastObserverDropsTheCacheAfterGcTime() {
        let key = UUID().uuidString
        var held: Cached<String>? = cached(key: key, staleTime: .seconds(60), gcTime: .zero) {
            "A"
        }
        waitUntil { held?.data == "A" }
        held = nil
        let again = cached(key: key, staleTime: .seconds(60), gcTime: .zero) {
            "B"
        }
        XCTAssertTrue(again.isPending)
        waitUntil { again.data == "B" }
    }

    @MainActor
    func testFailureIsVisibleAndRefetchReplacesIt() {
        let key = UUID().uuidString
        let calls = CallCount()
        let query = cached(key: key, gcTime: .seconds(60)) {
            calls.value += 1
            if calls.value == 1 {
                throw TestError.failed
            }
            return "A"
        }
        waitUntil { query.isError }
        XCTAssertNil(query.data)
        query.refetch()
        waitUntil { query.data == "A" }
        XCTAssertTrue(query.isSuccess)
        XCTAssertNil(query.error)
    }

    @MainActor
    private func waitUntil(_ ready: @escaping @MainActor () -> Bool) {
        let done = expectation(description: "ready")
        Task { @MainActor in
            while !ready() {
                await Task.yield()
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
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
