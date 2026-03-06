# Spike: Hierarchical Delegation via Extended HierarchialScopeMiddleWare

**Date:** 2026-03-05
**Goal:** Enable safe child-to-parent delegation throughout the scope tree
**Status:** 📋 Planning

---

## Problem Statement

### Current Limitation

Child-to-parent communication requires direct `send()` calls, which:
1. Creates reentrancy issues (Issue #1)
2. Enables send cycles (Issue #4)
3. Violates unidirectional data flow
4. Doesn't work in Reducer pattern (no `self` in static methods)

```swift
// Current problematic approach
func update(_ when: When) {
    switch when {
    case .userCompletedTask:
        parent?.send(.childCompletedTask)  // ❌ Reentrancy! Cycles!
    }
}
```

### Existing Foundation

`HierarchialScopeMiddleWare` already exists but is limited:

```swift
public protocol HierarchialScopeMiddleWare {
    func updateSubscope<Child: ScopeImplementation>(
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws
}
```

**Current behavior (ScopeImplementation.swift:188-217):**
- Child looks for **first parent** implementing protocol
- Only **one parent** intercepts child events
- Designed for **root scope** only

---

## Proposed Solution

### Core Idea: Multi-Level Hierarchical Interception

**Enable ALL parents in the tree to intercept child events:**

1. ✅ Any scope can implement `HierarchialScopeMiddleWare`
2. ✅ Child events bubble up through ALL implementing parents
3. ✅ Parents intercept declaratively (no direct `send()`)
4. ✅ No reentrancy (happens BEFORE child's `update()`)
5. ✅ Works with Reducer pattern

---

## Architecture Design

### Event Flow: Top-Down (Root → Child)

```
User Action
    ↓
Child.send(.userTappedButton)
    ↓
┌─────────────────────────────────────────┐
│ 1. Collect ALL implementing parents    │
│    [Root, Grandparent, ImmediateParent] │
│    (Top-down order)                     │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 2. Call Root FIRST                      │
│    Root.updateSubscope(grandparent, ..) │
│         ↓ BEFORE forwarding             │
│         [Root intercepts: log, auth]    │
│         ↓ forward()                     │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 3. Call Grandparent                     │
│    Grandparent.updateSubscope(parent,..)│
│         ↓ BEFORE forwarding             │
│         [Grandparent intercepts]        │
│         ↓ forward()                     │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 4. Call ImmediateParent                 │
│    Parent.updateSubscope(child, ..)     │
│         ↓ BEFORE forwarding             │
│         [Parent intercepts/delegates]   │
│         ↓ forward()                     │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 5. Execute child's update()             │
│    Child.update(.userTappedButton)      │
└─────────────────────────────────────────┘
    ↓
┌─────────────────────────────────────────┐
│ 6. Return up the chain                  │
│    Parent (AFTER child executed)        │
│         ↑ [Can react to completion]     │
│    Grandparent (AFTER parent)           │
│         ↑ [Can react]                   │
│    Root (AFTER grandparent)             │
│         ↑ [Can react]                   │
└─────────────────────────────────────────┘
```

### Key Insights: Top-Down Flow

**Why top-down is better:**

1. **Root has "first sight"** - Perfect for global concerns (logging, auth, analytics)
2. **BEFORE and AFTER interception** - Each level can react before forwarding AND after child completes
3. **Middleware composition** - Matches traditional middleware patterns
4. **Clear hierarchy** - Root → Grandparent → Parent → Child makes architectural sense

**Safety guarantees:**
- All interception happens BEFORE child's `update()`
- No reentrancy (child hasn't started updating yet)
- Each level controls whether to forward
- Clear BEFORE/AFTER boundaries

---

## Implementation Plan

### Phase 1: Extend Protocol & Collection Logic

**File:** `Sources/Statoscope/ScopeImplementation.swift`

#### 1.1 Protocol Design

Current protocol is already optimal:

```swift
public protocol HierarchialScopeMiddleWare {
    /// Intercept child scope events before they execute
    /// Parent controls forwarding by calling (or not calling) child.update(when)
    func updateSubscope<Child: ScopeImplementation>(
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws
}
```

**No changes needed to protocol** - forwarding control is implicit (just don't call `child.update()` to block).

#### 1.2 Replace `firstHierarchialScopeMiddlewareParent()`

**Current (lines 190-199):**
```swift
func firstHierarchialScopeMiddlewareParent() -> HierarchialScopeMiddleWare? {
    var iterator: InjectionTreeNodeProtocol? = self as? InjectionTreeNodeProtocol
    while iterator != nil {
        if let iteratorIsHierarchialMiddleware = iterator as? HierarchialScopeMiddleWare {
            return iteratorIsHierarchialMiddleware  // ❌ Returns FIRST only
        }
        iterator = iterator?._parentNode
    }
    return nil
}
```

**Proposed:**
```swift
/// Collect ALL parents implementing HierarchialScopeMiddleWare
/// Returns array from root to immediate parent (top-down order)
private func allHierarchialScopeMiddlewareParents() -> [HierarchialScopeMiddleWare] {
    var parents: [HierarchialScopeMiddleWare] = []
    var iterator: InjectionTreeNodeProtocol? = self as? InjectionTreeNodeProtocol

    // Walk up to collect parents
    while iterator != nil {
        iterator = iterator?._parentNode  // Move to parent

        if let parent = iterator as? HierarchialScopeMiddleWare {
            parents.append(parent)
        }
    }

    // Reverse to get top-down order (Root first, immediate parent last)
    return parents.reversed()
}
```

#### 1.3 Update `shouldUseParentEnclosedHierarchialUpdate()`

**Current (lines 201-204):**
```swift
func shouldUseParentEnclosedHierarchialUpdate() -> Bool {
    return firstHierarchialScopeMiddlewareParent() != nil
}
```

**Proposed:**
```swift
func shouldUseParentEnclosedHierarchialUpdate() -> Bool {
    return !allHierarchialScopeMiddlewareParents().isEmpty
}
```

#### 1.4 Rewrite `callParentEnclosedHierarchialUpdate()`

**Current (lines 206-217):** Calls single parent

**Proposed:** Recursive top-down forwarding

```swift
private func callParentEnclosedHierarchialUpdate(_ when: When) throws {
    let parents = allHierarchialScopeMiddlewareParents()
    guard !parents.isEmpty else {
        // No parents, just execute child directly
        try update(when)
        return
    }

    guard let selfAsInjectionNode = self as? InjectionTreeNode else {
        try update(when)
        return
    }

    let selfKeyPathOnParent = selfAsInjectionNode._keyPathToSelfOnParent ?? \Self.self

    // Start with ROOT (first in array)
    // Each parent's updateSubscope() will call the next level
    try parents.first?.updateSubscope(self, when, selfKeyPathOnParent)
}
```

**Inside each parent's `updateSubscope()` implementation:**

```swift
func updateSubscope<Child: ScopeImplementation>(
    _ child: Child,
    _ when: Child.When,
    _ keyPath: AnyKeyPath
) throws {
    // BEFORE forwarding - intercept here
    print("Root intercepted: \(when)")

    // Forward to next level (grandparent → parent → child)
    try child.update(when)  // This recursively calls next parent OR child

    // AFTER child completes - react here
    print("Root completed: \(when)")
}
```

**The magic:** Each `child.update(when)` call either:
1. Calls the next parent's `updateSubscope()` (if more parents exist)
2. Calls the actual child's `update()` (if no more parents)

This creates a natural BEFORE/AFTER sandwich at each level!

---

### Phase 2: Testing Strategy

**File:** `Tests/StatoscopeTests/HierarchicalDelegationTests.swift` (new)

#### 2.1 Test: Single Parent Intercepts Child Event

```swift
final class ParentScope: Statostore, HierarchialScopeMiddleWare {
    @Subscope var child: ChildScope?
    var receivedChildEvents: [ChildScope.When] = []

    enum When {
        case createChild
        case childDelegated(String)
    }

    func updateSubscope<Child: ScopeImplementation>(
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws {
        if let childWhen = when as? ChildScope.When {
            receivedChildEvents.append(childWhen)

            // Delegate to self
            if case .taskCompleted(let task) = childWhen {
                send(.childDelegated(task))
            }
        }

        // Forward to child
        try child.update(when)
    }

    func update(_ when: When) throws {
        switch when {
        case .createChild:
            child = ChildScope()
        case .childDelegated(let task):
            // Handle delegation
            print("Parent received: \(task)")
        }
    }
}

final class ChildScope: Statostore {
    enum When {
        case taskCompleted(String)
    }

    func update(_ when: When) throws {
        // Just update child state
    }
}

// Test
func testParentInterceptsChildEvent() throws {
    let parent = ParentScope()

    try ParentScope.GIVEN { parent }
        .WHEN(.createChild)
        .WITH(\.child) { child in
            child.WHEN(.taskCompleted("task1"))
        }
        .THEN { scope in
            XCTAssertEqual(scope.receivedChildEvents.count, 1)
            // Parent received delegation
        }
        .runTest()
}
```

#### 2.2 Test: Multiple Parents in Chain

```swift
final class RootScope: Statostore, HierarchialScopeMiddleWare {
    @Subscope var parent: ParentScope?
    var interceptedEvents: [String] = []

    func updateSubscope<Child: ScopeImplementation>(...) throws {
        interceptedEvents.append("Root intercepted: \(when)")
        try child.update(when)
    }
}

final class ParentScope: Statostore, HierarchialScopeMiddleWare {
    @Subscope var child: ChildScope?
    var interceptedEvents: [String] = []

    func updateSubscope<Child: ScopeImplementation>(...) throws {
        interceptedEvents.append("Parent intercepted: \(when)")
        try child.update(when)
    }
}

final class ChildScope: Statostore {
    enum When { case action }
    func update(_ when: When) throws {}
}

// Test: Verify both Root and Parent intercept
func testMultipleLevelsIntercept() throws {
    let root = RootScope()
    root.parent = ParentScope()
    root.parent?.child = ChildScope()

    root.parent?.child?.send(.action)

    // Both root and parent should have intercepted
    XCTAssertEqual(root.interceptedEvents.count, 1)
    XCTAssertEqual(root.parent?.interceptedEvents.count, 1)
}
```

#### 2.3 Test: Parent Can Block Events from Reaching Child

```swift
final class AuthParent: Statostore, HierarchialScopeMiddleWare {
    @Subscope var child: ChildScope?
    var blockedEvents: [ChildScope.When] = []

    func updateSubscope<Child: ScopeImplementation>(
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws {
        if let childWhen = when as? ChildScope.When {
            // Block unauthorized events
            if case .unauthorizedAction = childWhen {
                blockedEvents.append(childWhen)
                return  // ← Don't call child.update() - event blocked!
            }
        }

        // Forward allowed events
        try child.update(when)
    }
}

final class ChildScope: Statostore {
    var executedEvents: [When] = []

    enum When {
        case authorizedAction
        case unauthorizedAction
    }

    func update(_ when: When) throws {
        executedEvents.append(when)  // Track what actually executed
    }
}

// Test: Verify child doesn't receive blocked event
func testParentBlocksUnauthorizedEvents() throws {
    let parent = AuthParent()
    parent.child = ChildScope()

    // Authorized event - should reach child
    parent.child?.send(.authorizedAction)
    XCTAssertEqual(parent.child?.executedEvents.count, 1)

    // Unauthorized event - should be blocked
    parent.child?.send(.unauthorizedAction)
    XCTAssertEqual(parent.child?.executedEvents.count, 1)  // Still 1!
    XCTAssertEqual(parent.blockedEvents.count, 1)  // Parent blocked it
}
```

#### 2.4 Test: No Reentrancy Issues

```swift
func testNoReentrancy() throws {
    // Parent intercepts child event
    // Parent sends its own event during interception
    // Verify no reentrancy crash

    let parent = ParentScope()
    parent.child = ChildScope()

    // This should NOT cause reentrancy
    parent.child?.send(.action)

    // Parent's send() during updateSubscope should be safe
    XCTAssertNoThrow(...)
}
```

---

### Phase 3: Integrate with Reducer Pattern

**Challenge:** Reducer pattern uses static methods, no `self`

#### 3.1 Design: MiddlewareReducer Protocol

**Create a dedicated protocol for Reducers that intercept child events:**

```swift
// New protocol in Statoscope
public protocol MiddlewareReducer {
    associatedtype State
    associatedtype When

    /// Called BEFORE child's update() executes
    /// - Parameters:
    ///   - childState: The child's state (type-erased)
    ///   - childWhen: The child's event (type-erased)
    ///   - parentState: Parent's mutable state for modifications
    /// - Returns: Optional parent When to send for delegation
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When?
}
```

**User implements:**

```swift
@Reducer
struct ParentReducer: MiddlewareReducer {
    struct State: Injectable {
        @SubState var child: ChildReducer.State?
        var completedTasks: Int = 0
    }

    enum When {
        case childDelegated(String)
        case updateChild(ChildReducer.When)
    }

    // Implement MiddlewareReducer
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When? {
        // Type-cast to specific child
        if let childWhen = childWhen as? ChildReducer.When {
            switch childWhen {
            case .taskCompleted(let task):
                // React BEFORE child processes event
                parentState.completedTasks += 1
                return .childDelegated(task)  // Delegate to parent

            default:
                return nil  // No delegation needed
            }
        }
        return nil
    }

    // Regular reducer update
    static func update(_ when: When, state: inout State, ...) throws {
        switch when {
        case .childDelegated(let task):
            // Handle delegation
            print("Parent received: \(task)")

        case .updateChild(let childWhen):
            // Forward to child
            // (framework handles this via @SubState)
            break
        }
    }
}
```

**Macro generates:**

```swift
extension ParentReducer {
    public final class Store: Statostore, ObservableObject, HierarchialScopeMiddleWare {
        // ... existing Store code ...

        // ONLY generated if ParentReducer conforms to MiddlewareReducer
        public func updateSubscope<Child: ScopeImplementation>(
            _ child: Child,
            _ when: Child.When,
            _ keyPath: AnyKeyPath
        ) throws {
            // BEFORE: Call static middleware method
            var mutableState = state

            let delegateWhen = try ParentReducer.updateSubscope(
                childState: (child as? ChildReducer.Store)?.state ?? child,
                childWhen: when,
                parentState: &mutableState
            )

            state = mutableState

            // Send delegation event if returned
            if let delegateWhen = delegateWhen {
                send(delegateWhen)
            }

            // FORWARD: Call child's update (may trigger next parent)
            try child.update(when)

            // AFTER: Could add another callback here if needed
            // let afterWhen = try ParentReducer.afterSubscope(...)
        }
    }
}
```

#### 3.2 Macro Changes Required

**File:** `Sources/StatoscopeMacros/ReducerMacro.swift`

1. **Check if Reducer conforms to `MiddlewareReducer` protocol**
   ```swift
   func reducerConformsToMiddleware(in structDecl: StructDeclSyntax) -> Bool {
       guard let inheritanceClause = structDecl.inheritanceClause else {
           return false
       }
       return inheritanceClause.inheritedTypes.contains { inheritedType in
           inheritedType.type.as(IdentifierTypeSyntax.self)?.name.text == "MiddlewareReducer"
       }
   }
   ```

2. **If conformance detected, add to Store class:**
   - Add `HierarchialScopeMiddleWare` to Store's protocol conformance list
   - Generate `updateSubscope()` implementation that:
     - Calls `ParentReducer.updateSubscope()` BEFORE forwarding
     - Sends delegation event if returned
     - Forwards to child via `child.update(when)`

3. **Generated code structure:**
   ```swift
   public final class Store: Statostore, ObservableObject, HierarchialScopeMiddleWare {
       // ^ Added HierarchialScopeMiddleWare

       // ... existing code ...

       // ONLY if MiddlewareReducer conformance:
       public func updateSubscope<Child: ScopeImplementation>(
           _ child: Child,
           _ when: Child.When,
           _ keyPath: AnyKeyPath
       ) throws {
           var mutableState = state

           let delegateWhen = try \(reducerName).updateSubscope(
               childState: child,
               childWhen: when,
               parentState: &mutableState
           )

           state = mutableState

           if let delegateWhen = delegateWhen {
               send(delegateWhen)
           }

           try child.update(when)
       }
   }
   ```

4. **Validation:**
   - If Reducer conforms to `MiddlewareReducer`, verify `updateSubscope()` method exists
   - Emit diagnostic if protocol conformance declared but method missing

---

### Phase 4: Documentation & Examples

#### 4.1 Update CLAUDE.md

Add section: **Child-to-Parent Delegation**

```markdown
### Child-to-Parent Delegation Pattern

Statoscope provides `HierarchialScopeMiddleWare` for safe delegation:

**Traditional Statostore:**
```swift
final class ParentScope: Statostore, HierarchialScopeMiddleWare {
    @Subscope var child: ChildScope?

    func updateSubscope<Child>(_ child: Child, _ when: Child.When, _ keyPath: AnyKeyPath) throws {
        // Intercept child events BEFORE they execute
        if let childWhen = when as? ChildScope.When {
            switch childWhen {
            case .taskCompleted(let task):
                send(.childDelegated(task))  // Delegate to self
            case .unauthorized:
                // Block event - don't forward to child!
                return
            default:
                break
            }
        }

        // Forward to child (or skip to block event)
        try child.update(when)
    }
}
```

**Reducer Pattern:**
```swift
@Reducer
struct ParentReducer: MiddlewareReducer {
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) -> When? {
        if case ChildReducer.When.taskCompleted(let task) = childWhen {
            return .childDelegated(task)
        }
        return nil
    }
}
```

**Blocking Events:**
```swift
// Parent can block child events by not forwarding
func updateSubscope<Child>(...) throws {
    // Check authorization
    guard isAuthorized(when) else {
        return  // Don't call child.update() - event blocked!
    }

    // Forward only if authorized
    try child.update(when)
}
```
```

#### 4.2 Create Tutorial

**File:** `Tests/StatoscopeTests/Examples/Tutorial07_HierarchicalDelegation.swift`

**Practical Example: Todo List with Delegation**

```swift
// Child: Individual Todo Item
@Reducer
struct TodoItemReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var id: String = ""
        var title: String = ""
        var isCompleted: Bool = false
    }

    enum When {
        case toggleComplete
    }

    static func update(_ when: When, state: inout State, ...) throws {
        switch when {
        case .toggleComplete:
            state.isCompleted.toggle()
        }
    }
}

// Parent: Todo List (Intercepts child events)
@Reducer
struct TodoListReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var items: [TodoItemReducer.State] = []
        var completedCount: Int = 0
    }

    enum When {
        case addItem(String)
        case itemToggled(id: String, completed: Bool)
    }

    // Implement MiddlewareReducer - intercept child events
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When? {
        if let itemState = childState as? TodoItemReducer.State,
           let itemWhen = childWhen as? TodoItemReducer.When {

            switch itemWhen {
            case .toggleComplete:
                // Intercept BEFORE child toggles
                let willBeCompleted = !itemState.isCompleted

                // Delegate to parent
                return .itemToggled(id: itemState.id, completed: willBeCompleted)
            }
        }
        return nil
    }

    static func update(_ when: When, state: inout State, ...) throws {
        switch when {
        case .addItem(let title):
            var newItem = TodoItemReducer.State()
            newItem.id = UUID().uuidString
            newItem.title = title
            state.items.append(newItem)

        case .itemToggled(let id, let completed):
            // Parent received delegation from child!
            if completed {
                state.completedCount += 1
            } else {
                state.completedCount -= 1
            }
        }
    }
}

// Test
func testParentCountsCompletedItems() throws {
    try TodoListReducer.Store.GIVEN {
        var state = TodoListReducer.State()
        state.items = [
            TodoItemReducer.State(id: "1", title: "Task 1", isCompleted: false)
        ]
        return TodoListReducer.Store(initialState: state)
    }
    .THEN(\.state.completedCount, equals: 0)
    .WITH(\.state.items[0]) { item in
        item.WHEN(.toggleComplete)  // Child event triggers parent delegation!
    }
    .THEN(\.state.completedCount, equals: 1)  // Parent received delegation
    .runTest()
}
```

**What happens:**
1. User toggles todo item (child event)
2. Parent's `updateSubscope()` intercepts BEFORE child executes
3. Parent sees the toggle and returns `.itemToggled()` delegation event
4. Parent's `send(.itemToggled())` updates completed count
5. Child's `update()` executes and toggles state

**Result:** Parent and child stay in sync via delegation, no direct `send()` calls!

---

### Phase 5: Update Production Readiness Audit

**File:** `PRODUCTION_READINESS_AUDIT.md`

#### Update Issue #4

**Current:**
```
### 4. ⚠️ Parent-Child Send Cycles
**Severity:** HIGH
```

**Updated:**
```
### 4. ⚠️ Parent-Child Send Cycles

**Status:** ✅ **SOLVED via HierarchialScopeMiddleWare**

**Solution:** Use hierarchical delegation pattern instead of direct `send()`:

- ✅ Parent implements `HierarchialScopeMiddleWare`
- ✅ Parent intercepts child events BEFORE child update
- ✅ No reentrancy (happens before child processes)
- ✅ No cycles (parent doesn't trigger child events)
- ✅ Works with Reducer pattern

**Recommended Pattern:**
[Show example]

**Legacy Pattern (Unsafe):**
[Show anti-pattern with direct send]
```

---

## Implementation Checklist

### Phase 1: Core Extension
- [ ] Update `allHierarchialScopeMiddlewareParents()` to collect all parents
- [ ] Update `callParentEnclosedHierarchialUpdate()` to call all parents
- [ ] Add optional `shouldForwardToParent` control
- [ ] Verify existing tests still pass

### Phase 2: Traditional Statostore Tests
- [ ] Test single parent intercepts child
- [ ] Test multiple parents in chain (grandparent, great-grandparent)
- [ ] Test propagation control
- [ ] Test no reentrancy issues
- [ ] Test with complex scope trees (3+ levels)

### Phase 3: Reducer Pattern Integration
- [ ] Design `onChildEvent()` callback API
- [ ] Update `@Reducer` macro to detect callback
- [ ] Generate `HierarchialScopeMiddleWare` conformance
- [ ] Test Reducer pattern delegation
- [ ] Compare Reducer vs Statostore ergonomics

### Phase 4: Documentation
- [ ] Update CLAUDE.md with delegation patterns
- [ ] Create Tutorial07_HierarchicalDelegation.swift
- [ ] Add API documentation to protocol
- [ ] Create migration guide from direct `send()` to delegation

### Phase 5: Production Readiness
- [ ] Update PRODUCTION_READINESS_AUDIT.md
- [ ] Mark Issue #4 as SOLVED
- [ ] Add best practices section
- [ ] Performance testing (overhead of parent chain)

---

## Open Questions

1. **Order of parent calls:** ✅ **RESOLVED**
   - ✅ **Top-down (root first)** - Root has "first sight", better middleware composition
   - Root → Grandparent → Parent → Child

2. **Reducer protocol design:** ✅ **RESOLVED**
   - ✅ **MiddlewareReducer protocol** - Explicit, type-safe, clear API
   - Forces implementation of `updateSubscope()` method

3. **BEFORE vs AFTER interception:**
   - Currently: Only BEFORE (via `updateSubscope()`)
   - Future: Add `afterSubscope()` callback for post-execution reactions?
   - Use case: Cleanup, metrics after child completes

4. **Blocking/Filtering events:** ✅ **RESOLVED**
   - ✅ Parent controls forwarding by **not calling** `child.update(when)` in `updateSubscope()`
   - Use case: Auth middleware blocks unauthorized events
   - Pattern: Early return without calling `child.update()` blocks the event

5. **Performance:**
   - What's the overhead of walking parent chain?
   - Should we cache parent chains?
   - Benchmark: <5% overhead acceptable

6. **Error handling:**
   - If parent's `updateSubscope()` throws, should child's `update()` still run?
   - **Answer: NO** - parent interception failure should abort child update
   - Error propagates up and operation fails safely

---

## Success Criteria

✅ **Functionality:**
- All parents in tree can intercept child events
- No reentrancy issues
- Works with Reducer pattern

✅ **Performance:**
- Parent chain walking adds <5% overhead
- No memory leaks

✅ **Usability:**
- Clear, intuitive API
- Less code than direct `send()` approach
- Type-safe delegation

✅ **Safety:**
- Eliminates send cycles
- Compile-time guarantees (Reducer pattern)
- Clear architectural pattern

---

## Alternative Approaches Considered

### A. Effect-Based Delegation
- Child uses effects to notify parent
- **Rejected:** Too complex, async boundary

### B. Shared Event Bus
- Redux-style global dispatcher
- **Rejected:** Loses scope encapsulation

### C. Parent Polling
- Parent periodically checks child state
- **Rejected:** Inefficient, not reactive

### D. Callback Injection
- Parent passes callbacks to child at creation
- **Rejected:** Verbose, tight coupling

**Chosen: HierarchialScopeMiddleWare extension** provides best balance of safety, performance, and ergonomics.

---

## Timeline Estimate

- **Phase 1 (Core):** 4 hours
- **Phase 2 (Tests):** 6 hours
- **Phase 3 (Reducer):** 8 hours
- **Phase 4 (Docs):** 4 hours
- **Phase 5 (Audit):** 2 hours

**Total:** ~24 hours (3 days)

---

## Next Steps

1. ✅ **Approve this plan**
2. Create feature branch: `feature/hierarchical-delegation`
3. Implement Phase 1 (core extension)
4. Write tests for Phase 2
5. Verify no regressions
6. Continue with Reducer integration

**Ready to proceed?**
