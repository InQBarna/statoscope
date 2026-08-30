# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Statoscope is a Swift state management library for iOS focused on simplicity, testability, and scalability. It provides a structured approach to managing app state with synchronous events (When) and asynchronous effects.

## Build and Test Commands

### Building
```bash
swift build
```

For Xcode builds (iOS simulator):
```bash
xcodebuild -skipPackagePluginValidation -scheme Statoscope -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 16' build
```

### Testing
```bash
# Run all tests
swift test

# Run specific test target
swift test --filter StatoscopeTests
swift test --filter StatoscopeTestingTests
swift test --filter StatoscopeMacrosTests

# Run tests using Xcode test plan
xcodebuild test -scheme Statoscope -testPlan Statoscope-Package
```

### Documentation
Documentation is built using Swift-DocC. The library includes comprehensive documentation in `Sources/Statoscope/Documentation.docc/`.

## Architecture

### Core Concepts

**Scope**: The fundamental unit representing a piece of application state. Scopes are reference types (classes) that conform to the `Scope` protocol and manage a specific domain of state.

**Statostore**: The class-based implementation pattern combining Scope, ScopeImplementation, and StoreProtocol in a single class. The migration path for existing ViewModel-shaped screens — see State Management Patterns below.

**Reducer**: The recommended pattern for new features — a `@Reducer`-annotated struct with a `State`, a `When`, and a static `update()`. The macro generates a `Store<YourReducer>` that implements Scope/ScopeImplementation/StoreProtocol under the hood. See State Management Patterns below.

**When**: An enum defining all possible events that can occur within a Scope's lifetime. Events are processed synchronously through the `update(_:)` method.

**Effect**: Asynchronous operations that complete with a When case. Effects are type-safe and composable using map/mapToResult methods.

**EffectsState**: Manages the lifecycle of effects within a scope, providing enqueue/cancel operations. Effects are triggered after the `update(_:)` method completes.

### Dependency Injection and Scope Composition

**InjectionTreeNode**: All scopes participate in a dependency injection tree, similar to SwiftUI's environment.

**@Superscope**: Property wrapper linking a child Statostore to its parent in the injection tree.

**@Subscope**: Property wrapper for managing child Statostores within a parent scope.

**Injectable & @Injected**: Protocol and property wrapper for multi-level dependency injection throughout the scope hierarchy (works for both Statostore and Reducer).

**@SubState / @SuperState**: The Reducer-pattern equivalents of `@Subscope`/`@Superscope`, declared directly on a Reducer's `State` struct rather than on the class. See State Management Patterns below.

