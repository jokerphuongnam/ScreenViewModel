import SwiftUI

/// The ViewModel for `id`. A default value creates the instance when this id has none yet.
/// This screen holds that instance while the screen is alive and releases it when the screen is gone.
/// The same id with another model type is another group. The model deinits only after every screen in this group is gone. The model does not retain the view.
@MainActor
@propertyWrapper
public struct ShareState<Action, Model: ScreenModel<Action>>: DynamicProperty {
    private let id: String
    private let created: Model?
    private let hold = Hold()

    public init(id: String) {
        self.id = id
        self.created = nil
    }

    public init(wrappedValue: Model, id: String) {
        self.id = id
        self.created = wrappedValue
    }

    public var wrappedValue: Model {
        if let held = hold.value {
            return held
        }
        let model: Model
        if let existing = ShareRegistry.existing(id: id, as: Model.self) {
            model = existing
        } else if let created {
            model = ShareRegistry.insert(id: id, created)
        } else {
            model = ShareRegistry.model(id: id)
        }
        hold.value = model
        return model
    }

    private final class Hold {
        var value: Model?
    }
}
