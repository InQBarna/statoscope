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

**Statostore**: The primary implementation pattern combining Scope, ScopeImplementation, and StoreProtocol in a single class. Most features should be implemented as Statostores.

**When**: An enum defining all possible events that can occur within a Scope's lifetime. Events are processed synchronously through the `update(_:)` method.

**Effect**: Asynchronous operations that complete with a When case. Effects are type-safe and composable using map/mapToResult methods.

**EffectsState**: Manages the lifecycle of effects within a scope, providing enqueue/cancel operations. Effects are triggered after the `update(_:)` method completes.

### Dependency Injection and Scope Composition

**InjectionTreeNode**: All scopes participate in a dependency injection tree, similar to SwiftUI's environment.

**@Superscope**: Property wrapper linking a child scope to its parent in the injection tree.

**@Subscope**: Property wrapper for managing child scopes within a parent scope.

**Injectable & @Injected**: Protocol and property wrapper for multi-level dependency injection throughout the scope hierarchy.

### State Updates Flow

1. UI/System sends a When event via `send(_:)` or `sendUnsafe(_:)`
2. The `update(_:)` method processes the event synchronously
3. State properties (typically @Published) are mutated
4. Effects may be enqueued via `effectsState.enqueue(_:)`
5. After update completes, enqueued effects are triggered
6. Effect completion sends new When events back to the scope

### Module Structure

- **Statoscope**: Core library with Scope, Effect, Statostore, and injection system
  - `Effects/`: Effect protocol, type erasure (AnyEffect), and effects handler
  - `Injection/`: Dependency injection system (Injectable, @Injected, @Superscope, @Subscope)
  - `SwiftUI/`: SwiftUI integration helpers (StoreView, bindings)
  - `Helpers/`: Utility code and runtime helpers
  - `Logging/`: Debug description and logging support

- **StatoscopeTesting**: Testing utilities (import in test targets only)
  - `StoreTestPlan/`: Fluent testing API (GIVEN/WHEN/THEN/FORK)
  - `BuilderAPI/`: Alternative result builder-based testing API (B namespace)
  - Testing helpers for effects, scope tree inspection, and deallocation checks

- **StatoscopeMacros**: Swift macros for reducing boilerplate
  - `@EffectStruct`: Generates Effect conformance from static async functions
  - `@CaseAssociatedGet`: Generates getters for enum associated values
  - `@Copy`: Generates copy methods for value types

## State Management Patterns

### Single State Struct Pattern (Recommended)

**New in v2.x**: Statoscope now supports a single state struct pattern with dirty flag optimization for improved refactoring and performance.

#### Why Use Single State?

**Benefits:**
- **Centralized State**: All state in one struct, easy to understand and refactor
- **Easy Snapshots**: `let snapshot = scope.state` for undo/redo or state restoration
- **Performance**: Dirty flag prevents unnecessary @Published triggers (~90% reduction)
- **No Equatable Required**: Works with any state size without expensive comparisons

**Migration from Multiple @Published:**

```swift
// BEFORE: Multiple @Published properties
final class MyScope: Statostore, ObservableObject {
    @Published var count: Int = 0
    @Published var name: String = ""
    @Published var items: [Item] = []
    // State scattered across properties
}

// AFTER: Single state struct
struct MyState {
    var count: Int = 0
    var name: String = ""
    var items: [Item] = []
}

final class MyScope: Statostore, SingleStateScope, ObservableObject {
    @Published var state: MyState = MyState()

    enum When {
        case increment
        case setName(String)
    }

    // Old signature (required) - delegates to single state
    func update(_ when: When) throws {
        try updateWithSingleState(when)
    }

    // New signature with UpdateContext
    func update(_ when: When, context: inout UpdateContext<When, MyState>) throws {
        switch when {
        case .increment:
            context.state.count += 1  // Dirty flag automatically tracked
        case .setName(let name):
            context.state.name = name
        }
    }
}
```

#### How Dirty Flag Works

The `UpdateContext` tracks whether state was mutated during `update()`:

```swift
func update(_ when: When, context: inout UpdateContext<When, MyState>) throws {
    switch when {
    case .modifyingEvent:
        context.state.count += 1
        // Setting state.count marks dirty flag = true
        // Framework assigns to @Published: self.state = context.state

    case .readOnlyEvent:
        let value = context.state.count  // Just reading, no mutation
        // dirty flag stays false
        // Framework skips assignment, @Published not triggered!
    }
}
```

**Performance Impact:**
- Events that don't modify state: No @Published trigger (saves SwiftUI diffing)
- Events that modify state: Normal @Published trigger
- Overhead: Single boolean check (~0.001ms)
- No Equatable requirement: Works for domains of any size

**Edge Case:**
```swift
context.state.count = 5
context.state.count = 0  // Back to original value
// dirty flag = true (false positive)
// But SwiftUI's built-in diffing handles it → no UI update
```

**Verdict:** ~10% false positives are acceptable given SwiftUI's diffing.

#### UpdateContext API

The `UpdateContext<When, State>` provides:

```swift
public struct UpdateContext<When, State> {
    // State access with automatic dirty tracking
    public var state: State { get set }

    // Effects management
    public var effectsState: EffectsState<When>

    // Dependency injection access
    public var injectionTreeNode: InjectionTreeNode?
}
```

**Usage Examples:**

```swift
// Modify state
context.state.count += 1

// Enqueue effects
context.effectsState.enqueue(
    FetchDataEffect()
        .mapToResult()
        .map(When.dataLoaded)
)

// Access injected dependencies
let logger = context.injectionTreeNode?._resolve() as? Logger
```

