# ScreenViewModel

A small view-model loop for a SwiftUI screen. The view calls `send`. The screen handles that action and returns one `Effect`.

Platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The screen loop uses Foundation and Observation. Parent, global, and share injection use SwiftUI. There is no AppKit or UIKit dependency.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.0.0")
```

```swift
import ScreenViewModel
```

`1.0.0` is the first stable release. It includes the test suite. Earlier publishes were pre-release tags named `0.x.x-betaXX`. Those tags are not a stable API.

## Use it

Subclass `ScreenModel` and override `observable`. Hold the model in the view with `@State`. When that view releases the model, tasks are cancelled and stored cleanups run. Call `disappear()` only when the same model stays alive after the view is gone. `ScreenAction` is the marker for an action enum.

```swift
enum DemoAction: ScreenAction {
    case load
    case loaded(String)
}

@MainActor
@Observable
final class DemoModel: ScreenModel<DemoAction> {
    var fact = ""

    override func observable(action: DemoAction, cancel: Cancel) -> Effect<DemoAction> {
        switch action {
        case .load:
            return .task { send in
                send(.loaded("done"))
            }
        case .loaded(let text):
            fact = text
            return .none
        }
    }
}
```

```swift
@State private var model = DemoModel()
@State private var loadID: EffectID?

var body: some View {
    Button("Load") { model.send(.load, id: &loadID) }
}
```

`model.send(.load, id: &loadID)` writes a new `EffectID` into `loadID` when it is nil, then stores the effect under that id. The same variable reuses the id. Cancel it with `model.cancel(loadID!)`.

An enum case can be sent through the subscript. `model[.load]()` sends `.load`. `model[.load].id(&loadID)` and `model[.load]().id(&loadID)` store that effect under the id.

## State past one screen

A `ScreenModel` still owns its own fields. The app creates the objects below and passes them in. There is no hidden singleton. Mark the subclass `@Observable` so its fields notify views.

| API | Lifetime | What it is for |
| --- | --- | --- |
| `globalState` / `@GlobalState` | From the first `globalState` until the app exits | One ViewModel for that type. A screen reads `@GlobalState`. Dropping a screen does not drop the model. |
| `shareState` / `@ShareState` | While at least one joined screen is alive | One ViewModel for that id. `shareState(id:_:)` and `@ShareState(id:) = Model()` join the same group. The last screen to disappear releases the model. |
| `.parentState(_:)` / `@ParentState` | The parent view's model | Like `environmentObject`. Descendants read it. Views outside the modifier do not. Siblings do not see each other's models. |
| `cache` in a ViewModel | The result stays for `gcTime` after the call | One API call for that key. A ViewModel `await`s it. The same key joins the call already running, and a fresh value does not call again. |

None of these retain the view. A view still disappears as usual. `shareState` and `globalState` only mean that view starts using the model.

Every view that reads a model updates when a property it uses changes. That includes the view storing `globalState` or `shareState`, `@GlobalState`, `@ShareState`, the parent that passes `.parentState`, and `@ParentState`.

```swift
@State private var session = globalState(SessionModel())
@State private var note = shareState(id: "note", NoteModel())
@State private var wizard = WizardModel()

var body: some View {
    VStack {
        Text(session.name)
        Text(note.text)
        ParentChild()
    }
    .parentState(wizard)
}

struct GlobalReader: View {
    @GlobalState private var session: SessionModel
    var body: some View { Text(session.name) }
}

struct ShareReader: View {
    @ShareState(id: "note") private var note: NoteModel
    var body: some View { Text(note.text) }
}

struct ParentChild: View {
    @ParentState private var wizard: WizardModel
    var body: some View { Text(wizard.title) }
}
```

`@ShareState(id:) = NoteModel()` creates the instance only when that id has none yet. `@GlobalState` does not create one. Call `globalState` first.

Call the API from the ViewModel. The view reads the fields the model stores.

```swift
case .load:
    loading = true
    return .task(.userInitiated) { send in
        do {
            let fact = try await cache(key: "fact", staleTime: .seconds(60)) {
                try await fetchFact()
            }
            send(.loaded(fact))
        } catch {
            send(.failed)
        }
    }
```

Two screens that load the same key share one request. A later load inside `staleTime` gets the cached value and does not call the API. Default `staleTime` is zero. Default `gcTime` is five minutes.

A value that only the view displays uses `cached(key:_:)` or `@CacheState(key:)`. That is not the place for an API call. `cached.data`, `isFetching`, and `refetch()` describe that display value.

The macOS example's state screen is `Examples/ScreenViewModelExample/StateExample.swift`.

## Effect

`observable` returns exactly one case.

| Case | What it does |
| --- | --- |
| `.none` | Stores nothing. Does not clear an `onDisappear` that is already stored, and does not cancel a running `.task`. |
| `.redirect(action)` | Runs that action next. Depth is capped at 16 extra steps. An action that always redirects to itself is observed 17 times. |
| `.onNext` | Without an id, runs at the start of the next `send`, and also when the model is released. With an id, waits until `cancel(id)` or `disappear()`. |
| `.onDisappear` | Without an id, runs once from `disappear()`. With an id, `cancel(id)` runs it early. |
| `.task` | Async work, like SwiftUI `.task`. The closure receives `send` and must change state by sending an action. Default priority is `.userInitiated`. |

A new effect with the same id replaces the previous one. Replacing runs the old `onNext` or `onDisappear` immediately, and cancels the old `.task`.

Anonymous effects share one slot per kind. A new anonymous `.task` cancels the previous anonymous task. A named effect stays until `cancel(id)`, the same id is used again, `disappear()`, or the model is released.

`cancel` inside `observable` drops the effect that call is about to return, so it is never stored. `cancel(id)` drops the effect already stored under that id. `disappear()` cancels every task and runs every stored cleanup.

## Example and tests

The macOS example walks `.none`, `.redirect`, `.onNext`, `.onDisappear`, `.task`, and `cancel`, then a second screen for global, share, parent, and cache:

```sh
swift run ScreenViewModelExample
```

Tests live in `Sources/Tests`. Run them with `swift test`.

## Versions

| Tag | Contents |
| --- | --- |
| `0.1.0-beta01` | `send`, `Effect`, and task cancellation |
| `0.1.1-beta02` | Example executable |
| `0.2.0-beta03` | watchOS, tvOS, and visionOS |
| `0.3.0-beta04` | `cancel` passed into `observable` |
| `0.4.0-beta05` | `cancel` by id |
| `0.5.0-beta06` | Call-site id |
| `0.6.0-beta07` | Sources split by type |
| `1.0.0` | Stable API and the test suite. Pass an id with `send(_:id:)` |
