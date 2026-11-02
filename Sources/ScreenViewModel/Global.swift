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
    private static var identified: [GlobalIdentity: AnyObject] = [:]

    static func insert<Model: AnyObject>(_ model: Model) -> Model {
        entries[ObjectIdentifier(Model.self)] = model
        return model
    }

    static func existing<Model: AnyObject>(as _: Model.Type) -> Model? {
        entries[ObjectIdentifier(Model.self)] as? Model
    }

    static func model<Model: AnyObject>(as _: Model.Type) -> Model {
        guard let model = existing(as: Model.self) else {
            fatalError("No \(Model.self) global. Create it with globalState(_:).")
        }
        return model
    }

    static func insert<Model: AnyObject>(id: String, _ model: Model) -> Model {
        identified[GlobalIdentity(id: id, model: ObjectIdentifier(Model.self))] = model
        return model
    }

    static func existing<Model: AnyObject>(id: String, as _: Model.Type) -> Model? {
        identified[GlobalIdentity(id: id, model: ObjectIdentifier(Model.self))] as? Model
    }

    static func model<Model: AnyObject>(id: String) -> Model {
        guard let model = existing(id: id, as: Model.self) else {
            fatalError("No \(Model.self) global at id \(id). Create it with make(id:_:).")
        }
        return model
    }
}

private struct GlobalIdentity: Hashable {
    let id: String
    let model: ObjectIdentifier
}

/// Returns the app-wide `ViewModel` for this screen, or registers `model` and returns it. Same lifetime as `globalState` for `ScreenModel`.
/// The context autoclosure of a dropped duplicate never runs.
@MainActor
@discardableResult
public func globalState<Screen: ScreenContext>(_ model: @autoclosure () -> ViewModel<Screen, GlobalScope>) -> ViewModel<Screen, GlobalScope> {
    if let existing = GlobalRegistry.existing(as: ViewModel<Screen, GlobalScope>.self) {
        return existing
    }
    return GlobalRegistry.insert(model())
}
