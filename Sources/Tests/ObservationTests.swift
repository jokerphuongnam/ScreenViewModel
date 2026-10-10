import Observation
import XCTest
@testable import ScreenViewModel

final class ObservationTests: XCTestCase {
    @MainActor
    func testGlobalCreatorAndReadersUpdate() {
        let model = globalState(ObservedModel())
        let reader = GlobalState<ProbeAction, ObservedModel>()
        expectChange { model.count } change: { model.count += 1 }
        expectChange { reader.wrappedValue.count } change: { model.count += 1 }
    }

    @MainActor
    func testShareCreatorAndReadersUpdate() {
        let id = "observe-\(UUID().uuidString)"
        let model = shareState(id: id, ObservedModel())
        let reader = ShareState<ProbeAction, ObservedModel>(id: id)
        expectChange { model.title } change: { model.title = "next" }
        expectChange { reader.wrappedValue.title } change: { model.title = "after" }
    }

    @MainActor
    func testParentAndChildUpdateFromTheSameModel() throws {
        let parent = ObservedModel()
        let published = ScreenScope().setting(parent).model(ObservedModel.self)
        let child = try XCTUnwrap(published)
        expectChange { parent.count } change: { parent.count += 1 }
        expectChange { child.count } change: { parent.count += 1 }
    }

    @MainActor
    private func expectChange(_ read: () -> some Any, change: () -> Void) {
        let changed = expectation(description: "changed")
        withObservationTracking {
            _ = read()
        } onChange: {
            changed.fulfill()
        }
        change()
        wait(for: [changed], timeout: 1)
    }
}

@MainActor
@Observable
private final class ObservedModel: ScreenModel<ProbeAction> {
    var count = 0
    var title = ""
}
