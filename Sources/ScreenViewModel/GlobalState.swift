import SwiftUI

/// The app-wide ViewModel of this type. `globalState` creates it once, and it stays until the app exits.
/// Reading it does not retain the view, and releasing this screen does not release the model.
@MainActor
@propertyWrapper
public struct GlobalState<Action, Model: ScreenModel<Action>>: DynamicProperty {
    public init() {}

    public var wrappedValue: Model {
        GlobalRegistry.model(as: Model.self)
    }
}
