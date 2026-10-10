import Foundation

/// ViewModels visible to a view and its descendants. A child scope sees its parent models. A sibling scope does not see the other sibling's model.
public struct ScreenScope {
    var models: [ObjectIdentifier: AnyObject] = [:]

    public init() {}

    public func setting<Model: AnyObject>(_ model: Model) -> ScreenScope {
        var copy = self
        copy.models[ObjectIdentifier(Model.self)] = model
        return copy
    }

    public func model<Model: AnyObject>(_: Model.Type = Model.self) -> Model? {
        models[ObjectIdentifier(Model.self)] as? Model
    }
}
