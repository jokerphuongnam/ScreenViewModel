import Foundation

/// Returns the app-wide model of this type, or registers `model` and returns it.
/// The first call keeps that instance until the app exits. Later calls return the same instance.
/// Storing the result does not change a view's lifetime. The model does not retain the view.
@MainActor
@discardableResult
public func globalState<Action, Model: ScreenModel<Action>>(_ model: Model) -> Model {
    if let existing = GlobalRegistry.existing(as: Model.self) {
        return existing
    }
    return GlobalRegistry.insert(model)
}

@MainActor
enum GlobalRegistry {
    private static var entries: [ObjectIdentifier: AnyObject] = [:]

    static func insert<Action, Model: ScreenModel<Action>>(_ model: Model) -> Model {
        entries[ObjectIdentifier(Model.self)] = model
        return model
    }

    static func existing<Action, Model: ScreenModel<Action>>(as _: Model.Type) -> Model? {
        entries[ObjectIdentifier(Model.self)] as? Model
    }

    static func model<Action, Model: ScreenModel<Action>>(as _: Model.Type) -> Model {
        guard let model = existing(as: Model.self) else {
            fatalError("No \(Model.self) global. Create it with globalState(_:).")
        }
        return model
    }
}