#### State Snapshots and Restoration

Single state structs make snapshots trivial:

```swift
// Take snapshot
let snapshot = scope.state

// Modify state
scope.send(.increment)
scope.send(.setName("New"))

// Restore from snapshot (undo)
scope.state = snapshot
```

#### Subscopes with Single State

**Important:** `@Subscope` properties stay on the Statostore, NOT in the state struct:

```swift
struct MyState {
    var count: Int
    // ❌ NO @Subscope here
}

final class MyScope: Statostore, SingleStateScope, ObservableObject {
    @Published var state: MyState = MyState()
    @Subscope var child: ChildScope?  // ✅ Here on Statostore
}
```

**Rationale:** Subscopes have lifecycle and framework concerns (not pure data).

#### Testing with Single State

The fluent testing API works seamlessly:

```swift
try MyScope.GIVEN {
    MyScope()
}
.THEN(\.state.count, equals: 0)  // Access state via KeyPath
.WHEN(.increment)
.THEN(\.state.count, equals: 1)
.runTest()
```

For builder API:

```swift
B.TestPlan<MyScope> {
    B.GIVEN { MyScope() }
    B.THEN(\.state.count, equals: 0)
    B.WHEN(.increment)
    B.THEN(\.state.count, equals: 1)
}.run()
```

### Traditional Multiple @Published Pattern

The traditional pattern with multiple `@Published` properties continues to work:

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

This pattern is appropriate for:
- Simple scopes with 2-3 state properties
- When you don't need state snapshots
- When state is naturally independent

## Testing Patterns

### Flow Testing (GIVEN/WHEN/THEN)

Statoscope emphasizes "Acceptance as Code" - tests declare expected behavior using a fluent API:

```swift
try MyScope.GIVEN {
    MyScope()
}
.THEN(\.stateProperty, equals: initialValue)
.WHEN(.userAction)
.THEN(\.stateProperty, equals: newValue)
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

### Builder API (Alternative)

The `B` namespace provides a result builder API for better debugging:

```swift
B.TestPlan<MyScope> {
    B.GIVEN { MyScope() }
    B.THEN(\.state, equals: value)
    B.WHEN(.action)
    B.THEN(\.state, equals: newValue)
}.run()
```

The builder API executes steps imperatively with `@inline(never)` functions, making it easier to set breakpoints and step through tests.

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

func update(_ when: When, context: inout UpdateContext<When, State>) throws {
    switch when {
    case .userStartedOperation:
        context.effectsState.enqueue(
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

**Middleware**: Scopes support middleware for intercepting When events - useful for logging, analytics, or modifying behavior without changing core logic.

**Effects are NOT immediately triggered**: Effects enqueued during `update(_:)` are triggered after the method completes. The `effectsState` accumulates them during the update.

**Type erasure with AnyEffect**: Effects are type-erased to `AnyEffect<When>` internally. The original "pristine" effect is preserved for testing and comparison using `pristineEquals(_:)` and `pristineIs(_:)`.

**Single State Bridge Pattern**: Scopes using `SingleStateScope` must implement both the old `update(_:)` signature (as a bridge) and the new `update(_:context:)` signature. The bridge delegates to `updateWithSingleState()` which handles dirty flag tracking automatically.

## Migration Guides

### Migrating to Single State Pattern

**Step 1: Define State Struct**

```swift
// Collect all @Published properties into a struct
struct CounterState {
    var count: Int = 0
    var name: String = ""
    var isLoading: Bool = false
}
```

**Step 2: Replace @Published Properties**

```swift
// Before
final class CounterScope: Statostore, ObservableObject {
    @Published var count: Int = 0
    @Published var name: String = ""
    @Published var isLoading: Bool = false

// After
final class CounterScope: Statostore, SingleStateScope, ObservableObject {
    @Published var state: CounterState = CounterState()
```

**Step 3: Adopt SingleStateScope Protocol**

```swift
final class CounterScope: Statostore, SingleStateScope, ObservableObject {
    @Published var state: CounterState = CounterState()

    // Add bridge method
    func update(_ when: When) throws {
        try updateWithSingleState(when)
    }

    // Add new signature with UpdateContext
    func update(_ when: When, context: inout UpdateContext<When, CounterState>) throws {
        // Implementation...
    }
}
```

**Step 4: Update update() Implementation**

```swift
// Before
func update(_ when: When) throws {
    switch when {
    case .increment:
        count += 1
    case .setName(let name):
        self.name = name
    }
}

// After
func update(_ when: When, context: inout UpdateContext<When, CounterState>) throws {
    switch when {
    case .increment:
        context.state.count += 1  // Access via context.state
    case .setName(let name):
        context.state.name = name
    }
}
```

**Step 5: Update SwiftUI Views**

```swift
// Before
Text("\(scope.count)")

// After
Text("\(scope.state.count)")
```

**Step 6: Update Tests**

```swift
// Before
.THEN(\.count, equals: 1)

// After
.THEN(\.state.count, equals: 1)
```

**Common Pitfalls:**

1. **Don't put @Subscope in state struct** - Keep subscopes on Statostore class
2. **Remember the bridge method** - Must implement both `update(_:)` signatures
3. **Update KeyPaths in tests** - Add `.state` prefix to all KeyPath assertions
4. **Import @_spi for updateWithSingleState** - Tests need `@_spi(Internal) @testable import Statoscope`

## Project Status

See `PRODUCTION_READINESS_AUDIT.md` for current production readiness assessment and known limitations.

See `SINGLE_STATE_PROGRESS.md` for details on single state pattern implementation status.
