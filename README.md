# swift-witnesses

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)

Macro-generated protocol witnesses for dependency injection — `@Witness` turns a struct of closures into a callable test double that a task-local context resolves and overrides per live, preview, or test mode.

---

## Key Features

- **Macro-generated witnesses** — `@Witness` synthesizes the initializer, labeled call methods, a `Calls` enum, an `observe` accessor, and an `unimplemented()` factory from a struct of closure properties.
- **Scoped, task-local overrides** — `withWitnesses` and `Witness.Context.with` replace witnesses for one `operation:` scope with no globals and no leakage to sibling tasks.
- **Live / preview / test modes** — a `Witness.Key` resolves through the `liveValue → previewValue → testValue` chain selected by the current context mode.
- **Typed throws preserved** — the scope helpers forward the operation's typed error unchanged, so `throws(E)` survives the override boundary.
- **Ownership-aware closures** — witness closures carry `borrowing`, `consuming`, and `inout` parameters, and keys can vend `~Copyable` values.
- **Total by default** — `unimplemented()` returns a witness whose operations throw `Witness.Unimplemented.Error` with source location instead of trapping.

---

## Quick Start

A `@Witness` struct of closures replaces a hand-written protocol plus its live and stub conforming types. Conform it to `Witness.Key` to supply a live implementation, then resolve and override it through the task-local `Witness.Context`:

```swift
import Witnesses

@Witness
struct Weather: Sendable {
    var forecast: @Sendable (_ city: String) async throws -> Double
}

extension Weather: Witness.Key {
    static var liveValue: Weather {
        Weather(forecast: { city in /* real network lookup */ 21.5 })
    }
}

// Production code resolves the live witness from the task-local context:
let live = Witness.Context.current[Weather.self]
let real = try await live.forecast(city: "Amsterdam")   // 21.5

// A test swaps in a stub for one scope — no protocol, no global, no leakage:
let stubbed = try await withWitnesses { values in
    values[Weather.self] = Weather(forecast: { _ in 30.0 })
} operation: {
    try await Witness.Context.current[Weather.self].forecast(city: "Amsterdam")
}                                                       // 30.0
```

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/swift-foundations/swift-witnesses.git", branch: "main")
]
```

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "Witnesses", package: "swift-witnesses")
    ]
)
```

Requires Swift 6.3.1 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26.

---

## Architecture

Three library products built on the `Witnesses Macros Implementation` compiler plugin.

| Product | When to import |
|---------|----------------|
| `Witnesses` | Application and library code — the `@Witness` / `@WitnessScope` / `@WitnessAccessors` macros plus the task-local `Witness.Context`, `Witness.Values`, `Witness.Key`, and `Witness.Unimplemented` runtime. The default import. |
| `Witnesses Macros` | Lower-level consumers that want the `@Witness` macro family and the witness protocol surface without the `Witness.Context` runtime. |
| `Witnesses Test Support` | Test targets — re-exports `Witnesses` for test consumers. |

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE](LICENSE.md).
