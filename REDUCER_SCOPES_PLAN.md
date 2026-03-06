# Reducer Pattern: Superscopes & Subscopes Support Plan

**Date:** 2026-02-27
**Status:** 📋 PROPOSAL (Not Implemented)

---

## Problem Statement

The Reducer pattern currently lacks two key features from traditional Statostores:

1. **Superscope Access** - Reading parent state (currently via `@Superscope` property wrapper)
2. **Subscope Management** - Declaring, creating, and managing child scopes with lifecycle

These features are critical for building complex scope hierarchies.

---

## 1. Superscope (Parent State Access)

### Current Traditional Pattern

```swift
final class ChildScope: Statostore, ObservableObject {
    @Superscope var parent: ParentScope
    @Published var childValue: Int = 0

    func update(_ when: When) throws {
        // Can read parent state
        childValue = parent.parentValue * 2

        // Can even send to parent (though discouraged)
        parent.send(.childDidUpdate)
    }
}
```

### Requirements for Reducer Pattern

- ✅ Read-only access to parent state
- ✅ Type-safe (know parent type)
- ✅ Optional (not all reducers have parents)
- ⚠️ Should NOT allow sending to parent (breaks unidirectional flow)
- ✅ Works with dependency injection tree

---

## Proposal 1A: Parent State via Dependencies (Recommended)

### API Design

```swift
// Access parent state through dependencies
static func update(
    _ when: When,
    state: inout State,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies
) throws {
    // Resolve parent state (read-only)
    if let parentState: ParentState = try? dependencies.resolveParentState() {
        state.value = parentState.someValue * 2
    }
}
```

### Implementation Approach

**Add to `ReducerDependencies` protocol:**
```swift
protocol ReducerDependencies {
    func resolve<T: Injectable>() throws -> T
    func inject<T>(_ object: T)

    // NEW: Parent state access
    func resolveParentState<S>() throws -> S  // Read-only parent state
}
```

**ReducerStore provides parent state:**
```swift
struct ReducerDependenciesImpl: ReducerDependencies {
    private let node: InjectionTreeNode?

    func resolveParentState<S>() throws -> S {
        guard let node = node,
              let parent = node._parentNode as? any ScopeImplementation,
              let parentWithState = parent as? any HasStateProtocol,
              let state = parentWithState.getState() as? S else {
            throw InjectionError.noParentState
        }
        return state  // Returns copy (read-only)
    }
}
```

**Need helper protocol for type erasure:**
```swift
@_spi(Internal)
protocol HasStateProtocol {
    func getState() -> Any
}

extension ReducerStore: HasStateProtocol {
    func getState() -> Any {
        return state
    }
}
```

### Pros/Cons

**Pros:**
- ✅ Leverages existing dependency injection infrastructure
- ✅ Read-only by default (returns copy)
- ✅ Type-safe with generic parameter
- ✅ Consistent with other dependency resolution
- ✅ Optional - just don't call if not needed

**Cons:**
- ⚠️ Runtime type checking (could fail at runtime if parent type wrong)
- ⚠️ Need protocol for type erasure
- ⚠️ Returns copy (not reference) - could be expensive for large state

---

## Proposal 1B: Parent State as Additional Parameter

### API Design

```swift
// Parent state as explicit parameter
protocol Reducer {
    associatedtype State
    associatedtype ParentState = Never  // Default: no parent

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        parentState: ParentState  // Read-only
    ) throws
}
```

### Usage

```swift
struct ChildReducer: Reducer {
    typealias ParentState = MyParentState  // Declare parent type

    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        parentState: MyParentState  // Automatically provided
    ) throws {
        state.value = parentState.someValue * 2
    }
}
```

### Pros/Cons

**Pros:**
- ✅ Compile-time type safety (parent type is in signature)
- ✅ Explicit in signature (clear that reducer needs parent)
- ✅ Read-only by default

**Cons:**
- ❌ More complex protocol (associatedtype)
- ❌ All reducers need to declare ParentState (even if Never)
- ❌ ReducerStore needs to handle Never case
- ❌ Less flexible (parent type baked into reducer)

---

## Recommendation for Superscope: **Proposal 1A**

Use `dependencies.resolveParentState<T>()` because:
- Simple API addition
- Leverages existing infrastructure
- Optional/flexible
- Read-only by default

---

## 2. Subscope (Child Scope Management)

### Current Traditional Pattern

```swift
final class ParentScope: Statostore, ObservableObject {
    @Published var parentValue: Int = 0
    @Subscope var child: ChildScope?

    func update(_ when: When) throws {
        switch when {
        case .showChild:
            // Create child
            child = ChildScope()

        case .hideChild:
            // Destroy child
            child = nil

        case .childAction:
            // Send to child
            child?.send(.increment)
        }
    }
}
```

### Key Challenges

