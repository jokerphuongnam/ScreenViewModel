import Foundation
import Observation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class ObservationTests {
    @MainActor
    @Test func testGlobalCreatorAndReadersUpdate() async {
        let model = globalState(ObservedModel())
        let reader = GlobalState<ProbeAction, ObservedModel>()
        await expectChange { model.count } change: { model.count += 1 }
        await expectChange { reader.wrappedValue.count } change: { model.count += 1 }
    }

    @MainActor
    @Test func testShareCreatorAndReadersUpdate() async {
        let id = "observe-\(UUID().uuidString)"
        let model = shareState(id: id, ObservedModel())
        let reader = ShareState<ProbeAction, ObservedModel>(id: id)
        await expectChange { model.title } change: { model.title = "next" }
        await expectChange { reader.wrappedValue.title } change: { model.title = "after" }
    }

    @MainActor
    @Test func testParentAndChildUpdateFromTheSameModel() async throws {
        let parent = ObservedModel()
        let published = ScreenScope().setting(parent).model(ObservedModel.self)
        let child = try #require(published)
        await expectChange { parent.count } change: { parent.count += 1 }
        await expectChange { child.count } change: { parent.count += 1 }
    }

    @MainActor
    private func expectChange(_ read: () -> some Any, change: () -> Void) async {
        let changed = expectation(description: "changed")
        withObservationTracking {
            _ = read()
        } onChange: {
            changed.fulfill()
        }
        change()
        await wait(for: [changed], timeout: 1)
    }
}

@MainActor
@Observable
private final class ObservedModel: ScreenModel<ProbeAction> {
    var count = 0
    var title = ""
}
