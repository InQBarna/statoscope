# Reducer Pattern: Parent Observation & Scope Links

**Date:** 2026-02-27
**Status:** 📋 PROPOSAL - Parent Observation Solution

---

## The Problem

### Current Issue with Read-Only Parent State

In the original proposal, parent state is accessed via:
```swift
let parentState: ParentState = try dependencies.resolveParentState()
```

**Problems:**
1. Returns a **copy** (not reference) - no observation link
2. ChildView won't re-render when parent changes
3. In SwiftUI navigation (NavigationLink, sheets), views are cached
4. Child views may show stale parent data

### Why This Matters

```swift
struct ChildView: View {
    @ObservedObject var childStore: ReducerStore<ChildReducer>

    var body: some View {
        VStack {
            // This works - observes child
            Text("Child count: \(childStore.state.value)")

            // This DOESN'T update when parent changes!
            // Because we only observe childStore, not parent
            Text("Parent count: \(childStore.state.parentCount)")
        }
    }
}
```

When parent's @Published state changes, ChildView doesn't re-render because it doesn't observe the parent store.

---

## Traditional Statostore Solution

```swift
final class ChildScope: Statostore, ObservableObject {
    @Superscope var parent: ParentScope  // Strong reference, Observable

    // @Superscope property wrapper likely:
    // 1. Holds reference to parent
    // 2. Observes parent's objectWillChange
    // 3. Republishes to child's objectWillChange
}
```

When parent publishes changes, child automatically republishes, so views observing child also update.

---

## Solution: Include Parent in Scope Links

### User's Excellent Suggestion ✅

Instead of `subscopes: inout Subscopes`, use a more comprehensive parameter that includes BOTH parent and children.

### Option 1: Rename to "ScopeLinks"

```swift
protocol Reducer {
    associatedtype State
    associatedtype ScopeLinks = NoScopeLinks  // Both parent AND children

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ScopeLinks  // Replaces "subscopes"
    ) throws
}

struct NoScopeLinks {}  // Default: no parent, no children
```

### Child Declares Parent

```swift
struct ChildScopeLinks {
    weak var parent: ReducerStore<ParentReducer>?  // Weak to avoid retain cycle
    // No children for this leaf scope
}

struct ChildReducer: Reducer {
    typealias ScopeLinks = ChildScopeLinks

    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ChildScopeLinks
    ) throws {
        // Access parent state (live reference!)
        if let parent = scopeLinks.parent {
            state.childValue = parent.state.parentValue * 2
        }
    }
}
```

### Parent Declares Children

```swift
struct ParentScopeLinks {
    var child: ReducerStore<ChildReducer>?  // Strong reference
    var settings: ReducerStore<SettingsReducer>?
    // No parent for root scope
}

struct ParentReducer: Reducer {
    typealias ScopeLinks = ParentScopeLinks

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ParentScopeLinks
    ) throws {
        switch when {
        case .createChild:
            let child = ReducerStore<ChildReducer>(
                initialState: ChildState(),
                scopeLinks: ChildScopeLinks(parent: ???)  // HOW TO SET PARENT?
            )
            scopeLinks.child = child
        }
    }
}
```

**Problem:** How does parent set the child's parent link to itself?

---

## Challenge: Setting Up Parent Link

### The Circular Reference Problem

1. Parent creates child: `let child = ReducerStore<ChildReducer>(...)`
2. Child's scopeLinks needs parent reference
3. But parent is creating child, so can't pass `self` yet

### Solution A: Two-Step Initialization

```swift
// Step 1: Create child without parent
let child = ReducerStore<ChildReducer>(initialState: ChildState())

// Step 2: Set parent link
child.setParent(parentStore)  // Custom method

// Step 3: Store child
scopeLinks.child = child
```

**ReducerStore implementation:**
```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    @Published public private(set) var state: R.State
    public var scopeLinks: R.ScopeLinks

    // Helper to set parent after creation
    public func setParent<P>(_ parent: ReducerStore<P>) where R.ScopeLinks: HasParent {
        // Mutate scopeLinks.parent
        scopeLinks.setParent(parent)
    }
}

// Protocol for scope links with parent
protocol HasParent {
    associatedtype ParentStore: ObservableObject
    var parent: ParentStore? { get set }
    mutating func setParent(_ parent: ParentStore)
}
```

### Solution B: Parent Passed to Child Initializer

```swift
// In ParentReducer.update():
let child = ReducerStore<ChildReducer>(
    initialState: ChildState(),
    parent: parentStore  // Pass parent at creation
)
```

**ReducerStore implementation:**
```swift
public init(
    initialState: R.State,
    parent: ParentStore? = nil
) where R.ScopeLinks == ChildScopeLinks<ParentStore> {
    self.state = initialState
    self.scopeLinks = ChildScopeLinks(parent: parent)
}
```

**Problem:** How does parent get reference to itself in the static update method?

### Solution C: Parent Set by Framework

