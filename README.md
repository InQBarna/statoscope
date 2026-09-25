# ``Statoscope``

A small library to handle iOS application state, focused in simplicity, testability and scalability.

## Overview

Statoscope enables the app developer to focus on the overall design of the app's state, providing helpers for testing, dependency injection and composition of state scopes.

* **State management**

    State and mutation of state using synchronous events is implemented by the Store with a single entry point using `When` events.

* **Effects**

    All asynchronous effects are handled by the library using the EffectsHandler, enabling effects status check and cancellation.

* **Scopes**

    The Statoscope is the minimum implementation for a piece of state, handles State, mutation and Effects. Scopes can be linked together as a dependency tree — via `@SubState`/`@SuperState` for the `@Reducer` pattern below, or the Superscope/Subscope property wrappers for the classic pattern

* **Testing**

    The TestPlan helper object allows Flow tests of the whole app's production code setup, enabling Acceptance As Code, specially if state properties and When events are properly named

* **Dependency injection**

    Injectable protocol and Injected property wrappers, in conjunction with the Scope linkages allow a multi-level dependency injection such as the one accomplished by SwiftUI.

Statoscope ships two patterns for a scope's state: **`@Reducer`** (below) is recommended for new features. **Statostore** — a class with `@Published` properties — is the easy migration path for bringing an existing ViewModel-shaped screen into Statoscope; see [README-Statostore.md](README-Statostore.md).

## Installation

The library is bundled as a Swift Package manager

  1. Add the SPM package with url "https://github.com/InQBarna/statoscope.git"
  2. Add the **Statoscope** library to your *app* target
  3. Add **StatoscopeTesting** library to your *test* target

## Usage

### Basic (State + When + Test)

Design a feature by declaring the State and When. Then Declare the acceptance criteria in your tests, see the example below. The `@Reducer` macro eliminates boilerplate by generating the store class for you — just annotate a plain struct with `@Reducer` and define a nested `State`, `When`, and a static `update` function:

```swift
@Reducer
struct Counter {
    struct State {
        var viewDisplaysTotalCount: Int = 0
    }

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount += 1
        case .userTappedDecrementButton:
            state.viewDisplaysTotalCount = max(0, state.viewDisplaysTotalCount - 1)
        }
    }
}
```

The macro generates `Counter.Store` — a fully functional `Statostore, ObservableObject`. Tests use the same fluent API:

```swift
try Counter.Store.GIVEN {
    Counter.Store(initialState: Counter.State())
}
.THEN(\.state.viewDisplaysTotalCount, equals: 0)
.WHEN(.userTappedIncrementButton)
.THEN(\.state.viewDisplaysTotalCount, equals: 1)
.runTest()
```

Key differences from the traditional pattern:
- `update` is a **static** function — no `self`, purely functional
- State is always a **single struct** accessed via `store.state`
- No class boilerplate to write — the macro generates `Counter.Store`

### Basic with effects

(Side) **Effect**s are triggered tasks that may finish affecting your app state. That's why effects are expressed in the Statoscope library with an ending *When* case. In the following example the Counter feature is synchronized with a service by using a network api call: an *Effect*. There are many user experiences to achieve this feature, hopefully the Test (Acceptance as code) in the following snippets cleanly state

```swift
@Reducer
struct Counter {
    struct State {
        var viewDisplaysTotalCount: Int = 0
        var viewDisplaysError: String?
        var viewShowsLoadingAndDisablesButtons: Bool = false
    }

    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(Result<DTO, Error>)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws { /* ... */ }
}
```

```swift
final class ReducerExample2: XCTestCase {
    func testCounterExample3UserFlow() throws {
        try Counter.Store.GIVEN {
            Counter.Store(initialState: Counter.State())
        }
        .THEN(\.state.viewDisplaysTotalCount, equals: 0)
        .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.state.viewDisplaysTotalCount, equals: 1)
        .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: true)
        .FORK(.networkPostCompleted(.failure(CancellationError()))) { sut in
            try sut
                .THEN(\.state.viewDisplaysTotalCount, equals: 1)
                .THEN(\.state.viewDisplaysError, equals: "The operation couldn’t be completed. (Swift.CancellationError error 1.)")
                .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
        }
        .WHEN(.networkPostCompleted(.success(DTO(count: 1))))
        .THEN(\.state.viewDisplaysTotalCount, equals: 1)
        .THEN(\.state.viewShowsLoadingAndDisablesButtons, equals: false)
        .runTest()
    }
}
```

The code above can be interpreted as the "design" of the feature. Stating the different *State*s, *When*s and the user experience of the app. See below the implementation details

```swift

struct DTO: Codable {
    let count: Int
}

struct NetworkEffect<Response: Decodable>: Effect {
    let request: URLRequest
    func runEffect() async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    }
}

@Reducer
struct Counter {
    /* ... */

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount += 1
            try triggerNetworkUpdate(state: &state, effectsState: &effectsState)
        case .userTappedDecrementButton:
            guard state.viewDisplaysTotalCount > 0 else {
                return
            }
            state.viewDisplaysTotalCount -= 1
            try triggerNetworkUpdate(state: &state, effectsState: &effectsState)
        case .networkPostCompleted(let remoteCounter):
            state.viewShowsLoadingAndDisablesButtons = false
            switch remoteCounter {
            case .success(let remoteCounterSuccess):
                state.viewDisplaysTotalCount = remoteCounterSuccess.count
            case .failure(let error):
                state.viewDisplaysError = error.localizedDescription
            }
        }
    }

    private static func triggerNetworkUpdate(state: inout State, effectsState: inout EffectsState<When>) throws {
        state.viewShowsLoadingAndDisablesButtons = true
        guard let url = URL(string: "http://statoscope.com") else {
            fatalError()
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(DTO(count: state.viewDisplaysTotalCount))
        effectsState.enqueue(
            NetworkEffect<DTO>(request: request)
                .mapToResult()
                .map(When.networkPostCompleted)
        )
    }
}
```

> Migrating an existing ViewModel-shaped screen instead of building something new? See [README-Statostore.md](README-Statostore.md) for the classic, class-based pattern — its `@Published`-properties-plus-methods shape maps closely onto what a ViewModel already looks like.

### Beyond basics

There are much more interesting topics covered by the Statoscope library.
* Dependency injection (`ReducerDependencies` / `@ReducerInjected`)
* Scope composition (`@SubState` / `@SuperState`)
* Reacting to child-scope events (`MiddlewareReducer` / `updateSubstate`)
* Effects testing
* SwiftUI views coupling to stores
Follow the links to the tutorials or documentation below for more info.

## Documentation And Tutorials

* [Documentation](https://inqbarna.github.io/statoscope/0.1.1/documentation/statoscope/)
* [Tutorials](https://inqbarna.github.io/statoscope/0.1.1/tutorials/statoscopetutorial)