**MiddlewareReducer**: The Reducer-pattern equivalent of `HierarchialScopeMiddleWare` — lets a Reducer intercept events from its own `@SubState` children (not its own events; that's a different concern, see below). See State Management Patterns below.

### State Updates Flow

1. UI/System sends a When event via `send(_:)` or `sendUnsafe(_:)`
2. The `update(_:)` method processes the event synchronously
3. State properties (typically @Published) are mutated
4. Effects may be enqueued via `effectsState.enqueue(_:)`
5. After update completes, enqueued effects are triggered
6. Effect completion sends new When events back to the scope

### Module Structure

- **Statoscope**: Core library with Scope, Effect, Statostore, Reducer, and injection system
  - `Reducer/`: The Reducer pattern — `Reducer`/`MiddlewareReducer` protocols, `Store<R>`, `SubState`/`SuperState`, `ReducerDependencies`, `ReducerInjected`, child-slot machinery
  - `Effects/`: Effect protocol, type erasure (AnyEffect), and effects handler (shared by both patterns)
  - `Injection/`: Dependency injection system (Injectable, @Injected, @Superscope, @Subscope — Statostore-side; Reducer's equivalents live in `Reducer/`)
  - `SwiftUI/`: SwiftUI integration helpers (StoreView, bindings, AutoConnectedView for Reducer navigation)
  - `Helpers/`: Utility code and runtime helpers
  - `Logging/`: Debug description and logging support

- **StatoscopeTesting**: Testing utilities (import in test targets only)
  - `StoreTestPlan/`: Fluent testing API (GIVEN/WHEN/THEN/FORK) — works with both Statostore and Reducer stores
  - Testing helpers for effects, scope tree inspection, and deallocation checks

- **StatoscopeMacros**: Swift macros for reducing boilerplate
  - `@Reducer`: Generates the `Store<R>` typealias and child/parent-slot wiring for a Reducer type
  - `@SuperScope`: Incremental-migration macro linking a Reducer's State to an unmigrated legacy Statostore parent
  - `@EffectStruct`: Generates Effect conformance from static async functions
  - `@CaseAssociatedGet`: Generates convenience getters for enum associated values
  - `@Copy`: Generates copy methods for value types

## State Management Patterns

Statoscope ships two patterns for managing a scope's state. **Reducer is recommended for new features.** Statostore — the original, class-based pattern — is best treated as the migration path for bringing an existing `ObservableObject`/ViewModel-shaped screen into Statoscope with minimal reshaping: its `@Published`-properties-plus-methods shape maps closely onto what a ViewModel already looks like.

### Reducer Pattern (Recommended)

A Reducer is a plain struct annotated with `@Reducer`. It defines a nested `State` struct, a `When` enum, and a `static func update(...)` — no `self`, no stored properties on the reducer itself. The macro generates a `Store<YourReducer>` class (exposed as `YourReducer.Store`) that holds the actual state, schedules effects, and conforms to `ObservableObject` for SwiftUI.

```swift
@Reducer
struct CounterReducer {
    struct State {
        var count: Int = 0
        var name: String = ""
    }

    enum When {
        case increment
        case setName(String)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .increment:
            state.count += 1
        case .setName(let name):
            state.name = name
        }
    }
}

// The macro generates CounterReducer.Store:
let store = CounterReducer.Store(initialState: CounterReducer.State())
store.send(.increment)
print(store.state.count) // 1
```

Being `static` is the point: `update()` has no access to `self`, so it can't reenter `send()` on itself — the reentrancy hole documented for the classic Statostore pattern in `PRODUCTION_READINESS_AUDIT.md` is closed by construction here, not by a runtime guard.

#### Parent-child composition: `@SubState` / `@SuperState`

Child scopes are declared directly on the parent's `State` struct:

```swift
@Reducer
struct ParentReducer {
    struct State {
        @SubState var child: ChildReducer.State?
    }
    enum When { case createChild }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createChild:
            state.child = ChildReducer.State()   // creates and wires the child Store
        }
    }
}
```

Assigning a value creates (or replaces) the child `Store`; assigning `nil` destroys it. The parent accesses the live child via the macro-generated `store.children.child` accessor.

A child that needs read access to its parent's state declares `@SuperState`:

```swift
@Reducer
struct ChildReducer {
    struct State {
        @SuperState var parent: ParentReducer.State   // read-only snapshot, injected before each update()
        var doubled: Int = 0
    }
    enum When { case sync }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .sync: state.doubled = state.parent.count * 2
        }
    }
}
```

`@SuperState` is a **value snapshot** taken fresh before each `update()` call — not a live reference to the parent. It's read-only: assigning to it is a compile error.

#### Intercepting child events: `MiddlewareReducer` + `SubstateOutcome`

A reducer that needs to react to events from its own `@SubState` children conforms to `MiddlewareReducer`:

```swift
@Reducer
struct ParentReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: ChildReducer.State?
        var delegatedTasks: [String] = []
    }
    enum When { case childDelegated(String) }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,               // read-only — updateSubstate never mutates directly
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        guard let when = childWhen as? ChildReducer.When else { return .pass }
        if case .taskCompleted(let task) = when {
            return .react(.childDelegated(task))   // send to update(), then still forward to the child
        }
        return .pass
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .childDelegated(let task): state.delegatedTasks.append(task)
        }
    }
}
```

`updateSubstate` runs BEFORE the child's own `update()`, and `parentState` is read-only by design — any reaction has to go through the returned `SubstateOutcome<When>`, which lands in `update()`, the single place `State` ever changes:
- `.pass` — no reaction, forward the event to the child as normal
- `.react(When)` — send `When` to this reducer's own `update()`, then still forward to the child
- `.intercept(When?)` — optionally send `When`, but do NOT forward to the child. Use this when the reaction makes forwarding unsafe — most commonly, it replaced or removed the very child subtree the event came from.

#### Dependency injection: `ReducerDependencies` / `@ReducerInjected`

```swift
static func update(
    _ when: When,
    state: inout State,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies
) throws {
    let logger: Logger = try dependencies.resolve()
    logger.log("Processing: \(when)")
}
```

For ambient access across the whole `State` struct rather than just inside `update()`, use `@ReducerInjected` directly on a state property — resolved from the injection tree the same way `@Injected` resolves for classic Statostore.

#### Effects

```swift
static func update(
    _ when: When,
    state: inout State,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies
) throws {
    switch when {
    case .startLoad:
        state.isLoading = true
        effectsState.enqueue(
            FetchDataEffect()
                .mapToResult()
                .map(When.loadCompleted)
        )
    case .loadCompleted(let result):
        state.isLoading = false
        // handle result...
    }
}
```

Same `EffectsState`/`Effect` infrastructure as classic Statostore — effects are enqueued during `update()` and triggered after it returns, exactly as described in State Updates Flow above.

### Traditional Statostore Pattern (Migration Path)

The original pattern: a class with scattered `@Published` properties and an instance-method `update(_:)`.

```swift
final class CounterScope: Statostore, ObservableObject {
    @Published var count: Int = 0
    @Published var name: String = ""

    enum When {
        case increment
        case setName(String)
    }

    func update(_ when: When) throws {
        switch when {
        case .increment:
            count += 1
        case .setName(let name):
            self.name = name
        }
    }
}
```

Reach for this when migrating an existing `ObservableObject`/ViewModel-shaped screen — the `@Published`-properties-plus-methods shape maps closely onto what's already there, so the mechanical rewrite is small. Be aware it currently has real, unresolved safety gaps that `@Reducer` closes by construction (no reentrancy guard on `send()` during `update()`; see `PRODUCTION_READINESS_AUDIT.md`) — prefer Reducer for anything new.

Both patterns share the same testing, effects, and injection infrastructure.

## Testing Patterns

### Flow Testing (GIVEN/WHEN/THEN)

Statoscope emphasizes "Acceptance as Code" - tests declare expected behavior using a fluent API:

```swift
// Classic Statostore: KeyPaths point directly at @Published properties
try MyScope.GIVEN {
    MyScope()
}
.THEN(\.stateProperty, equals: initialValue)
.WHEN(.userAction)
.THEN(\.stateProperty, equals: newValue)
.runTest()

// Reducer: KeyPaths go through .state, since state is a single struct
try MyReducer.Store.GIVEN {
    MyReducer.Store(initialState: MyReducer.State())
}
.THEN(\.state.stateProperty, equals: initialValue)
.WHEN(.userAction)
.THEN(\.state.stateProperty, equals: newValue)
.runTest()
```

### Key Testing Methods

- **GIVEN**: Creates the scope instance
- **WHEN**: Sends a When event to the scope
- **THEN**: Asserts state using KeyPath or custom closure
- **FORK**: Tests alternate execution paths (e.g., success vs. error)
- **WITH**: Navigates to a child scope for assertions
- **WHEN_EffectCompletes**: Simulates effect completion with a result
- **WHEN_OlderEffectCompletes**: Completes the oldest pending effect
- **THEN_NoEffects**: Asserts no pending effects exist

### Effect Testing

Effects are tested by simulating their completion:

```swift
.WHEN_EffectCompletes(MyEffect.self, with: .successResult)
// or
.WHEN_OlderEffectCompletes(with: .whenCase(.result))
```

## Macros

### @EffectStruct

Converts static async functions into Effect types:

```swift
@EffectStruct
static func fetchData() async throws -> Data {
    // async implementation
}
// Generates: FetchDataEffect struct conforming to Effect
```

Use `equatable: true` parameter to auto-generate Equatable conformance.

### @CaseAssociatedGet

Generates convenience getters for enum associated values - useful for extracting values from When cases in tests.

## SwiftLint

The project uses SwiftLint with minimal configuration (`.swiftlint.yml`):
- Allows underscores in identifiers and type names
- SwiftLintBuildToolPlugin is integrated via Package.swift

## Common Patterns

### Naming Conventions for Acceptance as Code

State properties should read as sentences: `viewDisplaysTotalCount`, `viewShowsLoadingAndDisablesButtons`

When cases should read as events: `.userTappedIncrementButton`, `.networkPostCompleted(Result)`

This makes tests self-documenting.

### Effect Patterns

Effects return When cases to complete their lifecycle:

```swift
enum When {
    case userStartedOperation
    case operationCompleted(Result<Success, Failure>)
}

// Reducer pattern: effectsState is a parameter of static update()
static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
    switch when {
    case .userStartedOperation:
        effectsState.enqueue(
            MyEffect()
                .mapToResult()
                .map(When.operationCompleted)
        )
    case .operationCompleted(let result):
        // handle result
    }
}

// Classic Statostore: effectsState is available directly on self
func update(_ when: When) throws {
    switch when {
    case .userStartedOperation:
        effectsState.enqueue(
            MyEffect()
                .mapToResult()
                .map(When.operationCompleted)
        )
    case .operationCompleted(let result):
        // handle result
    }
}
```

### Testing with assertRelease

Use `runTest(assertRelease: true)` to verify scopes are properly deallocated after tests, catching memory leaks.

### Testing with assertNoPendingEffects

By default `runTest()` checks for pending effects at the end. Disable with `assertNoPendingEffects: false` if testing scenarios with ongoing effects.

## Important Implementation Details

**ScopeImplementation vs Scope**: `Scope` is the public protocol. `ScopeImplementation` is the internal protocol with the `update(_:)` method and effects handling. `Statostore` conforms to both.

**Middleware**: Two distinct mechanisms, both available on Reducer's generated `Store<R>` (since it's also a Statostore) as well as classic Statostore. `addMiddleWare { store, when, forward in ... }` intercepts a scope's OWN events before its own `update()` runs — useful for logging/analytics without changing core logic. `MiddlewareReducer`/`HierarchialScopeMiddleWare` is a different concern: intercepting events from a scope's CHILD scopes (see State Management Patterns below).

**Effects are NOT immediately triggered**: Effects enqueued during `update(_:)` are triggered after the method completes. The `effectsState` accumulates them during the update.

**Type erasure with AnyEffect**: Effects are type-erased to `AnyEffect<When>` internally. The original "pristine" effect is preserved for testing and comparison using `pristineEquals(_:)` and `pristineIs(_:)`.

## Project Status

See `PRODUCTION_READINESS_AUDIT.md` for current production readiness assessment and known limitations.
