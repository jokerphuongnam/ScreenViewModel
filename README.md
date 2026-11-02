# ScreenViewModel

A small view-model loop for a SwiftUI screen. The view calls `send`. The screen handles that action and returns one `Effect`.

Platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The screen loop uses Foundation and Observation. Parent, global, and share injection use SwiftUI. There is no AppKit or UIKit dependency.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "3.1.0")
```

```swift
import ScreenViewModel
```

`3.1.0` is the current stable release. `store.send` and model `send` are synchronous. The action, its state update, and the redirect chain finish before `send` returns. A `.task` only stores the `Task`. Inside that task, `send` stays async. `3.0.0` is the source and `make` API, and `send` there is still synchronous. `ViewModel` requires a source: `ViewState`, `ParentScope`, `GlobalScope`, or `ShareScope`. `1.0.0` is the first stable API. Tags named `0.x.x-betaXX` are pre-release and are not a stable API. Version numbers follow [Semantic Versioning](https://semver.org/): the third number is a small backward compatible fix, the second number adds backward compatible API, and the first number changes only when existing API breaks. `from: "1.0.0"` accepts every `1.x` release. `2.0.0` adds `.id(&)` and gives `.redirect` an id, so a `switch` that matched `.redirect(let action)` must match the id as well. `.redirect(action)` still builds.

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
                await send(.loaded("done"))
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

An effect gets its id the same way. The id is generated. Do not pass a string or other hand-made value, because two of those can collide.

```swift
var onNextID: EffectID?

return .onNext { save() }.id(&onNextID)
```

`onNextID` then holds that generated id. `model.cancel(onNextID!)` cancels it. The same `.id(&id)` works on `.onDisappear` and `.task`. `.redirect(.next).id(&id)` stores the next action the way `send(next, id: &id)` does, and `cancel` uses that id. `.none` stores nothing, so it has no id.

An enum case can be sent through the subscript. `model[.load]()` sends `.load`. `model[.load].id(&loadID)` and `model[.load]().id(&loadID)` store that effect under the id.

## State past one screen

A `ScreenModel` still owns its own fields. The app creates the objects below and passes them in. There is no hidden singleton. Mark the subclass `@Observable` so its fields notify views.

| API | Lifetime | What it is for |
| --- | --- | --- |
| `Type.make(id:_:)` / `Type.make(id:)` on `GlobalScope`. `globalState` and `@GlobalState` still exist. | From the first `make(id:_:)` for that id until the process ends | Global `make(id:_:)` stores the instance until the process ends. The same id always returns that same instance. A later `make(id:_:)` does not run the closure. `make(id:)` only reads it. Dropping every view does not destroy it. |
| `Type.make(id:_:)` / `Type.make(id:)` on `ShareScope`. `shareState` and `@ShareState` still exist. | While something points at that instance | Share uses a weak registry. `make(id:_:)` runs the closure only when that id has no live instance. When nothing points at the instance, it is destroyed. A later `make(id:_:)` for that same id runs the closure again and starts a new lifetime. `make(id:)` only reads a live instance. If the id is empty it fatalErrors, because that call has no closure to create one. The same id with another model type is another group. |
| `.parentState(_:)` | Until the parent instance is deallocated | The parent creates the one instance with `Type.make(context:)`; a later `make(context:)` while that instance is alive returns it and does not run the context. A child stores `@Bindable private var coordinator = Type.make()`. `make()` returns the live instance and does not create one. The out-of-tree case is not handled yet. When that instance is deallocated, the group is gone, the next life starts only when a new parent calls `make(context:)`, and there is no `@ParentState`. |
| `cache` in a ViewModel | The result stays for `gcTime` after the call | One API call for that key and result type. The same key with another result type is another cache. A fresh value does not call again. |

None of these retain the view. A view still disappears as usual. Storing a Global or Share `make` result only means that view starts using the model. `@GlobalState` and `@ShareState` still exist.

Every view that reads a model updates when a property it uses changes. That includes the view storing `globalState`, `shareState`, `Type.make(id:_:)`, or `Type.make(id:)`, `@GlobalState`, `@ShareState`, the owner that stores `make(context:)`, and the child that stores `@Bindable private var coordinator = Type.make()`. The out-of-tree case is not handled yet.

```swift
@State private var session = Type.make(id: "session", SessionLogic())
@State private var note = Type.make(id: "note", NoteLogic())
@Bindable private var coordinator = Type.make(context:)

var body: some View {
    VStack {
        Text(session.name)
        Text(note.text)
        ParentChild()
    }
    .parentState(coordinator)
}

