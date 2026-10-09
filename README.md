# ScreenViewModel

A small screen view-model loop for SwiftUI. The view calls `send`. The screen returns an `Effect`.

Supported platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The library depends only on Foundation and Observation.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.4.0")
```

```swift
import ScreenViewModel
```

Conform an action enum to `ScreenAction`. Passing an id means that observer can be cancelled later. The id is written back when it was nil.

```swift
var loadID: EffectID?
model.send(DemoAction.load.id(&loadID))
model.cancel(loadID!)
```

Run the example on macOS. It walks through `.none`, `.redirect`, `.onNext`, `.onDisappear`, `.task`, and `cancel`:

```sh
swift run ScreenViewModelExample
```
