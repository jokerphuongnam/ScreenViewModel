import XCTest
@testable import ScreenViewModel

final class ScreenActionCallTests: XCTestCase {
    @MainActor
    func testSubscriptSendsAnEnumCase() {
        let model = Probe()
        model[.plain]()
        XCTAssertEqual(model.seen, [.plain])
    }

    @MainActor
    func testCallSendsTheStaticAction() {
        let model = StaticProbe()
        model[.arm]()
        XCTAssertEqual(model.seen, [.arm])
        model[.plain]()
        XCTAssertEqual(model.log, ["held"])
    }

    @MainActor
    func testMemberIdMatchesCallThenId() throws {
        let direct = StaticProbe()
        var directID: EffectID?
        _ = direct[.arm].id(&directID)
        direct.cancel(try XCTUnwrap(directID))
        XCTAssertEqual(direct.log, ["held"])

        let called = StaticProbe()
        var calledID: EffectID?
        _ = called[.arm]().id(&calledID)
        called.cancel(try XCTUnwrap(calledID))
        XCTAssertEqual(called.log, ["held"])
    }
}
