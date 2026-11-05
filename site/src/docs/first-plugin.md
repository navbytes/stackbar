---
title: Your first plugin
description: Write, build and check a Stackbar plugin in one Swift file, then put it in your menu bar and palette.
group: Build plugins
order: 1
---

A plugin is one `.swift` file that imports StackbarKit. You need Xcode 26 or
the Command Line Tools (`xcode-select --install`).

## Scaffold it

```sh
stackbarctl new Hello.swift --name "Hello"
```

Open the file and replace it with this:

```swift
import StackbarKit
import Foundation

@main
final class Hello: StackbarPlugin {
    static let manifest = Manifest(
        id: "dev.example.hello",
        name: "Hello",
        surfaces: [.menuBar, .panel],
        triggers: [.launch, .every(.seconds(1))]
    )

    var now = Date()
    @Stored("count") var count = 0      // kept across restarts

    func refresh() async throws { now = Date() }

    var menuBar: ViewContent {
        Label(now.formatted(date: .omitted, time: .shortened), symbol: "clock")
    }

    var panel: ViewContent {
        Text("Clicked \(count) times").style(.headline)
        Button("Click", symbol: "hand.tap") { self.count += 1 }
    }
}
```

State is plain properties. `refresh()` runs when a trigger fires; button
closures run on a click. Stackbar re-renders after each and sends only what
changed.

## Check it without the app

```sh
stackbarctl build Hello.swift                     # compiler errors point at your file
stackbarctl render Hello.swift --surface panel    # the panel as text, with action ids
stackbarctl render Hello.swift --event button/Click
```

`render` runs the plugin in the same sandbox as the app, so a missing
capability fails here the same way it would there.

## Run it

Copy the file into the plugins folder (Settings › General › Plugins folder).
Stackbar builds it in a few seconds and it appears in the menu bar.

## Add a palette command

Add this to the class, and **Say Hello** shows up when you type `hello`:

```swift
var commands: [Command] {
    Command("hello", title: "Say Hello", symbol: "hand.wave") { _ in
        .message("Hello!")
    }
}
```

## Next

- The [plugin reference](/docs/authoring/): views, commands, triggers,
  capabilities and host services.
- [Publish it to the Store](https://github.com/navbytes/stackbar-plugins/blob/main/CONTRIBUTING.md).
