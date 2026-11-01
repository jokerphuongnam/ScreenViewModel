import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class ShareStateTests {
    @MainActor
    @Test func testShareViewModelIsTheInstanceReadByShareState() {
        let created = shareState(id: "abc", ParentModel())
        let reader = ShareState<ProbeAction, ParentModel>(id: "abc")
        #expect(reader.wrappedValue === created)
        let again = shareState(id: "abc", ParentModel())
        #expect(again === created)
        let createdByWrapper = ShareState(wrappedValue: LeftModel(), id: "group")
        let createdModel = createdByWrapper.wrappedValue
        let sameGroup = ShareState<ProbeAction, LeftModel>(id: "group")
        #expect(sameGroup.wrappedValue === createdModel)
    }

    @MainActor
    @Test func testSameIdWithDifferentModelsAreDifferentGroups() {
        let parent = shareState(id: "abc", ParentModel())
        let left = shareState(id: "abc", LeftModel())
        #expect(shareState(id: "abc", ParentModel()) === parent)
        #expect(shareState(id: "abc", LeftModel()) === left)
        let parentReader = ShareState<ProbeAction, ParentModel>(id: "abc")
        let leftReader = ShareState<ProbeAction, LeftModel>(id: "abc")
        #expect(parentReader.wrappedValue === parent)
        #expect(leftReader.wrappedValue === left)
    }

    @MainActor
    @Test func testSharedModelStaysWhileOneScreenRemains() {
        let id = lifeID()
        let before = LifeModel.alive
        let owner = shareState(id: id, LifeModel())
        do {
            let reader = ShareState<ProbeAction, LifeModel>(id: id)
            #expect(reader.wrappedValue === owner)
        }
        #expect(LifeModel.alive == before + 1)
    }

    @MainActor
    @Test func testSharedModelDeinitsWhenTheLastShareStateScreenIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        do {
            let owner = shareState(id: id, LifeModel())
            let reader = ShareState<ProbeAction, LifeModel>(id: id)
            #expect(reader.wrappedValue === owner)
            #expect(LifeModel.alive == before + 1)
        }
        #expect(LifeModel.alive == before)
    }

    @MainActor
    @Test func testSharedModelDeinitsWhenTheLastShareStateWrapperIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        var reader: ShareState<ProbeAction, LifeModel>?
        do {
            let owner = shareState(id: id, LifeModel())
            reader = ShareState(id: id)
            #expect(reader?.wrappedValue === owner)
        }
        #expect(LifeModel.alive == before + 1)
        reader = nil
        #expect(LifeModel.alive == before)
    }

    @MainActor
    @Test func testShareStateDefaultJoinsTheGroupAndReleasesWithThatScreen() {
        let id = lifeID()
        let before = LifeModel.alive
        var creator: ShareState<ProbeAction, LifeModel>?
        var reader: ShareState<ProbeAction, LifeModel>?
        creator = ShareState(wrappedValue: LifeModel(), id: id)
        _ = creator?.wrappedValue
        reader = ShareState(id: id)
        #expect(reader?.wrappedValue === creator?.wrappedValue)
        #expect(LifeModel.alive == before + 1)
        creator = nil
        #expect(LifeModel.alive == before + 1)
        reader = nil
        #expect(LifeModel.alive == before)
    }

    @MainActor
    @Test func testSharedModelIsNewAfterEveryScreenIsGone() {
        let id = lifeID()
        let before = LifeModel.alive
        do {
            let first = shareState(id: id, LifeModel())
            #expect(shareState(id: id, LifeModel()) === first)
        }
        #expect(LifeModel.alive == before)
        let replacement = shareState(id: id, LifeModel())
        #expect(LifeModel.alive == before + 1)
        _ = replacement
    }
}