1. **Lifecycle Management** - When to create/destroy child stores
2. **State Composition** - Is child state part of parent state?
3. **Event Routing** - How to send events to child reducers
4. **Declarative** - Need to declare available subscopes
5. **Type Safety** - Know child types at compile time

---

## Proposal 2A: Subscope State in Parent State (Simple, Limited)

### Concept

Child state is just data in parent state struct. No separate child reducer.

```swift
struct ParentState {
    var parentValue: Int
    var childState: ChildState?  // Optional child state
}

struct ChildState {
    var childValue: Int
}

struct ParentReducer: Reducer {
    enum When {
        case increment
        case showChild
        case hideChild
        case childIncrement  // Parent handles child events
    }

    static func update(...) {
        switch when {
        case .showChild:
            state.childState = ChildState(childValue: 0)

        case .hideChild:
            state.childState = nil

        case .childIncrement:
            state.childState?.childValue += 1
        }
    }
}
```

### Pros/Cons

**Pros:**
- ✅ Very simple - just data
- ✅ State is centralized
- ✅ Easy to snapshot entire tree
- ✅ No lifecycle complexity

**Cons:**
- ❌ Parent handles all child events (no separation of concerns)
- ❌ Can't reuse child reducers
- ❌ Doesn't scale for complex child logic
- ❌ Not really "subscopes" - just nested state

**Verdict:** Too limited. Only works for very simple nested data, not real scopes.

---

## Proposal 2B: Subscope Stores Managed by ReducerStore

### Concept

ReducerStore manages a collection of child ReducerStores. Reducers can create/destroy/access them.

### API Design

```swift
// New parameter for subscope management
protocol ReducerSubscopes {
    // Access existing subscope
    func get<R: Reducer>(_ type: R.Type, id: String?) -> ReducerStore<R>?

    // Create new subscope
    func create<R: Reducer>(_ type: R.Type, id: String?, initialState: R.State) -> ReducerStore<R>

    // Destroy subscope
    func destroy<R: Reducer>(_ type: R.Type, id: String?)

    // Send event to subscope
    func send<R: Reducer>(_ type: R.Type, id: String?, event: R.When)
}

// Updated Reducer protocol
protocol Reducer {
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: ReducerSubscopes  // NEW
    ) throws
}
```

### Usage Example

```swift
struct ParentReducer: Reducer {
    enum When {
        case showChild
        case hideChild
        case childIncrement
    }

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: ReducerSubscopes
    ) throws {
        switch when {
        case .showChild:
            // Create child subscope
            subscopes.create(
                ChildReducer.self,
                id: "main-child",  // Optional ID for multiple children
                initialState: ChildState(value: 0)
            )

        case .hideChild:
            // Destroy child subscope
            subscopes.destroy(ChildReducer.self, id: "main-child")

        case .childIncrement:
            // Send event to child
            subscopes.send(ChildReducer.self, id: "main-child", event: .increment)

            // Or get child and send
            if let child = subscopes.get(ChildReducer.self, id: "main-child") {
                child.send(.increment)
            }
        }
    }
}
```

### Implementation Approach

**ReducerStore manages subscope map:**
```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    @Published public private(set) var state: R.State

    // NEW: Subscope storage
    private var subscopes: [String: any ObservableObject] = [:]

    // Helper to generate keys
    private func subscopeKey<SR: Reducer>(_ type: SR.Type, id: String?) -> String {
        let typeName = String(describing: type)
        return id.map { "\(typeName):\($0)" } ?? typeName
    }
}

struct ReducerSubscopesImpl: ReducerSubscopes {
    private weak var store: AnyObject?
    private var subscopes: [String: any ObservableObject]

    func create<R: Reducer>(...) -> ReducerStore<R> {
        let child = ReducerStore<R>(initialState: initialState)
        let key = subscopeKey(type, id: id)
        subscopes[key] = child

        // Set up parent relationship for injection tree
        // (child as? InjectionTreeNode)?._parentNode = store

        return child
    }

    func get<R: Reducer>(...) -> ReducerStore<R>? {
        let key = subscopeKey(type, id: id)
        return subscopes[key] as? ReducerStore<R>
    }

    func destroy<R: Reducer>(...) {
        let key = subscopeKey(type, id: id)
        subscopes.removeValue(forKey: key)
    }
}
```

### Pros/Cons

**Pros:**
- ✅ Full subscope functionality (create/destroy/send)
- ✅ Child reducers are reusable
- ✅ Separation of concerns maintained
- ✅ Type-safe access
- ✅ Supports multiple children via IDs
- ✅ Works with injection tree

**Cons:**
- ⚠️ More complex API (new parameter)
- ⚠️ Subscope state not in parent state struct (separate)
- ⚠️ Need to manage subscope lifecycle manually
- ⚠️ Subscopes map needs to be passed as `inout` (mutated during update)

