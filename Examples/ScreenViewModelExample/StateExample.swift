import ScreenViewModel
import SwiftUI

enum SessionAction: ScreenAction {
    case rename(String)
}

@MainActor
@Observable
final class SessionModel: ScreenModel<SessionAction> {
    var name = "Ada"

    override func observable(action: SessionAction, cancel: Cancel) -> Effect<SessionAction> {
        if case .rename(let name) = action {
            self.name = name
        }
        return .none
    }
}

enum NoteAction: ScreenAction {
    case append(String)
}

@MainActor
@Observable
final class NoteModel: ScreenModel<NoteAction> {
    var text = "Shared note"

    override func observable(action: NoteAction, cancel: Cancel) -> Effect<NoteAction> {
        if case .append(let suffix) = action {
            text += suffix
        }
        return .none
    }
}

enum WizardScreen: ScreenContext {
    struct State: DefaultScreenState, Equatable { var title = "Wizard" }
    enum Action { case retitle(String) }
}

final class WizardLogic: ViewModelContext<WizardScreen> {
    override func observable(action: WizardScreen.Action, state: inout WizardScreen.State, cancel: EffectCancel) -> ActionEffect<WizardScreen.Action> {
        if case .retitle(let title) = action {
            state.title = title
        }
        return .none
    }
}

typealias WizardModel = ViewModel<WizardScreen, ParentScope>

enum DeskScreen: ScreenContext {
    struct State: DefaultScreenState, Equatable { var name = "Desk" }
    enum Action { case rename(String) }
}

final class DeskLogic: ViewModelContext<DeskScreen> {
    override func observable(action: DeskScreen.Action, state: inout DeskScreen.State, cancel: EffectCancel) -> ActionEffect<DeskScreen.Action> {
        if case .rename(let name) = action { state.name = name }
        return .none
    }
}

typealias DeskModel = ViewModel<DeskScreen, GlobalScope>
typealias SharedDeskModel = ViewModel<DeskScreen, ShareScope>

enum FactAction: ScreenAction {
    case load
    case loaded(String)
    case failed
}

@MainActor
@Observable
final class FactModel: ScreenModel<FactAction> {
    var fact = ""
    var loading = false

    override func observable(action: FactAction, cancel: Cancel) -> Effect<FactAction> {
        switch action {
        case .load:
            loading = true
            return .task(.userInitiated) { send in
                do {
                    let fact = try await cache(key: "fact", staleTime: .seconds(60)) {
                        "A prime"
                    }
                    send(.loaded(fact))
                } catch {
                    send(.failed)
                }
            }
        case .loaded(let fact):
            loading = false
            self.fact = fact
            return .none
        case .failed:
            loading = false
            fact = "Failed"
            return .none
        }
    }
}

struct StateScreen: View {
    @State private var session = globalState(SessionModel())
    @State private var note = shareState(id: "note", NoteModel())
    @Bindable private var wizard = WizardModel.make(context: WizardLogic())
    @Bindable private var desk = DeskModel.make(id: "desk", DeskLogic())
    @Bindable private var sharedDesk = SharedDeskModel.make(id: "desk", DeskLogic())
    @State private var facts = FactModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Global  \(session.name)")
            Button("Rename global") { session[.rename("Grace")]() }
            GlobalReader()

            Text("Share  \(note.text)")
            Button("Append share") { note[.append(" +")]() }
            ShareReader()

            Text("Global view  \(desk.name)")
            GlobalDeskReader()
            Text("Share view  \(sharedDesk.name)")
            ShareDeskReader()

            Text("Parent  \(wizard.title)")
            VStack(alignment: .leading) {
                ParentChild()
            }
            .parentState(wizard)

            Text("Cache  \(facts.loading ? "loading" : facts.fact)")
            Button("Load from ViewModel") { facts[.load]() }
            Button("Load again") { facts[.load]() }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("State")
    }
}

private struct GlobalReader: View {
    @GlobalState private var session: SessionModel

    var body: some View {
        Text("Global reader  \(session.name)")
            .foregroundStyle(.secondary)
    }
}

private struct ShareReader: View {
    @ShareState(id: "note") private var note: NoteModel

    var body: some View {
        Text("Share reader  \(note.text)")
            .foregroundStyle(.secondary)
    }
}

private struct GlobalDeskReader: View {
    @Bindable private var desk = DeskModel.make(id: "desk")

    var body: some View {
        Text("Global view reader  \(desk.name)")
            .foregroundStyle(.secondary)
    }
}

private struct ShareDeskReader: View {
    @Bindable private var desk = SharedDeskModel.make(id: "desk")

    var body: some View {
        Text("Share view reader  \(desk.name)")
            .foregroundStyle(.secondary)
    }
}

private struct ParentChild: View {
    @Bindable private var wizard = WizardModel.make()

    var body: some View {
        VStack(alignment: .leading) {
            Text("Child  \(wizard.title)")
                .foregroundStyle(.secondary)
            Button("Retitle from child") { wizard.send(.retitle("Renamed")) }
        }
    }
}


