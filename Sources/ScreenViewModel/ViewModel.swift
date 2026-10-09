import Foundation

/// Screen view model. The view calls `send`. A screen overrides `observable(action:cancel:)`.
@MainActor
public protocol ViewModel: AnyObject {
    associatedtype Action
    func send(_ action: Action)
    func observable(action: Action, cancel: Cancel) -> Effect<Action>
}
