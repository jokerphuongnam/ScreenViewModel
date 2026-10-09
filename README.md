# ScreenViewModel

A small screen view-model loop for SwiftUI. The view calls `send`. The screen returns an `Effect`.

Supported platforms: macOS 14 and iOS 17.

```swift
.package(url: "https://github.com/jokerphuongnam/ScreenViewModel", from: "1.0.0")
```

```swift
import ScreenViewModel
```

Run the example on macOS. It walks through `.none`, `.redirect`, `.onNext`, `.onDisappear`, and `.task`:

```sh
swift run ScreenViewModelExample
```
