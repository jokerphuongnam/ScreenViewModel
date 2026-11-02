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

