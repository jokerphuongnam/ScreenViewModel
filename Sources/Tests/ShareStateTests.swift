import XCTest
@testable import ScreenViewModel

final class ShareStateTests: XCTestCase {
    @MainActor
    func testShareViewModelIsTheInstanceReadByShareState() {
        let created = shareState(id: "abc", ParentModel())
        let reader = ShareState<ProbeAction, ParentModel>(id: "abc")
        XCTAssertTrue(reader.wrappedValue === created)
        let again = shareState(id: "abc", ParentModel())
        XCTAssertTrue(again === created)
        let createdByWrapper = ShareState(wrappedValue: LeftModel(), id: "group")
        let createdModel = createdByWrapper.wrappedValue
        let sameGroup = ShareState<ProbeAction, LeftModel>(id: "group")
        XCTAssertTrue(sameGroup.wrappedValue === createdModel)
    }

    @MainActor
    func testSameIdWithDifferentModelsAreDifferentGroups() {
        let parent = shareState(id: "abc", ParentModel())
        let left = shareState(id: "abc", LeftModel())
        XCTAssertTrue(shareState(id: "abc", ParentModel()) === parent)
        XCTAssertTrue(shareState(id: "abc", LeftModel()) === left)
        let parentReader = ShareState<ProbeAction, ParentModel>(id: "abc")
        let leftReader = ShareState<ProbeAction, LeftModel>(id: "abc")
        XCTAssertTrue(parentReader.wrappedValue === parent)
        XCTAssertTrue(leftReader.wrappedValue === left)
    }

    @MainActor
    func testSharedModelStaysWhileOneScreenRemains() {
        let id = lifeID()
        let before = LifeModel.alive
        let owner = shareState(id: id, LifeModel())
        do {
            let reader = ShareState<ProbeAction, LifeModel>(id: id)
            XCTAssertTrue(reader.wrappedValue === owner)
        }
        XCTAssertEqual(LifeModel.alive, before + 1)
    }

    @MainActor
    func testSharedModelDeinitsWhenTheLastShareStateScreenIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        do {
            let owner = shareState(id: id, LifeModel())
            let reader = ShareState<ProbeAction, LifeModel>(id: id)
            XCTAssertTrue(reader.wrappedValue === owner)
            XCTAssertEqual(LifeModel.alive, before + 1)
        }
        XCTAssertEqual(LifeModel.alive, before)
    }

    @MainActor
    func testSharedModelDeinitsWhenTheLastShareStateWrapperIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        var reader: ShareState<ProbeAction, LifeModel>?
        do {
            let owner = shareState(id: id, LifeModel())
            reader = ShareState(id: id)
            XCTAssertTrue(reader?.wrappedValue === owner)
        }
        XCTAssertEqual(LifeModel.alive, before + 1)
        reader = nil
        XCTAssertEqual(LifeModel.alive, before)
    }

    @MainActor
    func testShareStateDefaultJoinsTheGroupAndReleasesWithThatScreen() {
        let id = lifeID()
        let before = LifeModel.alive
        var creator: ShareState<ProbeAction, LifeModel>?
        var reader: ShareState<ProbeAction, LifeModel>?
        creator = ShareState(wrappedValue: LifeModel(), id: id)
        _ = creator?.wrappedValue
        reader = ShareState(id: id)
        XCTAssertTrue(reader?.wrappedValue === creator?.wrappedValue)
        XCTAssertEqual(LifeModel.alive, before + 1)
        creator = nil
        XCTAssertEqual(LifeModel.alive, before + 1)
        reader = nil
        XCTAssertEqual(LifeModel.alive, before)
    }

    @MainActor
    func testSharedModelIsNewAfterEveryScreenIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        do {
            let first = shareState(id: id, LifeModel())
            XCTAssertTrue(shareState(id: id, LifeModel()) === first)
        }
        XCTAssertEqual(LifeModel.alive, before)
        let replacement = shareState(id: id, LifeModel())
        XCTAssertEqual(LifeModel.alive, before + 1)
        _ = replacement
    }
}
