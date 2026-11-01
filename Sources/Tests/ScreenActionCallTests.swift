import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class ScreenActionCallTests {
    @MainActor
    @Test func testSubscriptSendsAnEnumCase() {
        let model = Probe()
        model[.plain]()
        #expect(model.seen == [.plain])
    }

    @MainActor
    @Test func testCallSendsTheStaticAction() {
        let model = StaticProbe()
        model[.arm]()
        #expect(model.seen == [.arm])
        model[.plain]()
        #expect(model.log == ["held"])
    }

    @MainActor
    @Test func testMemberIdMatchesCallThenId() throws {
        let direct = StaticProbe()
        var directID: EffectID?
        _ = direct[.arm].id(&directID)
        direct.cancel(try #require(directID))
        #expect(direct.log == ["held"])

        let called = StaticProbe()
        var calledID: EffectID?
        _ = called[.arm]().id(&calledID)
        called.cancel(try #require(calledID))
        #expect(called.log == ["held"])
    }
}
