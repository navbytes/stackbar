# Tasks

One pull request each, in this order. Gate: `swift build && swift test`.

- [x] 1 `JSONFile` in HostCore; the stores read and write through it; tests pin the file formats
- [x] 2 `HostServices.handle`: one open path, one notification check, one notes cut; `RateLimiter` in its own file
- [x] 3 `SystemServices.swift` split into the protocol, `SimulatedSystem` and `ClipboardImageStore`
- [x] 4 `stackbarctl`: `main.swift` split into a file per group of commands
