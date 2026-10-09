# ScreenViewModel

A small screen view-model loop for SwiftUI. The view calls `send`. The screen returns an `Effect`.

Supported platforms: macOS 14, iOS 17, watchOS 10, tvOS 17, and visionOS 1. The library depends only on Foundation and Observation.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.2.0")
```

```swift
import ScreenViewModel
```

`observable(action:cancel:)` receives a `cancel` closure for the effect that call returns. Calling it cancels `.task`, and runs `.onNext` or `.onDisappear` once. The example's Stop button keeps that closure and calls it.

Run the example on macOS. It walks through `.none`, `.redirect`, `.onNext`, `.onDisappear`, `.task`, and `cancel`:

```sh
swift run ScreenViewModelExample
```