struct GlobalReader: View {
    @State private var session = Type.make(id: "session")
    var body: some View { Text(session.name) }
}

struct ShareReader: View {
    @State private var note = Type.make(id: "note")
    var body: some View { Text(note.text) }
}

struct ParentChild: View {
    @Bindable private var coordinator = Type.make()
    var body: some View {
        Text(coordinator.title)
    }
}
```

Global `make(id:_:)` stores the instance until the process ends. The same id always returns that same instance. A later `make(id:_:)` does not run the closure. `make(id:)` only reads it. Dropping every view does not destroy it. Share uses a weak registry. `make(id:_:)` runs the closure only when that id has no live instance. When nothing points at the instance, it is destroyed. A later `make(id:_:)` for that same id runs the closure again and starts a new lifetime. `make(id:)` only reads a live instance. If the id is empty it fatalErrors, because that call has no closure to create one. `@GlobalState` and `@ShareState` still exist. They are not the `make` calls.

Call the API from the ViewModel. The view reads the fields the model stores.

```swift
case .load:
    loading = true
    return .task(.userInitiated) { send in
        do {
            let fact = try await cache(key: "fact", staleTime: .seconds(60)) {
                try await fetchFact()
            }
            await send(.loaded(fact))
        } catch {
            await send(.failed)
        }
    }
```

The cache does not compare the closure. It pairs the string key with the result type.

Same key and same result type are one cache and one in-flight request. A later load inside `staleTime` returns the stored value and does not call again. Default `staleTime` is zero. Default `gcTime` is five minutes.

Same key and a different result type are a second cache. This does not fail, and it does not replace the first cache.

```swift
let text = try await cache(key: "fact") { "A" } // String cache
let number = try await cache(key: "fact") { 1 } // Int cache, separate
```

Two `String` calls need two keys. `cache(key: "fact")` and `cache(key: "title")` stay apart even though both return `String`. Reusing `"fact"` for a second string API reads and writes the fact cache.

`shareState` and Share `make` use the same grouping rule. The same id and the same model type are one group. The same id and another model type are another group. Share uses a weak registry. `make(id:_:)` runs the closure only when that id has no live instance. When nothing points at the instance, it is destroyed. A later `make(id:_:)` for that same id runs the closure again and starts a new lifetime. `make(id:)` only reads a live instance. If the id is empty it fatalErrors, because that call has no closure to create one. `@ShareState(id: "abc")` still exists and reads only the type written on the property.

A value that only the view displays uses `cached(key:_:)` or `@CacheState(key:)`. That is not the place for an API call. `cached.data`, `isFetching`, and `refetch()` describe that display value.

The macOS example's state screen is `Examples/ScreenViewModelExample/StateExample.swift`.

## Effect

`observable` returns exactly one case.

| Case | What it does |
| --- | --- |
| `.none` | Stores nothing. Does not clear an `onDisappear` that is already stored, and does not cancel a running `.task`. |
| `.redirect(action)` | Runs that action next. Depth is capped at 16 extra steps. An action that always redirects to itself is observed 17 times. `.redirect(action).id(&id)` stores that next effect the way `send(action, id: &id)` does. |
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
| `1.0.0` | First stable API and the test suite. Pass an id with `send(_:id:)`, or send an enum case with `model[.load]()` |
| `1.0.1` | Tests split by behavior. No API change |
| `1.1.0` | `.parentState` and `@ParentState` |
| `1.2.0` | `shareState` and `@ShareState` |
| `1.3.0` | `globalState` and `@GlobalState`. The model stays until the app exits |
| `1.3.1` | Tests that a read of a shared model updates when that value changes |
| `1.4.0` | `cache(key:)` and `@CacheState`. The key is a string |
| `1.4.1` | Docs and the state example |
| `1.5.0` | The same cache key with another result type is another cache. The same share id with another model type is another group |
| `1.5.1` | This version list |
| `2.0.0` | `.id(&)` generates an id for `.onNext`, `.onDisappear`, `.task`, and the action `.redirect` runs next. `.none` has no id. A switch on `.redirect` now includes that id. `cached(key:)` can be called off the main actor. `cache(key:)` also has a synchronous overload whose fetch runs on the caller. `send` is still synchronous |
| `2.1.0` | `ViewModel<Screen, Source>` and `ViewModelContext` sit beside `ScreenModel`. `@ParentState` is still the property wrapper. `make(id:)` is not the Global or Share API yet |
| `3.0.0` | `ViewModel` requires a source: `ViewState`, `ParentScope`, `GlobalScope`, or `ShareScope`. The `@ParentState` wrapper is removed. `.parentState(_:)` stays. The owner calls `Type.make(context:)`. A later `make(context:)` while that instance is alive returns it and does not run the context. A child calls `Type.make()`, which returns that instance or `fatalError` if no parent has created one. Global and Share owners call `Type.make(id:_:)` and readers call `Type.make(id:)`. A Global id lives until the process ends. A Share id is released when nothing points at it, and the next `make(id:_:)` starts a new instance. `send` is still synchronous |
| `3.1.0` | `store.send` and model `send` are synchronous. The action, its state update, and the redirect chain finish before `send` returns. A `.task` effect only stores the `Task` and does not wait for the task body. Inside that task, `send` stays `async`: `await send` waits for that action and its redirect chain, and does not wait for a nested `.task` body |

## Context ViewModel (2.1)

A newer API that sits alongside `ScreenModel`, which stays unchanged.

```swift
enum Counter: ScreenContext {
    struct State: DefaultScreenState, Equatable { var count = 0; var name = "" }  // plain value
    enum Action { case increment, load(id: Int), loaded(String) }
}

