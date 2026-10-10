import Foundation

/// Returns the model already registered at `id`, or registers `model` and returns it.
/// Storing the result, usually in `@State`, is this screen joining the group. The registry does not keep the model alive.
/// The model is released when every screen that joined with `shareState` or `@ShareState` is gone. It does not retain those views.
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
    private static var entries: [String: WeakBox] = [:]

    static func insert<Action, Model: ScreenModel<Action>>(id: String, _ model: Model) -> Model {
        entries[id] = WeakBox(model)
        return model
    }

    static func existing<Action, Model: ScreenModel<Action>>(id: String, as _: Model.Type) -> Model? {
        entries[id]?.value as? Model
    }

    static func model<Action, Model: ScreenModel<Action>>(id: String) -> Model {
        guard let model = existing(id: id, as: Model.self) else {
            fatalError("No \(Model.self) shared at id \(id). Create it with shareState(id:_:) or @ShareState(id:).")
        }
        return model
    }
}

private final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}
