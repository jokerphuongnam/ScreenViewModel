import Foundation

/// The view owns this model. Nothing is published to a parent, the app, or a share id.
public enum ViewState {}

/// The model belongs to the parent subtree. Create it with `make(context:)`, publish it with `parentState(_:)`, and children read that same instance.
public enum ParentScope {}

/// One instance for the app. `make` returns the instance already registered for this screen.
public enum GlobalScope {}

/// One instance for an `id`. `make` returns the instance already registered for this screen and id.
public enum ShareScope {}

extension ViewModel where Source == ViewState {
    /// Owns the model. `context` runs once, on the first read or send.
    public convenience init(context: @autoclosure @escaping () -> ViewModelContext<Screen>) {
        self.init(factory: context)
    }
}

extension ViewModel where Source == ParentScope {
    /// The instance the parent owns. Pass it to `parentState(_:)` so descendants read this object.
    public static func make(context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, ParentScope> {
        ViewModel(factory: context)
    }
}

extension ViewModel where Source == GlobalScope {
    /// Returns the app-wide instance, creating it from `context` only the first time.
    public static func make(context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, GlobalScope> {
        if let existing = GlobalRegistry.existing(as: ViewModel<Screen, GlobalScope>.self) {
            return existing
        }
        return GlobalRegistry.insert(ViewModel(factory: context))
    }

    /// The instance already registered with `make(context:)`.
    public static func make() -> ViewModel<Screen, GlobalScope> {
        GlobalRegistry.model(as: ViewModel<Screen, GlobalScope>.self)
    }
}

extension ViewModel where Source == ShareScope {
    /// Returns the instance at `id`, creating it from `context` only when that id has none.
    public static func make(id: String, context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, ShareScope> {
        if let existing = ShareRegistry.existing(id: id, as: ViewModel<Screen, ShareScope>.self) {
            return existing
        }
        return ShareRegistry.insert(id: id, ViewModel(factory: context))
    }

    /// The instance already registered at `id`.
    public static func make(id: String) -> ViewModel<Screen, ShareScope> {
        ShareRegistry.model(id: id)
    }
}
