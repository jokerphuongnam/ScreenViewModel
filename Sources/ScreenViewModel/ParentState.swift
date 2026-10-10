import SwiftUI

private struct ScreenScopeKey: EnvironmentKey {
    static let defaultValue = ScreenScope()
}

extension EnvironmentValues {
    var screenScope: ScreenScope {
        get { self[ScreenScopeKey.self] }
        set { self[ScreenScopeKey.self] = newValue }
    }
}

extension View {
    /// Publishes `model` to this view and every descendant, the same way `environmentObject` does. Views outside this modifier do not see it. A sibling does not see another sibling's model.
    public func parentState<Model: AnyObject>(_ model: Model) -> some View {
        transformEnvironment(\.screenScope) { scope in
            scope = scope.setting(model)
        }
    }
}

/// The ViewModel declared by a parent view. A child can read its parent's model. It cannot read a sibling's model.
@propertyWrapper
public struct ParentState<Model: AnyObject>: DynamicProperty {
    @Environment(\.screenScope) private var scope

    public init() {}

    public var wrappedValue: Model {
        guard let model = scope.model(Model.self) else {
            fatalError("No \(Model.self) above this view. Call parentState(_:) on a parent view.")
        }
        return model
    }
}