final class CounterLogic: ViewModelContext<Counter> {
    let service: CounterService
    init(service: CounterService = .live) { self.service = service }

    override func observable(action: Counter.Action, state: inout Counter.State, cancel: EffectCancel) -> ActionEffect<Counter.Action> {
        switch action {
        case .increment: state.count += 1; return .none
        case .load(let id):
            return .task(id: "load") { send in await send(.loaded(await self.service.fetch(id))) }
        case .loaded(let name): state.name = name; return .none
        }
    }
}

struct CounterView: View {
    @State var model = ViewModel(context: CounterLogic())   // the context is built only once, on first use
    var body: some View {
        Button("\(model.count)") { model.send(.increment) }  // outside code sees State fields and send() only
    }
}
```

- `State` is a plain struct. Observation lives on `ViewModelContext` (which is `@Observable` and stores `state`) and on `ViewModel`. Each `send` writes the new value back once; if `State` is `Equatable`, an unchanged state notifies no one. Views re-render when the state changes, not per field.
- Two-way binding works like a normal `@Observable` model: `TextField("Name", text: $model.name)` with `@State var model` or `@Bindable var model`. A write updates `State` on the context, which refreshes every view reading it. Then `ViewModelContext.binding(changed:state:cancel:)` runs, so you can validate the value or return an effect:
  ```swift
  override func binding(changed keyPath: PartialKeyPath<Counter.State>, state: inout Counter.State, cancel: EffectCancel) -> ActionEffect<Counter.Action> {
      if keyPath == \Counter.State.name { return .task(id: "search") { send in /* debounce, fetch */ } }
      return .none
  }
  ```
  `model.binding(\.name, send: { .setName($0) })` is still there when an edit should become an Action instead.
- `ActionEffect`: `.none`, `.send`, `.task(priority:id:)` (running a task with the same id replaces the old one), `.cancel(id:)`, `.onDisappear`, `.merge`. All tasks are cancelled when the ViewModel is released.
- Testing: `let viewModel = ViewModel(context: CounterLogic(service: .fake))`, then `viewModel.send(.increment)`, then `XCTAssertEqual(viewModel.count, 1)`.
- Lifecycle with the new ViewModel:
  - Global owner: `Type.make(id: "session", SessionLogic())`. Reader: `Type.make(id: "session")`. Global `make(id:_:)` stores the instance until the process ends. The same id always returns that same instance. A later `make(id:_:)` does not run the closure. `make(id:)` only reads it. Dropping every view does not destroy it.
  - Share owner: `Type.make(id: "note", NoteLogic())`. Reader: `Type.make(id: "note")`. Share uses a weak registry. `make(id:_:)` runs the closure only when that id has no live instance. When nothing points at the instance, it is destroyed. A later `make(id:_:)` for that same id runs the closure again and starts a new lifetime. `make(id:)` only reads a live instance. If the id is empty it fatalErrors, because that call has no closure to create one. The same id with another model type is another group.
  - Parent: The parent creates the one instance with `Type.make(context:)`; a later `make(context:)` while that instance is alive returns it and does not run the context. A child stores `@Bindable private var coordinator = Type.make()`. `make()` returns the live instance and does not create one. The out-of-tree case is not handled yet. When that instance is deallocated, the group is gone, the next life starts only when a new parent calls `make(context:)`, and there is no `@ParentState`.
  - `cache(key:)` works inside `.task`
- Source break: the old `protocol ViewModel` is now `ScreenModelProtocol`, because the name is taken by the new class.
