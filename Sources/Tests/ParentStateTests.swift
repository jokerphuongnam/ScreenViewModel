import XCTest
@testable import ScreenViewModel

final class ParentStateTests: XCTestCase {
    @MainActor
    func testChildScopeSeesTheParentModelAndNotItsSibling() {
        let parent = ParentModel()
        let left = LeftModel()
        let right = RightModel()
        let root = ScreenScope().setting(parent)
        let leftScope = root.setting(left)
        let rightScope = root.setting(right)
        XCTAssertTrue(leftScope.model(ParentModel.self) === parent)
        XCTAssertTrue(rightScope.model(ParentModel.self) === parent)
        XCTAssertNil(leftScope.model(RightModel.self))
        XCTAssertNil(rightScope.model(LeftModel.self))
    }
}
