# ScreenViewModel

A small view-model loop for a SwiftUI screen. The view calls `send`. The screen handles that action and returns one `Effect`.

Platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The library uses Foundation and Observation only. There is no AppKit or UIKit dependency.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.0.0")
```

```swift
import ScreenViewModel
```

`1.0.0` is the first stable release. It includes the test suite. Earlier publishes were pre-release tags named `0.x.x-betaXX`. Those tags are not a stable API.

## Use it

Subclass `ScreenModel` and override `observable`. Hold the model in the view with `@State`. Call `disappear()` from the view's `onDisappear`, or a named effect stays alive until something cancels it. `ScreenAction` is the marker for an action enum.

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
        .onDisappear { model.disappear() }
}
```

`model.send(.load, id: &loadID)` writes a new `EffectID` into `loadID` when it is nil, then stores the effect under that id. The same variable reuses the id. Cancel it with `model.cancel(loadID!)`.

A static member of the action type can be sent through dynamic member lookup. `model.load` is `model.send(.load)` when `Action` has `static var load` or `static let load`. Chain `.id` when that effect needs a handle:

```swift
model.load
model.load.id(&loadID)
```

Swift builds that lookup as a key path to the static member. A key path cannot refer to an enum case, so `case load` still goes through `send`. The subscript returns the model so `.id(&id)` can move the effect just stored onto that id. Swift does not allow `@discardableResult` on a subscript, so a bare `model.load` warns that the result is unused. `.id` is `@discardableResult`.

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

The macOS example walks `.none`, `.redirect`, `.onNext`, `.onDisappear`, `.task`, and `cancel`:

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
