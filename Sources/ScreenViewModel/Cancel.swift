import Foundation

/// Cancels effects returned from `observable`.
///
/// `cancel()` cancels the effect this call returned. `cancel(id)` cancels the effect stored under that id.
public struct Cancel {
    let ticket: EffectTicket
    let effects: ViewModelEffects

    public func callAsFunction() {
        effects.cancel(ticket)
    }

    public func callAsFunction(_ id: some Hashable) {
        effects.cancel(id: id)
    }
}
