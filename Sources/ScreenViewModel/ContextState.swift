import SwiftUI

/// `@GlobalState` for the context-based `ViewModel<Screen, GlobalScope>`. Reads the instance registered with `globalState(_:)`.
@MainActor
@propertyWrapper
public struct GlobalViewModel<Screen: ScreenContext>: DynamicProperty {
    public init() {}

    public var wrappedValue: ViewModel<Screen, GlobalScope> {
        GlobalRegistry.model(as: ViewModel<Screen, GlobalScope>.self)
    }

    public var projectedValue: Bindable<ViewModel<Screen, GlobalScope>> {
        Bindable(wrappedValue)
    }
}

/// `@ShareState` for the context-based `ViewModel<Screen, ShareScope>`. The default value is an autoclosure: it builds the model
/// only when `id` has none, and this screen holds the instance while it is alive.
@MainActor
@propertyWrapper
public struct ShareViewModel<Screen: ScreenContext>: DynamicProperty {
    private let id: String
    private let make: (() -> ViewModel<Screen, ShareScope>)?
    private let hold = Hold()

    public init(id: String) {
        self.id = id
        self.make = nil
    }

    public init(wrappedValue: @autoclosure @escaping () -> ViewModel<Screen, ShareScope>, id: String) {
        self.id = id
        self.make = wrappedValue
    }

    public var wrappedValue: ViewModel<Screen, ShareScope> {
        if let held = hold.value { return held }
        let model: ViewModel<Screen, ShareScope>
        if let existing = ShareRegistry.existing(id: id, as: ViewModel<Screen, ShareScope>.self) {
            model = existing
        } else if let make {
            model = ShareRegistry.insert(id: id, make())
        } else {
            model = ShareRegistry.model(id: id)
        }
        hold.value = model
        return model
    }

    public var projectedValue: Bindable<ViewModel<Screen, ShareScope>> {
        Bindable(wrappedValue)
    }

    private final class Hold {
        var value: ViewModel<Screen, ShareScope>?
    }
}
