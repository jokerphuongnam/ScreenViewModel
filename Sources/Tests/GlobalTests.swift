import XCTest
@testable import ScreenViewModel

final class GlobalTests: XCTestCase {
    @MainActor
    func testGlobalStateIsOneInstanceForTheType() {
        let created = globalState(ParentModel())
        let reader = GlobalState<ProbeAction, ParentModel>()
        XCTAssertTrue(reader.wrappedValue === created)
        XCTAssertTrue(globalState(ParentModel()) === created)
        let other = globalState(LeftModel())
        XCTAssertFalse((other as AnyObject) === created)
    }

    @MainActor
    func testGlobalModelLivesAfterEveryScreenIsGone() {
        let before = GlobalLifeModel.alive
        let identity: ObjectIdentifier
        do {
            let owner = globalState(GlobalLifeModel())
            let reader = GlobalState<ProbeAction, GlobalLifeModel>()
            XCTAssertTrue(reader.wrappedValue === owner)
            identity = ObjectIdentifier(owner)
        }
        XCTAssertEqual(GlobalLifeModel.alive, before + 1)
        let again = globalState(GlobalLifeModel())
        XCTAssertEqual(ObjectIdentifier(again), identity)
        XCTAssertEqual(GlobalLifeModel.alive, before + 1)
        let reader = GlobalState<ProbeAction, GlobalLifeModel>()
        XCTAssertTrue(reader.wrappedValue === again)
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