```swift
struct ParentReducer: Reducer {
    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ParentScopeLinks
    ) throws {
        // Create child (no parent yet)
        let child = ReducerStore<ChildReducer>(initialState: ChildState())

        // Framework automatically sets parent when assigned
        scopeLinks.child = child
        // ↑ Assignment triggers: child.scopeLinks.parent = currentStore
    }
}
```

**ReducerStore needs reference to self:**
```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    private var selfReference: ReducerStore<R>?

    public var scopeLinks: R.ScopeLinks {
        didSet {
            // When scopeLinks.child is set, update child's parent
            updateChildParentLinks()
        }
    }

    private func updateChildParentLinks() {
        // Use reflection to find all ReducerStore children
        // Set their parent link to self
    }
}
```

**Problem:** Requires reflection, complex, error-prone.

---

## Recommended Solution: Explicit Helper Method

### API Design

```swift
// In parent update method:
static func update(
    _ when: When,
    state: inout ParentState,
    effectsState: inout EffectsState<When>,
    dependencies: ReducerDependencies,
    scopeLinks: inout ParentScopeLinks
) throws {
    switch when {
    case .createChild:
        // Step 1: Create child
        let child = ReducerStore<ChildReducer>(initialState: ChildState())

        // Step 2: Link parent to child (framework helper)
        scopeLinks.linkChild(child, toParent: dependencies.currentStore())

        // Step 3: Store child
        scopeLinks.child = child
    }
}
```

### Implementation

**Add to ReducerDependencies:**
```swift
protocol ReducerDependencies {
    func resolve<T: Injectable>() throws -> T
    func inject<T>(_ object: T)

    // NEW: Get current store for parent linking
    func currentStore<R: Reducer>() -> ReducerStore<R>?
}
```

**Helper in ScopeLinks protocol:**
```swift
protocol ScopeLinks {
    // Helper to link child to parent
    mutating func linkChild<C: Reducer, P: Reducer>(
        _ child: ReducerStore<C>,
        toParent parent: ReducerStore<P>?
    )
}

// Implementation for parent scope links
extension ParentScopeLinks {
    mutating func linkChild<C: Reducer>(
        _ child: ReducerStore<C>,
        toParent parent: ReducerStore<ParentReducer>?
    ) {
        // Set parent on child's scope links
        if var childLinks = child.scopeLinks as? ChildScopeLinks {
            childLinks.parent = parent
            child.updateScopeLinks(childLinks)
        }
    }
}
```

**Problem:** Still complex, requires type casting.

---

## Alternative: Simpler Two-Level Approach

### Keep Parent Separate from Children

```swift
protocol Reducer {
    associatedtype State
    associatedtype Parent = NoParent
    associatedtype Children = NoChildren

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        parent: Parent,       // Read-only parent reference
        children: inout Children  // Mutable children
    ) throws
}
```

### Child Declares Parent Type

```swift
struct ChildReducer: Reducer {
    typealias Parent = ReducerStore<ParentReducer>
    typealias Children = NoChildren

    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        parent: ReducerStore<ParentReducer>,  // Type-safe, observable!
        children: inout NoChildren
    ) throws {
        // Direct access to parent
        state.value = parent.state.count
    }
}
```

### Parent Declares Children

```swift
struct ParentChildren {
    var child: ReducerStore<ChildReducer>?
}

struct ParentReducer: Reducer {
    typealias Parent = NoParent  // Root has no parent
    typealias Children = ParentChildren

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        parent: NoParent,
        children: inout ParentChildren
    ) throws {
        // Create child - framework handles parent linking
        children.child = ReducerStore<ChildReducer>(initialState: ChildState())
    }
}
```

### ReducerStore Handles Parent Linking Automatically

```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    @Published public private(set) var state: R.State
    public var children: R.Children
    private weak var parentStore: (any ObservableObject)?

    public func update(_ when: When) throws {
        var mutableState = state
        var mutableChildren = children
        let dependencies = ReducerDependenciesImpl(...)

        // Provide parent (self acts as parent for children)
        let parent = createParentReference()

        try R.update(
            when,
            state: &mutableState,
            effectsState: &effectsState,
            dependencies: dependencies,
            parent: parent,  // Parent reference
            children: &mutableChildren
        )

        state = mutableState
        children = mutableChildren

        // After update, wire up parent links for new children
        wireChildParentLinks(from: children)
    }

    private func wireChildParentLinks(from children: R.Children) {
        // Use Mirror to find all ReducerStore properties
        let mirror = Mirror(reflecting: children)
        for child in mirror.children {
            if let childStore = child.value as? any ReducerStoreProtocol {
                childStore.setParentStore(self)
            }
        }
    }
}
```

**Pros:**
- ✅ Separate parent and children conceptually
- ✅ Type-safe parent access
- ✅ Framework handles wiring automatically
- ✅ Observable parent reference

**Cons:**
- ⚠️ More complex signature (4 parameters)
- ⚠️ Requires reflection for auto-wiring
- ⚠️ Need protocol for type erasure

---

## Observation Mechanics

### Key Question: How Does Child View Observe Parent?

**Option 1: Child Republishes Parent Changes**

