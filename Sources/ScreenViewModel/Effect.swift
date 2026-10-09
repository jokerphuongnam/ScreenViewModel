import Foundation

/// One follow-up from an action. `send` performs the case that `observable` returns.
public enum Effect<Action> {
    case none
    /// Run this action after the current one. The previous anonymous `onNext` has already run.
    case redirect(Action)
    /// Without an id, runs when the next action arrives. With an id, runs when that id is cancelled or the view disappears.
    case onNext(id: AnyHashable? = nil, () -> Void)
    /// Without an id, runs once when the view disappears. A later `.none` does not clear it.
    /// With an id, `cancel(id)` runs it early.
    case onDisappear(id: AnyHashable? = nil, () -> Void)
    /// Async work, like SwiftUI `.task`. The same id replaces the previous task. Disappear cancels it too.
    case task(TaskPriority, id: AnyHashable? = nil, (_ send: (Action) -> Void) async -> Void)
}
