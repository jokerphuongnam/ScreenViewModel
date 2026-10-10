import XCTest
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
