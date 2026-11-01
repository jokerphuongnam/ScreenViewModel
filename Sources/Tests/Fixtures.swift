import Foundation
import Testing
@testable import ScreenViewModel

enum ProbeAction: ScreenAction, Hashable {
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

final class LogBox {
    var lines: [String] = []
}

@MainActor
final class Probe: ScreenModel<ProbeAction> {
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

struct StaticAction: Hashable {
    var name: String
    static let arm = StaticAction(name: "arm")
    static let plain = StaticAction(name: "plain")
}

@MainActor
final class StaticProbe: ScreenModel<StaticAction> {
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

@MainActor
func lifeID() -> String {
    "life-\(UUID().uuidString)"
}

@MainActor
final class LifeModel: ScreenModel<ProbeAction> {
    nonisolated(unsafe) static var alive = 0

    override init() {
        super.init()
        LifeModel.alive += 1
    }

    deinit {
        LifeModel.alive -= 1
    }
}

final class ParentModel: ScreenModel<ProbeAction> {}
final class LeftModel: ScreenModel<ProbeAction> {}
final class RightModel: ScreenModel<ProbeAction> {}

// MARK: - Swift Testing expectation helper

/// Thread-safe expectation helper for Swift Testing (fulfill / inverted / count).
final class Expectation: @unchecked Sendable {
    let description: String
    var expectedFulfillmentCount = 1
    var isInverted = false
    private let lock = NSLock()
    private var count = 0

    init(description: String) { self.description = description }

    func fulfill() {
        lock.lock(); count += 1; lock.unlock()
    }

    var fulfillmentCount: Int {
        lock.lock(); defer { lock.unlock() }
        return count
    }
}

func expectation(description: String) -> Expectation {
    Expectation(description: description)
}

/// Polls until every expectation is met (or, when inverted, until the timeout
/// passes without fulfillment); records a Swift Testing issue otherwise.
@MainActor
func wait(
    for expectations: [Expectation],
    timeout: Double,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    let deadline = Date().addingTimeInterval(timeout)
    func satisfied() -> Bool {
        expectations.allSatisfy { $0.isInverted || $0.fulfillmentCount >= $0.expectedFulfillmentCount }
    }
    while Date() < deadline {
        if expectations.contains(where: { $0.isInverted && $0.fulfillmentCount > 0 }) { break }
        if satisfied() && !expectations.contains(where: \.isInverted) { break }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    for e in expectations {
        if e.isInverted {
            #expect(e.fulfillmentCount == 0, "inverted expectation '\(e.description)' was fulfilled",
                    sourceLocation: sourceLocation)
        } else {
            #expect(e.fulfillmentCount >= e.expectedFulfillmentCount,
                    "expectation '\(e.description)' not fulfilled within \(timeout)s",
                    sourceLocation: sourceLocation)
        }
    }
}
