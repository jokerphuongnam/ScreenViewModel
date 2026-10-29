import Foundation

/// The old screen view model contract, adopted by `ScreenModel`. The view calls `send`. A screen overrides `observable(action:cancel:)`.
/// It was named `ViewModel` before 2.1.0; that name now belongs to the final `ViewModel<Screen>` class.
@MainActor
public protocol ScreenModelProtocol: AnyObject {
    associatedtype Action
    func send(_ action: Action)
    func observable(action: Action, cancel: Cancel) -> Effect<Action>
}
