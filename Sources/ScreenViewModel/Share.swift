import Foundation

/// Returns the model already registered at `id`, or registers `model` and returns it.
/// Storing the result, usually in `@State`, is this screen joining the group. The registry does not keep the model alive.
/// The same id with a different model type is a different group. The model is released when every screen in its group is gone. It does not retain those views.
@MainActor
@discardableResult
public func shareState<Action, Model: ScreenModel<Action>>(id: String, _ model: Model) -> Model {
    if let existing = ShareRegistry.existing(id: id, as: Model.self) {
        return existing
    }
    return ShareRegistry.insert(id: id, model)
}

@MainActor
enum ShareRegistry {
    private static var entries: [ShareIdentity: WeakBox] = [:]

    static func insert<Model: AnyObject>(id: String, _ model: Model) -> Model {
        entries[ShareIdentity(id: id, model: ObjectIdentifier(Model.self))] = WeakBox(model)
        return model
    }

    static func existing<Model: AnyObject>(id: String, as _: Model.Type) -> Model? {
        entries[ShareIdentity(id: id, model: ObjectIdentifier(Model.self))]?.value as? Model
    }

    static func model<Model: AnyObject>(id: String) -> Model {
        guard let model = existing(id: id, as: Model.self) else {
            fatalError("No \(Model.self) shared at id \(id). Create it with shareState(id:_:) or @ShareState(id:).")
        }
        return model
    }
}

private struct ShareIdentity: Hashable {
    let id: String
    let model: ObjectIdentifier
}

private final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

/// Returns the `ViewModel` already shared at `id`, or registers `model` and returns it. Same lifetime as `shareState` for `ScreenModel`:
/// the registry is weak, and the last screen holding it releases it. `model` is only built when `id` has none.
@MainActor
@discardableResult
public func shareState<Screen: ScreenContext>(id: String, _ model: @autoclosure () -> ViewModel<Screen>) -> ViewModel<Screen> {
    if let existing = ShareRegistry.existing(id: id, as: ViewModel<Screen>.self) {
        return existing
    }
    return ShareRegistry.insert(id: id, model())
}
