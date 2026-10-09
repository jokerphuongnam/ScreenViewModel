# ScreenViewModel

A small screen view-model loop for SwiftUI. The view calls `send`. The screen returns an `Effect`.

Supported platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The library depends only on Foundation and Observation.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.3.0")
```

```swift
import ScreenViewModel
```

`cancel()` drops the effect this call returned. `cancel(id)` drops the effect stored with that id. A new effect with the same id replaces the old one. The example's Stop button calls `cancel("load")`.

Run the example on macOS. It walks through `.none`, `.redirect`, `.onNext`, `.onDisappear`, `.task`, and `cancel`:

```sh
swift run ScreenViewModelExample
```