```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    private var parentCancellable: AnyCancellable?

    func setParentStore(_ parent: any ObservableObject) {
        // Observe parent's objectWillChange
        parentCancellable = (parent.objectWillChange as? ObservableObjectPublisher)?
            .sink { [weak self] _ in
                // When parent changes, child republishes
                self?.objectWillChange.send()
            }
    }
}
```

**Result:** When parent state changes:
1. Parent's `objectWillChange` fires
2. Child's observer triggers
3. Child's `objectWillChange` fires
4. Views observing child re-render

**Pros:**
- ✅ ChildView only needs to observe child
- ✅ Automatic observation chain
- ✅ Works with SwiftUI navigation caching

**Cons:**
- ⚠️ Child re-renders even if it doesn't use parent state
- ⚠️ Performance: unnecessary re-renders
- ⚠️ Hard to optimize

**Option 2: Views Observe Both Parent and Child**

```swift
struct ChildView: View {
    @ObservedObject var child: ReducerStore<ChildReducer>
    @ObservedObject var parent: ReducerStore<ParentReducer>  // Explicit

    var body: some View {
        VStack {
            Text("Child: \(child.state.value)")
            Text("Parent: \(parent.state.count)")
        }
    }
}

// But where does ChildView get parent reference?
// From child.parent!
if let parent = child.parent as? ReducerStore<ParentReducer> {
    ChildView(child: child, parent: parent)
}
```

**Pros:**
- ✅ Efficient - only re-renders when actually needed
- ✅ Explicit dependencies

**Cons:**
- ⚠️ View needs to know about parent
- ⚠️ Boilerplate passing parent around

---

## Recommendation

### Use Combined "ScopeLinks" with Auto-Observation

```swift
protocol Reducer {
    associatedtype State
    associatedtype ScopeLinks = NoScopeLinks

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ScopeLinks
    ) throws
}

// Child declares parent
struct ChildScopeLinks {
    weak var parent: ReducerStore<ParentReducer>?
}

// Parent declares children
struct ParentScopeLinks {
    var child: ReducerStore<ChildReducer>?
}
```

**When child.scopeLinks.parent is set:**
1. ReducerStore observes parent.objectWillChange
2. When parent changes, child.objectWillChange fires
3. Views observing child automatically update

**Implementation:**
```swift
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {
    public var scopeLinks: R.ScopeLinks {
        didSet {
            setupParentObservation()
        }
    }

    private var parentObserver: AnyCancellable?

    private func setupParentObservation() {
        // Extract parent using Mirror
        let mirror = Mirror(reflecting: scopeLinks)
        for (label, value) in mirror.children {
            if label == "parent",
               let parent = value as? any ObservableObject {
                observeParent(parent)
            }
        }
    }

    private func observeParent(_ parent: any ObservableObject) {
        parentObserver = (parent.objectWillChange as? ObservableObjectPublisher)?
            .sink { [weak self] _ in
                self?.objectWillChange.send()  // Republish
            }
    }
}
```

---

## Proposed API (Final)

```swift
// Child
struct ChildScopeLinks {
    weak var parent: ReducerStore<ParentReducer>?
}

struct ChildReducer: Reducer {
    typealias ScopeLinks = ChildScopeLinks

    static func update(
        _ when: When,
        state: inout ChildState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ChildScopeLinks
    ) throws {
        // Access parent state - triggers re-render when parent changes!
        if let parent = scopeLinks.parent {
            state.value = parent.state.count
        }
    }
}

// Parent
struct ParentScopeLinks {
    var child: ReducerStore<ChildReducer>?
}

struct ParentReducer: Reducer {
    typealias ScopeLinks = ParentScopeLinks

    static func update(
        _ when: When,
        state: inout ParentState,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies,
        scopeLinks: inout ParentScopeLinks
    ) throws {
        switch when {
        case .createChild:
            // Framework provides helper
            scopeLinks.child = dependencies.createChildStore(
                ChildReducer.self,
                initialState: ChildState()
            )
            // Auto-wires parent link in child
        }
    }
}
```

---

## Open Questions

1. **Should child always republish parent changes?**
   - YES for simplicity
   - NO for performance (but complex to optimize)
   - **Recommendation:** YES (simple, works)

2. **Weak vs strong parent reference?**
   - MUST be weak to avoid retain cycle
   - **Recommendation:** `weak var parent`

3. **How to handle parent-less root scopes?**
   - ScopeLinks = NoScopeLinks (no parent)
   - Or: `var parent: ReducerStore<ParentReducer>? = nil`
   - **Recommendation:** Optional parent

4. **Should we rename "Subscopes" to "ScopeLinks"?**
   - YES - more accurate (includes parent + children)
   - **Recommendation:** Rename to `ScopeLinks`

---

## Summary

✅ **Include parent in ScopeLinks** (user's suggestion is correct!)
✅ **Auto-observe parent** (republish parent changes to child)
✅ **Type-safe** (parent type declared in ScopeLinks)
✅ **Weak reference** (avoid retain cycles)
✅ **Framework helps** (auto-wire parent when child assigned)

This solves the observation issue while keeping the API clean and type-safe.
