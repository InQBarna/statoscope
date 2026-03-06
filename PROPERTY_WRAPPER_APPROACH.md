# Property Wrappers on State: Implementation Challenges

## The Goal

User wants to write:

```swift
struct ChildState {
    @ParentReducer var parent: ParentState
    var value: Int = 0
}

struct ChildReducer: Reducer {
    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout NoScopeLinks  // Not used
    ) throws {
        // Access parent state directly
        state.value = state.parent.count * 2
    }
}
```

## Challenge

Property wrappers on value types (State) need access to reference types (ReducerStore) to get current state. But:

1. State is copied in/out of update()
2. Property wrappers can't access external context by default
3. Reflection can see wrappers but can't easily call their methods

## Proposed Solutions

### Option 1: Hidden Context Field (❌ Complex)

State has a hidden `_context` field that framework injects:

```swift
struct ChildState {
    @_spi(Internal) var _context: StateContext?
    @ParentReducer var parent: ParentState
    var value: Int = 0
}
```

**Problems:**
- Pollutes every State struct
- Framework needs to inject context before update()
- Breaks State purity (has framework-specific field)

### Option 2: Thread-Local Context (❌ Fragile)

Use thread-local storage to pass context:

```swift
// Framework sets this before calling update()
thread_local var currentReducerContext: StateContext?

@propertyWrapper
struct ParentReducer<R: Reducer> {
    var wrappedValue: R.State {
        currentReducerContext?.parentState as? R.State ?? defaultValue
    }
}
```

**Problems:**
- Breaks if update() switches threads
- Fragile and hard to debug
- Not safe for concurrent access

### Option 3: Manual Computed Properties (✅ Simple)

State uses computed properties that access scopeLinks:

```swift
struct ChildState {
    // Hidden storage for scopeLinks (injected by framework)
    @_spi(Internal) var _scopeLinks: ChildScopeLinks

    // Computed property for parent access
    var parent: ParentState {
        _scopeLinks.parent?.state ?? ParentState()
    }

    var value: Int = 0
}
```

**Problems:**
- Still requires framework to inject _scopeLinks
- Not much better than current scopeLinks parameter

### Option 4: Keep ScopeLinks Parameter (✅ RECOMMENDED)

Current approach with state projections is actually clean:

```swift
struct ChildScopeLinks {
    var parent: Parent<ParentReducer>?  // State-only projection
}

struct ChildState {
    var value: Int = 0
}

static func update(
    _ when: When,
    state: inout ChildState,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies,
    scopeLinks: inout ChildScopeLinks
) throws {
    // Access parent state (no send() method available!)
    if let parentState = scopeLinks.parent?.state {
        state.value = parentState.count * 2
    }
}
```

**Advantages:**
- ✅ Explicit and clear
- ✅ State remains pure value type
- ✅ No framework magic
- ✅ Compile-time safe (no send() method)
- ✅ Easy to test and understand

## Recommendation

**Keep the current `scopeLinks` parameter approach** with state projections.

It's explicit, safe, and doesn't require complex framework magic. The slight verbosity (`scopeLinks.parent?.state` instead of `state.parent`) is worth the simplicity and safety.

If users really want property-wrapper-like syntax, they can define helper extensions:

```swift
extension ChildState {
    mutating func syncWithParent(_ scopeLinks: ChildScopeLinks) {
        if let parentState = scopeLinks.parent?.state {
            self.value = parentState.count * 2
        }
    }
}

// In update:
state.syncWithParent(scopeLinks)
```

This gives them the ergonomics they want while keeping the framework simple.