---

## Proposal 2C: Declarative Subscope Definition (Most Complex, Most Powerful)

### Concept

Declare subscopes in reducer type, similar to SwiftUI's @StateObject.

### API Design

```swift
protocol Reducer {
    associatedtype State
    associatedtype Subscopes = NoSubscopes  // Default: no subscopes

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: inout Subscopes  // Declared subscope stores
    ) throws
}

// Helper for no subscopes
struct NoSubscopes {}

// Define subscopes as struct
struct ParentSubscopes {
    var child: ReducerStore<ChildReducer>?
    var settings: ReducerStore<SettingsReducer>?
}

struct ParentReducer: Reducer {
    typealias Subscopes = ParentSubscopes

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: inout ParentSubscopes  // Type-safe!
    ) throws {
        switch when {
        case .showChild:
            subscopes.child = ReducerStore<ChildReducer>(
                initialState: ChildState(value: 0)
            )

        case .hideChild:
            subscopes.child = nil

        case .childIncrement:
            subscopes.child?.send(.increment)

        case .showSettings:
            subscopes.settings = ReducerStore<SettingsReducer>(
                initialState: SettingsState()
            )
        }
    }
}
```

### SwiftUI Integration

```swift
struct ParentView: View {
    @ObservedObject var store: ReducerStore<ParentReducer>

    var body: some View {
        VStack {
            Text("Parent: \(store.state.value)")

            // Access subscopes
            if let child = store.subscopes.child {
                ChildView(store: child)
            }
        }
    }
}
```

### Implementation Approach

**ReducerStore exposes subscopes:**
```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    @Published public private(set) var state: R.State

    // NEW: Public subscopes access
    public var subscopes: R.Subscopes

    public init(initialState: R.State) where R.Subscopes == NoSubscopes {
        self.state = initialState
        self.subscopes = NoSubscopes()
    }

    public init(initialState: R.State, subscopes: R.Subscopes) {
        self.state = initialState
        self.subscopes = subscopes
    }

    public func update(_ when: When) throws {
        var mutableState = state
        var mutableSubscopes = subscopes  // Make mutable copy
        let dependencies = ReducerDependenciesImpl(...)

        try R.update(
            when,
            state: &mutableState,
            effectsState: &effectsState,
            dependencies: dependencies,
            subscopes: &mutableSubscopes  // Pass as inout
        )

        state = mutableState
        subscopes = mutableSubscopes  // Assign back
    }
}
```

### Pros/Cons

**Pros:**
- ✅ Compile-time type safety (subscopes known at compile time)
- ✅ Declarative (explicitly list subscopes)
- ✅ Clean SwiftUI integration (subscopes accessible from view)
- ✅ Separation of concerns
- ✅ Subscopes are stored separately from state

