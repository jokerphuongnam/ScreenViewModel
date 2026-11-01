import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class GlobalTests {
    @MainActor
    @Test func testGlobalStateIsOneInstanceForTheType() {
        let created = globalState(ParentModel())
        let reader = GlobalState<ProbeAction, ParentModel>()
        #expect(reader.wrappedValue === created)
        #expect(globalState(ParentModel()) === created)
        let other = globalState(LeftModel())
        #expect(!((other as AnyObject) === created))
    }

    @MainActor
    @Test func testGlobalModelLivesAfterEveryScreenIsGone() {
        let before = GlobalLifeModel.alive
        let identity: ObjectIdentifier
        do {
            let owner = globalState(GlobalLifeModel())
            let reader = GlobalState<ProbeAction, GlobalLifeModel>()
            #expect(reader.wrappedValue === owner)
            identity = ObjectIdentifier(owner)
        }
        #expect(GlobalLifeModel.alive == before + 1)
        let again = globalState(GlobalLifeModel())
        #expect(ObjectIdentifier(again) == identity)
        #expect(GlobalLifeModel.alive == before + 1)
        let reader = GlobalState<ProbeAction, GlobalLifeModel>()
        #expect(reader.wrappedValue === again)
    }
}

@MainActor
private final class GlobalLifeModel: ScreenModel<ProbeAction> {
    nonisolated(unsafe) static var alive = 0

    override init() {
        super.init()
        GlobalLifeModel.alive += 1
    }

    deinit {
        GlobalLifeModel.alive -= 1
    }
}
