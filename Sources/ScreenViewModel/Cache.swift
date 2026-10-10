import Foundation
import Observation
import SwiftUI

/// Runs the call for `key` and this result type, or joins the call already running for that pair. A different result type is a different cache. A fresh cached value is returned without calling `fetch` again.
/// This is the ViewModel path: call it from `observable` while loading. The result stays cached for `gcTime` after the call returns.
/// The cache does not retain the view.
@MainActor
public func cache<Value>(
    key: String,
    staleTime: Duration = .zero,
    gcTime: Duration = .seconds(5 * 60),
    _ fetch: @escaping @Sendable () async throws -> Value
) async throws -> Value {
    let cached = CacheRegistry.lease(key: key, staleTime: staleTime, gcTime: gcTime, fetch: fetch)
    return try await cached.load()
}

/// The view path. Same key and value type as `cache`, for a value that only the view displays.
/// The returned object is one observer. It does not retain the view.
@MainActor
public func cached<Value>(
    key: String,
    staleTime: Duration = .zero,
    gcTime: Duration = .seconds(5 * 60),
    _ fetch: @escaping @Sendable () async throws -> Value
) -> Cached<Value> {
    CacheRegistry.lease(key: key, staleTime: staleTime, gcTime: gcTime, fetch: fetch)
}

/// The shared result of a `cache(key:_:)` query. `data`, `error`, and `isFetching` update every view that reads them.
@MainActor
@Observable
public final class Cached<Value> {
    private let entry: CacheEntry<Value>

    public var data: Value? { entry.record.data }
    public var error: (any Error)? { entry.record.error }
    public var isFetching: Bool { entry.record.isFetching }
    public var isPending: Bool { entry.record.status == .pending }
    public var isSuccess: Bool { entry.record.status == .success }
    public var isError: Bool { entry.record.status == .error }

    /// Fetches again, including when the current data is still fresh.
    public func refetch() {
        entry.fetch(force: true)
    }

    func load() async throws -> Value {
        try await entry.load()
    }

    fileprivate init(entry: CacheEntry<Value>) {
        self.entry = entry
        entry.retainObserver()
    }

    deinit {
        let entry = entry
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                entry.releaseObserver()
            }
        } else {
            let queued = entry
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    queued.releaseObserver()
                }
            }
        }
    }
}

/// A view observer for a query. Use this for a value the view displays. API calls belong in the ViewModel through `cache(key:_:)`.
@MainActor
@propertyWrapper
public struct CacheState<Value>: DynamicProperty {
    private let key: String
    private let hold = Hold()

    public init(key: String) {
        self.key = key
    }

    public var wrappedValue: Cached<Value> {
        if let held = hold.value {
            return held
        }
        let cached = CacheRegistry.existing(key: key, as: Value.self)
        hold.value = cached
        return cached
    }

    private final class Hold {
        var value: Cached<Value>?
    }
}

enum CacheClock {
    static var now: () -> Date = { Date() }
}

@MainActor
enum CacheRegistry {
    private static var entries: [CacheIdentity: AnyObject] = [:]

    static func lease<Value>(
        key: String,
        staleTime: Duration,
        gcTime: Duration,
        fetch: @escaping @Sendable () async throws -> Value
    ) -> Cached<Value> {
        let identity = CacheIdentity(key: key, value: ObjectIdentifier(Value.self))
        let entry: CacheEntry<Value>
        if let existing = entries[identity] as? CacheEntry<Value> {
            existing.fetchBody = fetch
            existing.staleTime = staleTime
            existing.gcTime = gcTime
            entry = existing
        } else {
            entry = CacheEntry(identity: identity, fetch: fetch, staleTime: staleTime, gcTime: gcTime)
            entries[identity] = entry
        }
        return Cached(entry: entry)
    }

    static func existing<Value>(key: String, as _: Value.Type) -> Cached<Value> {
        let identity = CacheIdentity(key: key, value: ObjectIdentifier(Value.self))
        guard let entry = entries[identity] as? CacheEntry<Value> else {
            fatalError("No cache for \(key). Create it with cache(key:_:) or cached(key:_:).")
        }
        return Cached(entry: entry)
    }

    static func remove(_ identity: CacheIdentity, entry: AnyObject) {
        guard entries[identity] === entry else { return }
        entries[identity] = nil
    }
}

struct CacheIdentity: Hashable {
    let key: String
    let value: ObjectIdentifier
}

enum CacheStatus {
    case pending
    case success
    case error
}

@MainActor
@Observable
final class CacheRecord<Value> {
    var data: Value?
    var error: (any Error)?
    var isFetching = false
    var status = CacheStatus.pending
}

@MainActor
final class CacheEntry<Value> {
    let identity: CacheIdentity
    let record = CacheRecord<Value>()
    var fetchBody: @Sendable () async throws -> Value
    var staleTime: Duration
    var gcTime: Duration
    private var observers = 0
    private var task: Task<Value, Error>?
    private var updatedAt: Date?
    private var collect: Task<Void, Never>?

    init(
        identity: CacheIdentity,
        fetch: @escaping @Sendable () async throws -> Value,
        staleTime: Duration,
        gcTime: Duration
    ) {
        self.identity = identity
        self.fetchBody = fetch
        self.staleTime = staleTime
        self.gcTime = gcTime
    }

    func retainObserver() {
        observers += 1
        collect?.cancel()
        collect = nil
        if record.data == nil || isStale {
            fetch(force: false)
        }
    }

    func load() async throws -> Value {
        if let data = record.data, !isStale {
            return data
        }
        return try await run(force: false).value
    }

    func releaseObserver() {
        observers = max(0, observers - 1)
        guard observers == 0 else { return }
        if gcTime == .zero {
            evict()
            return
        }
        let wait = gcTime
        collect = Task { @MainActor in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled, self.observers == 0 else { return }
            self.evict()
        }
    }

    func fetch(force: Bool) {
        _ = run(force: force)
    }

    private func run(force: Bool) -> Task<Value, Error> {
        if let task, !force { return task }
        task?.cancel()
        let fetchBody = fetchBody
        record.isFetching = true
        let task = Task<Value, Error> { @MainActor in
            do {
                let value = try await fetchBody()
                try Task.checkCancellation()
                self.record.data = value
                self.record.error = nil
                self.record.status = .success
                self.updatedAt = CacheClock.now()
                self.record.isFetching = false
                self.task = nil
                return value
            } catch {
                self.record.isFetching = false
                self.task = nil
                guard !Task.isCancelled else { throw error }
                self.record.error = error
                self.record.status = .error
                throw error
            }
        }
        self.task = task
        return task
    }

    private var isStale: Bool {
        guard let updatedAt else { return true }
        return CacheClock.now().timeIntervalSince(updatedAt) >= staleTime.seconds
    }

    private func evict() {
        task?.cancel()
        task = nil
        collect?.cancel()
        collect = nil
        CacheRegistry.remove(identity, entry: self)
    }
}

private extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
