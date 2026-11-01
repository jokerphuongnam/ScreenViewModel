import Foundation
import Testing
@testable import ScreenViewModel

@Suite(.serialized) final class ParentStateTests {
    @MainActor
    @Test func testChildScopeSeesTheParentModelAndNotItsSibling() {
        let parent = ParentModel()
        let left = LeftModel()
        let right = RightModel()
        let root = ScreenScope().setting(parent)
        let leftScope = root.setting(left)
        let rightScope = root.setting(right)
        #expect(leftScope.model(ParentModel.self) === parent)
        #expect(rightScope.model(ParentModel.self) === parent)
        #expect(leftScope.model(RightModel.self) == nil)
        #expect(rightScope.model(LeftModel.self) == nil)
    }
}
