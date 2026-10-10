import Foundation

final class EffectTicket {
    var cancelled = false
}

final class EffectSlot {
    let ticket: EffectTicket
    var onNext: (() -> Void)?
    var onDisappear: (() -> Void)?
    var task: Task<Void, Never>?

    init(ticket: EffectTicket) {
        self.ticket = ticket
    }

    func finish() {
        task?.cancel()
        task = nil
        let next = onNext
        let gone = onDisappear
        onNext = nil
        onDisappear = nil
        next?()
        gone?()
    }
}

/// Holds anonymous effects and effects stored under an id.
final class ViewModelEffects {
    private var finished = false
    var anonymousOnNext: (() -> Void)?
    var anonymousOnNextTicket: EffectTicket?
    var anonymousOnDisappear: (() -> Void)?
    var anonymousOnDisappearTicket: EffectTicket?
    var anonymousTask: Task<Void, Never>?
    var anonymousTaskTicket: EffectTicket?
    var named: [AnyHashable: EffectSlot] = [:]

    func fireAnonymousOnNext() {
        let cleanup = anonymousOnNext
        anonymousOnNext = nil
        anonymousOnNextTicket = nil
        cleanup?()
    }

    func store(ticket: EffectTicket, id: AnyHashable?, onNext: @escaping () -> Void) {
        if let id {
            replaceNamed(id: id, ticket: ticket).onNext = onNext
        } else {
            fireAnonymousOnNext()
            anonymousOnNext = onNext
            anonymousOnNextTicket = ticket
        }
    }

    func store(ticket: EffectTicket, id: AnyHashable?, onDisappear: @escaping () -> Void) {
        if let id {
            replaceNamed(id: id, ticket: ticket).onDisappear = onDisappear
        } else {
            anonymousOnDisappear = onDisappear
            anonymousOnDisappearTicket = ticket
        }
    }

    func store(ticket: EffectTicket, id: AnyHashable?, task: Task<Void, Never>) {
        if let id {
            let slot = replaceNamed(id: id, ticket: ticket)
            slot.task?.cancel()
            slot.task = task
        } else {
            anonymousTask?.cancel()
            anonymousTask = task
            anonymousTaskTicket = ticket
        }
    }

    func cancel(_ ticket: EffectTicket) {
        ticket.cancelled = true
        if anonymousOnNextTicket === ticket {
            fireAnonymousOnNext()
        }
        if anonymousOnDisappearTicket === ticket {
            let cleanup = anonymousOnDisappear
            anonymousOnDisappear = nil
            anonymousOnDisappearTicket = nil
            cleanup?()
        }
        if anonymousTaskTicket === ticket {
            anonymousTask?.cancel()
            anonymousTask = nil
            anonymousTaskTicket = nil
        }
        let keys = named.filter { $0.value.ticket === ticket }.map(\.key)
        for key in keys {
            named.removeValue(forKey: key)?.finish()
        }
    }

    func cancel(id: some Hashable) {
        named.removeValue(forKey: AnyHashable(id))?.finish()
    }

    func cancelAll() {
        guard !finished else { return }
        finished = true
        fireAnonymousOnNext()
        let disappear = anonymousOnDisappear
        anonymousOnDisappear = nil
        anonymousOnDisappearTicket = nil
        anonymousTask?.cancel()
        anonymousTask = nil
        anonymousTaskTicket = nil
        let slots = named.values
        named.removeAll()
        for slot in slots { slot.finish() }
        disappear?()
    }

    private func replaceNamed(id: AnyHashable, ticket: EffectTicket) -> EffectSlot {
        named.removeValue(forKey: id)?.finish()
        let slot = EffectSlot(ticket: ticket)
        named[id] = slot
        return slot
    }

    deinit {
        cancelAll()
    }
}
