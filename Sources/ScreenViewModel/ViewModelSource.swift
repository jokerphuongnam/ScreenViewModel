import Foundation

/// Only this module can create a token, so another module cannot conform to `ViewModelSource`.
public struct ViewModelSourceToken {
    internal init() {}
}

public protocol ViewModelSource {
    static var sourceToken: ViewModelSourceToken { get }
}

/// The view owns this model. Nothing is published to a parent, the app, or a share id.
public enum ViewState: ViewModelSource {
    public static var sourceToken: ViewModelSourceToken { ViewModelSourceToken() }
}

/// One instance for this `ViewModel` type. The parent creates it. When that instance is deallocated, the group is gone.
public enum ParentScope: ViewModelSource {
    public static var sourceToken: ViewModelSourceToken { ViewModelSourceToken() }
}

/// One instance for an id, kept until the app exits. `make(id:_:)` creates it. `make(id:)` only reads it.
public enum GlobalScope: ViewModelSource {
    public static var sourceToken: ViewModelSourceToken { ViewModelSourceToken() }
}

/// One instance for an id, released with the last owner. `make(id:_:)` creates it. `make(id:)` only reads it.
public enum ShareScope: ViewModelSource {
    public static var sourceToken: ViewModelSourceToken { ViewModelSourceToken() }
}

extension ViewModel where Source == ViewState {
    /// Owns the model. `context` runs once, on the first read or send.
    public static func make(context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, ViewState> {
        ViewModel(factory: context)
    }

    public convenience init(context: @autoclosure @escaping () -> ViewModelContext<Screen>) {
        self.init(factory: context)
    }
}

extension ViewModel where Source == ParentScope {
    /// Creates the one instance for this `ViewModel` type. A later `make(context:)` while that instance is alive returns it and does not run `context`. `make()` returns the live instance and does not create one. A child stores `@Bindable private var coordinator = Type.make()`. The out-of-tree case is not handled yet. When the parent instance is deallocated, the group is gone. The next life starts only when a new parent calls `make(context:)`.
    public static func make(context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, ParentScope> {
        if let existing = ParentRegistry.existing(as: ViewModel<Screen, ParentScope>.self) {
            return existing
        }
        return ParentRegistry.insert(ViewModel(factory: context))
    }

    /// Returns the live instance. Does not create one. A child stores `@Bindable private var coordinator = Type.make()`. The out-of-tree case is not handled yet.
    public static func make() -> ViewModel<Screen, ParentScope> {
        guard let existing = ParentRegistry.existing(as: ViewModel<Screen, ParentScope>.self) else {
            fatalError("Parent must call make(context:) first.")
        }
        return existing
    }
}

@MainActor
enum ParentRegistry {
    private static var entries: [ObjectIdentifier: ParentWeakBox] = [:]

    static func insert<Model: AnyObject>(_ model: Model) -> Model {
        entries[ObjectIdentifier(Model.self)] = ParentWeakBox(model)
        return model
    }

    static func existing<Model: AnyObject>(as _: Model.Type) -> Model? {
        entries[ObjectIdentifier(Model.self)]?.value as? Model
    }
}

private final class ParentWeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

extension ViewModel where Source == GlobalScope {
    /// Returns the instance at `id`. The context runs only when that id has none. Later calls return the stored instance and do not run the context. The instance stays until the app exits.
    public static func make(id: String, _ context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, GlobalScope> {
        if let existing = GlobalRegistry.existing(id: id, as: ViewModel<Screen, GlobalScope>.self) {
            return existing
        }
        return GlobalRegistry.insert(id: id, ViewModel(factory: context))
    }

    /// The instance already registered at `id`. Does not create one.
    public static func make(id: String) -> ViewModel<Screen, GlobalScope> {
        GlobalRegistry.model(id: id)
    }
}

extension ViewModel where Source == ShareScope {
    /// Returns the instance at `id`. The context runs only when that id has none. Later calls return the stored instance and do not run the context. The last owner releases it.
    public static func make(id: String, _ context: @autoclosure @escaping () -> ViewModelContext<Screen>) -> ViewModel<Screen, ShareScope> {
        if let existing = ShareRegistry.existing(id: id, as: ViewModel<Screen, ShareScope>.self) {
            return existing
        }
        return ShareRegistry.insert(id: id, ViewModel(factory: context))
    }

    /// The instance already registered at `id`. Does not create one.
    public static func make(id: String) -> ViewModel<Screen, ShareScope> {
        ShareRegistry.model(id: id)
    }
}