**Cons:**
- ❌ Most complex implementation
- ⚠️ Subscopes struct needs to be defined manually
- ⚠️ Less flexible (can't dynamically create different subscope types)
- ⚠️ Need to handle Subscopes = NoSubscopes case

---

## Recommendation for Subscopes: **Proposal 2B or 2C**

**Use Proposal 2B (ReducerSubscopes parameter) if:**
- Need dynamic subscope creation (don't know types ahead of time)
- Have many optional subscopes
- Want simpler implementation

**Use Proposal 2C (Declarative Subscopes) if:**
- Know subscope types at compile time
- Want better SwiftUI integration
- Prefer explicit declarations
- Don't mind extra complexity

---

## Combined API (Full Picture)

### If using Proposal 1A + 2B:

```swift
protocol Reducer {
    associatedtype When
    associatedtype State

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,  // For injection + parent state
        subscopes: ReducerSubscopes          // For child management
    ) throws
}

// Extended ReducerDependencies
protocol ReducerDependencies {
    func resolve<T: Injectable>() throws -> T
    func inject<T>(_ object: T)
    func resolveParentState<S>() throws -> S  // NEW
}

// New ReducerSubscopes
protocol ReducerSubscopes {
    func get<R: Reducer>(_ type: R.Type, id: String?) -> ReducerStore<R>?
    func create<R: Reducer>(_ type: R.Type, id: String?, initialState: R.State) -> ReducerStore<R>
    func destroy<R: Reducer>(_ type: R.Type, id: String?)
    func send<R: Reducer>(_ type: R.Type, id: String?, event: R.When)
}
```

### If using Proposal 1A + 2C:

```swift
protocol Reducer {
    associatedtype When
    associatedtype State
    associatedtype Subscopes = NoSubscopes  // Declarative subscopes

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,  // For injection + parent state
        subscopes: inout Subscopes          // Declarative child stores
    ) throws
}
```

---

## Full Example: Complex Hierarchy

```swift
// ====== Parent Reducer ======

struct ParentState {
    var title: String
    var count: Int
}

struct ParentSubscopes {
    var child: ReducerStore<ChildReducer>?
}

struct ParentReducer: Reducer {
    typealias Subscopes = ParentSubscopes

    enum When {
        case showChild
        case hideChild
        case incrementChild
    }

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: inout ParentSubscopes
    ) throws {
        switch when {
        case .showChild:
            subscopes.child = ReducerStore<ChildReducer>(
                initialState: ChildState(value: 0)
            )

        case .hideChild:
            subscopes.child = nil

        case .incrementChild:
            subscopes.child?.send(.increment)
        }
    }
}

// ====== Child Reducer ======

struct ChildState {
    var value: Int
}

struct ChildReducer: Reducer {
    typealias Subscopes = NoSubscopes  // No children

    enum When {
        case increment
        case readParent
    }

    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        subscopes: inout NoSubscopes
    ) throws {
        switch when {
        case .increment:
            state.value += 1

        case .readParent:
            // Access parent state (read-only)
            if let parentState: ParentState = try? dependencies.resolveParentState() {
                state.value = parentState.count
            }
        }
    }
}

// ====== SwiftUI View ======

struct ParentView: View {
    @ObservedObject var store: ReducerStore<ParentReducer>

    var body: some View {
        VStack {
            Text("Parent: \(store.state.title)")

            Button("Show Child") {
                store.send(.showChild)
            }

            // Render child if exists
            if let child = store.subscopes.child {
                ChildView(store: child)
            }
        }
    }
}

struct ChildView: View {
    @ObservedObject var store: ReducerStore<ChildReducer>

    var body: some View {
        Text("Child: \(store.state.value)")
        Button("Increment") {
            store.send(.increment)
        }
    }
}
```

---

## Implementation Phases

### Phase 1: Superscope Support (Simpler)
1. Add `resolveParentState<S>()` to `ReducerDependencies` protocol
2. Implement in `ReducerDependenciesImpl`
3. Add `HasStateProtocol` for type erasure
4. Implement in `ReducerStore`
5. Add tests

**Estimated effort:** 2-3 hours

### Phase 2: Subscopes Support (Complex)
Choose between 2B or 2C, then:
1. Define `ReducerSubscopes` protocol OR `Subscopes` associatedtype
2. Update `Reducer` protocol signature
3. Update `ReducerStore` to manage subscopes
4. Implement subscope lifecycle
5. Wire up injection tree relationships
6. Add tests
7. Add SwiftUI examples

**Estimated effort:** 4-6 hours (2B) or 6-8 hours (2C)

---

## Open Questions

1. **Should subscopes trigger parent re-renders?**
   - When child state changes, should parent @Published trigger?
   - Probably not (SwiftUI handles child observation separately)

2. **Should we support heterogeneous subscope collections?**
   - `var children: [ReducerStore<ChildReducer>]`
   - Requires more complex API

3. **Should subscopes be exposed publicly on ReducerStore?**
   - For SwiftUI access: YES (Proposal 2C)
   - For encapsulation: NO (Proposal 2B)

4. **How to handle subscope deallocation?**
   - When `subscopes.child = nil`, does it properly deinit?
   - Need to test memory management

5. **Should parent modification from child be allowed?**
   - Currently NO (read-only parent state)
   - Could allow via dependencies.sendToParent(event)?
   - Probably discourage this pattern

---

## Recommendation Summary

### For Superscope: ✅ Proposal 1A
- Add `dependencies.resolveParentState<S>()`
- Simple, clean, leverages existing infrastructure
- Read-only by default (good practice)

### For Subscopes: 🤔 Choose Based on Needs

**Use Proposal 2C (Declarative) if:**
- Building medium-to-complex hierarchies
- Want compile-time safety
- Need SwiftUI integration
- Prefer explicit declarations

**Use Proposal 2B (Dynamic) if:**
- Need runtime flexibility
- Have simpler use cases
- Want easier implementation
- Prefer imperative style

**Use Traditional Statostore if:**
- Very complex hierarchies
- Need maximum flexibility
- Reducer constraints feel limiting

---

## Next Steps

1. **Get user feedback** on proposals
2. **Choose subscope approach** (2B or 2C)
3. **Implement superscope support** (Phase 1)
4. **Implement subscope support** (Phase 2)
5. **Add comprehensive tests**
6. **Update documentation**
7. **Create migration examples**

---

## Conclusion

Both superscopes and subscopes can be added to the Reducer pattern:

- **Superscopes** are straightforward via `dependencies.resolveParentState<S>()`
- **Subscopes** require more design decisions (2B vs 2C)

The Reducer pattern remains simpler than traditional Statostore, but can still handle hierarchical state management when needed.

For very complex scope trees, traditional Statostore may still be the better choice - and that's okay! Both patterns can coexist.
