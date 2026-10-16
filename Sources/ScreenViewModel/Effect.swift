import Foundation

/// One follow-up from an action. `send` performs the case that `observable` returns.
public enum Effect<Action> {
    case none
    /// Run this action after the current one. The previous anonymous `onNext` has already run.
    /// An id from `.id(&)` is the id of that next action, the same way `send(next, id:)` stores its effect.
    case redirect(Action, id: EffectID? = nil)
    /// Without an id, runs when the next action arrives. With an id, runs when that id is cancelled or the view disappears.
    case onNext(id: AnyHashable? = nil, () -> Void)
    /// Without an id, runs once when the view disappears. A later `.none` does not clear it.
    /// With an id, `cancel(id)` runs it early.
    case onDisappear(id: AnyHashable? = nil, () -> Void)
    /// Async work, like SwiftUI `.task`. The same id replaces the previous task. Disappear cancels it too.
    case task(TaskPriority, id: AnyHashable? = nil, (_ send: (Action) -> Void) async -> Void)
}

extension Effect {
    /// Writes a generated `EffectID` into `slot` when it is nil.
    ///
    /// `.onNext { save() }.id(&onNextID)`
    /// `.onDisappear { stop() }.id(&watchID)`
    /// `.task { send in }.id(&taskID)`
    /// `.redirect(.next).id(&redirectID)` stores the next action the way `send(next, id: &redirectID)` does.
    ///
    /// `.none` stores nothing, so it leaves `slot` untouched. The same variable keeps the same id. Cancel with `model.cancel(onNextID!)`.
    public func id(_ slot: inout EffectID?) -> Effect<Action> {
        switch self {
        case .none:
            return .none
        case .redirect(let action, _):
            let resolved = slot ?? EffectID()
            slot = resolved
            return .redirect(action, id: resolved)
        case .onNext(_, let action):
            let resolved = slot ?? EffectID()
            slot = resolved
            return .onNext(id: resolved.raw, action)
        case .onDisappear(_, let action):
            let resolved = slot ?? EffectID()
            slot = resolved
            return .onDisappear(id: resolved.raw, action)
        case .task(let priority, _, let work):
            let resolved = slot ?? EffectID()
            slot = resolved
            return .task(priority, id: resolved.raw, work)
        }
    }
}
