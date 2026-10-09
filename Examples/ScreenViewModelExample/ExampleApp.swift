import Observation
import ScreenViewModel
import SwiftUI

enum DemoAction {
    case appear
    case addOne
    case addOneThenOne
    case addTwo
    case arm
    case load
    case stop
    case loaded(Int)
}

@MainActor
@Observable
final class DemoModel: ScreenModel<DemoAction> {
    var count = 0
    var loading = false
    var fact = "No task yet."
    var trace: [String] = []
    private var loadID = 0
    private var stopLoad: (() -> Void)?

    override func observable(action: DemoAction, cancel: @escaping () -> Void) -> Effect<DemoAction> {
        switch action {
        case .appear:
            note("appear → .onDisappear")
            return .onDisappear { [weak self] in
                self?.note("view disappeared → .onDisappear ran")
            }

        case .addOne:
            count += 1
            note("addOne → .none, count \(count)")
            return .none

        case .addTwo:
            note("addTwo → .redirect(.addOneThenOne)")
            return .redirect(.addOneThenOne)

        case .addOneThenOne:
            count += 1
            note("addOneThenOne → .redirect(.addOne)")
            return .redirect(.addOne)

        case .arm:
            note("arm → .onNext. The next action runs this cleanup first.")
            return .onNext { [weak self] in
                self?.note("next action → .onNext ran")
            }

        case .load:
            loadID += 1
            let id = loadID
            loading = true
            fact = "Task \(id) is running."
            stopLoad = cancel
            note("load → .task \(id). Stop calls cancel() for this action.")
            return .task(.userInitiated) { send in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                send(.loaded(id))
            }

        case .stop:
            stopLoad?()
            stopLoad = nil
            loading = false
            fact = "Cancelled."
            note("stop → cancel() for the load action")
            return .none

        case .loaded(let id):
            loading = false
            fact = "Task \(id) finished."
            note("loaded → .none, task \(id) finished")
            return .none
        }
    }

    private func note(_ line: String) {
        trace.append(line)
    }
}

@main
struct ExampleApp: App {
    @State private var model = DemoModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Trace stays here when the demo screen closes.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    TraceList(lines: model.trace)
                    NavigationLink("Open demo screen") {
                        DemoScreen(model: model)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(minWidth: 520, minHeight: 420)
                .navigationTitle("ScreenViewModel")
            }
        }
    }
}

struct DemoScreen: View {
    @Bindable var model: DemoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Count \(model.count)")
                .font(.title2)
            Text(model.fact)
                .foregroundStyle(model.loading ? .secondary : .primary)
            HStack {
                Button("Add one  .none") { model.send(.addOne) }
                Button("Add two  .redirect") { model.send(.addTwo) }
                Button("Arm  .onNext") { model.send(.arm) }
                Button("Load  .task") { model.send(.load) }
                    .disabled(model.loading)
                Button("Stop  cancel()") { model.send(.stop) }
                    .disabled(!model.loading)
            }
            TraceList(lines: model.trace)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Every effect")
        .onAppear { model.send(.appear) }
        .onDisappear { model.disappear() }
    }
}

private struct TraceList: View {
    let lines: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if lines.isEmpty {
                    Text("No actions yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
