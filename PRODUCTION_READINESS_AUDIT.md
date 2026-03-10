# Statoscope Production Readiness Audit

**Date:** 2026-03-09
**Status:** 🟡 **REDUCER PATTERN: PRODUCTION READY** / 🔴 **STATOSTORE PATTERN: NOT PRODUCTION READY**
**Reviewer:** Architecture Review

## Executive Summary

The **traditional Statostore pattern** has critical architectural issues that violate the framework's unidirectional data flow principle. The **Reducer pattern** (with `@Reducer` macro) solves all of them by design.

### Pattern Comparison

| Pattern | Issue #1 Reentrancy | Issue #2 Direct update() | Issue #3 _updating flag | Issue #4 Send cycles | Production Ready? |
|---------|---------------------|--------------------------|------------------------|---------------------|-------------------|
| **Statostore (traditional)** | ❌ Critical | ❌ Critical | ❌ Critical | ❌ Critical | **NO** |
| **Reducer (with @Reducer macro)** | ✅ **Solved** | ✅ **Solved** | ✅ Low Risk | ✅ **Solved** | ✅ **YES** |

**Recommendations:**

- **Statostore Pattern:** ❌ Do NOT use in production until all critical issues are resolved
- **Reducer Pattern:** ✅ **PRODUCTION READY** — All four critical issues are solved by design

---

## 🎯 Reducer Pattern Impact Assessment

**Status:** ✅ **PRODUCTION READY** - All four critical issues are **solved by design**

The **Reducer pattern** (introduced with the `@Reducer` macro) provides **compile-time safety** that eliminates all critical issues:

| Issue | Traditional Statostore | Reducer Pattern | Status |
|-------|----------------------|----------------|--------|
| **#1 Reentrancy** | ❌ Runtime only | ✅ **Compile-time protection** | ✅ **SOLVED** |
| **#2 Direct update()** | ❌ Public method | ✅ Static/Internal | ✅ **SOLVED** |
| **#3 _updating flag** | ❌ assertionFailure() | ⚠️ **Edge cases only** | ⚠️ **LOW RISK** |
| **#4 Send cycles** | ❌ Possible | ✅ **Structurally impossible** | ✅ **SOLVED** |

### Why Reducer Pattern Is Safer

**Issue #1 - Compile-Time Protection:**
```swift
// Traditional Statostore (vulnerable)
func update(_ when: When) throws {
    self.send(.delayFinished)  // ❌ Compiles! Reentrancy possible
}

// Reducer pattern (safe)
static func update(_ when: When, state: inout State, ...) throws {
    self.send(.delayFinished)  // ✅ Won't compile - no 'self'!
}
```

**Issue #2 - Static Methods Are Harmless:**
- Static `Reducer.update()` is a pure function - safe to call directly
- Instance `Store.update()` is `@_spi(Internal)` - protected from user code

**Issue #3 - Dramatically Reduced Risk:**

The `_updating` flag issue **cannot occur** in normal Reducer usage because:
- ✅ Can't call `send()` during static `update()` (compile error)
- ✅ No `self` reference available to break reentrancy
- ✅ Main attack vector is blocked at compile time

The flag would only trigger in **exotic edge cases**:
- Concurrent `send()` calls from multiple threads (should use MainActor)
- Framework bugs (not user code bugs)

**Recommendation for Reducer Pattern Users:** Issue #3 is **LOW RISK** and can be safely ignored for most applications.

---

## Critical Issues

### 1. ⚠️ No Reentrancy Protection

**Severity:** CRITICAL
**Impact:** Breaks unidirectional flow, causes unpredictable state
**File:** `Tests/StatoscopeTests/StatoscopeAccessControl.swift:44-45`

#### Problem

`send()` can be called during `update()`, violating the fundamental principle of unidirectional data flow:

```swift
func update(_ when: When) throws {
    // ❌ This compiles and runs, but breaks unidirectional flow!
    self.send(.delayFinished)
}
```

#### Why This Is Dangerous

1. **Breaks Event Ordering:** Events are processed out of order
2. **State Corruption:** Multiple simultaneous state mutations
3. **Middleware Bypass:** Inner send() bypasses outer middleware
4. **Effect Chaos:** Effects may fire in wrong order or multiple times

#### Example of Failure

```swift
func update(_ when: When) throws {
    switch when {
    case .increment:
        count += 1  // count = 1
        send(.double)  // ⚠️ Reenters update!
        // When we return here, count might be 2, 4, or anything

    case .double:
        count *= 2  // count = 2? 4? Depends on timing!
    }
}
```

#### Current "Protection" (Insufficient)

There's an `_updating` flag that only guards `enqueue()`:

```swift
// In EffectsState.swift (conceptual)
guard !_updating else {
    assertionFailure("Cannot enqueue effects during update")
    return
}
```

**Why this doesn't help:**
- `assertionFailure()` is stripped in Release builds
- Only guards `effectsState.enqueue()`, not `send()`
- Doesn't prevent the actual reentrancy

#### Recommended Fix

**Option A: Runtime Protection (Statostore)**
```swift
private var _updating = false

public func send(_ when: When) {
    guard !_updating else {
        fatalError("Reentrancy detected: send() called during update()")
    }
    _updating = true
    defer { _updating = false }
    // ... actual send logic
}
```

**Option B: Compile-Time Protection (Preferred) ✅ IMPLEMENTED**

**Use the Reducer Pattern** - this issue is **SOLVED** by design:

```swift
@Reducer
struct MyReducer {
    struct State: Injectable {
        var count: Int = 0
    }

    enum When {
        case increment
    }

    // ✅ Static method - no self, no send()!
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        // Impossible to call send() here - no self reference!
        state.count += 1
    }
}
```

**Status for Reducer Pattern:** ✅ **RESOLVED** - Compile-time protection eliminates this entire class of bugs.

---

### 2. ⚠️ Direct update() Calls Allowed

**Severity:** CRITICAL
**Impact:** Bypasses middleware and effects handling
**File:** `Tests/StatoscopeTests/StatoscopeAccessControl.swift:50-51`

#### Problem

`update()` is a public method and can be called directly:

```swift
func update(_ when: When) throws {
    // ❌ This compiles and bypasses everything!
    try self.update(.otherEvent)
}
```

#### Why This Is Dangerous

1. **Middleware Bypass:** Direct call skips all middleware
2. **No Effect Triggering:** Effects won't be triggered
3. **Breaks Testing:** Test assertions can't track direct calls
4. **Debugging Nightmare:** Event flow is hidden

#### Example of Failure

```swift
let store = MyStore()
    .addMiddleWare { _, when, forward in
        print("Event: \(when)")  // For debugging
        try forward(when)
    }

// Via send() - middleware runs
store.send(.increment)  // ✅ Prints "Event: increment"

// Direct call - middleware skipped!
try store.update(.increment)  // ❌ Silent! No middleware!
```

#### Recommended Fix

**Option A: Make update() Internal (Statostore)**

```swift
@_spi(Internal)
public func update(_ when: When) throws {
    // Only accessible to framework internals
}
```

**Option B: Use Reducer Pattern ✅ IMPLEMENTED**

The Reducer pattern **solves this by design**:

```swift
@Reducer
struct MyReducer {
    // Static method - harmless to call directly (pure function)
    static func update(_ when: When, state: inout State, ...) throws {
        // No side effects, no middleware bypass
        // Just a pure state transformation
    }
}

// Generated Store has internal instance method
extension MyReducer {
    public final class Store {
        @_spi(Internal)  // ✅ Protected!
        public func update(_ when: When) throws {
            // Calls static method, triggers effects, etc.
        }
    }
}
```

**Why this works:**
1. **Static method** is a pure function - calling it directly is harmless
2. **Instance method** is `@_spi(Internal)` - requires framework access
3. **User code** has no way to bypass middleware

**Status for Reducer Pattern:** ✅ **RESOLVED** - No way to bypass middleware from user code.

---

### 3. ⚠️ Insufficient _updating Flag

**Severity:** HIGH
**Impact:** No protection in Release builds
**File:** `Sources/Statoscope/Effects/EffectsState.swift` (conceptual)

#### Problem

The `_updating` flag uses `assertionFailure()` which is stripped in Release:

```swift
guard !_updating else {
    assertionFailure("Cannot enqueue during update")  // ⚠️ Gone in Release!
    return
}
```

#### Why This Is Dangerous

1. **Debug vs Release Behavior:** Different behavior in Debug vs Release
2. **Production Failures:** Bugs only appear in production
3. **False Confidence:** Tests pass in Debug, fail in Release

#### Recommended Fix

**For Statostore Pattern:**

Use `precondition()` or `fatalError()` for non-recoverable errors:

```swift
guard !_updating else {
    precondition(false, "Reentrancy detected")  // ✅ Works in Release!
    // or
    fatalError("Reentrancy detected")
}
```

#### Status for Reducer Pattern

⚠️ **NOT AN ISSUE** in normal Reducer usage

The `_updating` flag **cannot be triggered** when using the Reducer pattern because:

1. ✅ **Issue #1 is solved** - Can't call `send()` during static `update()` (compile error)
2. ✅ **No reentrancy path** - The main attack vector is blocked at compile time
3. ✅ **Normal enqueue() is allowed** - The flag doesn't prevent `effectsState.enqueue()` during update (that's the normal pattern!)

**The flag would only trigger in exotic edge cases:**
- Concurrent `send()` from multiple threads (use `@MainActor` to prevent)
- Framework implementation bugs (not user code bugs)
- Extremely unusual direct access to internal APIs

**Recommendation for Reducer users:** This issue can be **safely ignored** - your code cannot trigger it under normal circumstances.

**Impact level:** LOW (was CRITICAL for Statostore)

---

### 4. ⚠️ Parent-Child Send Cycles

**Severity:** HIGH (Statostore) / ✅ **N/A (Reducer)**
**Impact:** Infinite loops, stack overflow
**File:** None (architectural issue)

#### Problem (Statostore only)

Nothing prevents parent-child send cycles in traditional Statostore:

```swift
// Parent
func update(_ when: When) {
    child.send(.parentUpdated)
}

// Child
func update(_ when: When) {
    parent.send(.childUpdated)  // ⚠️ Infinite loop!
}
```

#### Why This Is Dangerous

1. **Stack Overflow:** Recursive calls until crash
2. **Infinite Events:** Events ping-pong forever
3. **Hard to Debug:** Cycle may be indirect (A→B→C→A)

#### Status for Reducer Pattern

✅ **STRUCTURALLY IMPOSSIBLE** — Parent-child send cycles cannot occur in the Reducer pattern:

1. **`static update()` has no `self`** — Cannot reference any Store, cannot call `send()`:
   ```swift
   static func update(_ when: When, state: inout State, ...) throws {
       // No 'self'. No store reference. No send() possible.
       state.count += 1  // Only pure state mutations and effect enqueuing
   }
   ```

2. **`MiddlewareReducer.updateSubstate` is also pure** — Parameters are value types only:
   ```swift
   static func updateSubstate<Child: Reducer>(
       _ childType: Child.Type,
       childState: Child.State,       // value type, read-only
       childWhen: Child.When,
       parentState: inout State,      // value type
       dependencies: ReducerDependencies  // no send() access
   ) throws -> When?                  // return value only, no send()
   ```
   The return `When?` is the only delegation mechanism — strictly **child → parent** direction.
   The framework calls `self.send(delegateWhen)` after `updateSubstate` returns, under controlled conditions, and it cannot cycle back to the child synchronously.

3. **The only path to parent → child communication is async effects** — effect completions
   are dispatched via `Task` and processed on the next run loop iteration, never creating
   synchronous cycles.

**Recommendation for Reducer Pattern:** This issue is ✅ **RESOLVED** — structurally impossible by the design of the static function API.

#### Recommended Fix (Statostore only)

**Option A: Cycle Detection**
```swift
private var _eventStack: [String] = []

func send(_ when: When) {
    let eventId = "\(type(of: self)).\(when)"
    guard !_eventStack.contains(eventId) else {
        fatalError("Send cycle detected: \(_eventStack + [eventId])")
    }
    _eventStack.append(eventId)
    defer { _eventStack.removeLast() }
    // ... process event
}
```

**Option B: Event Queue (Preferred)**

Queue all events and process serially:

```swift
private var _eventQueue: [When] = []
private var _processing = false

func send(_ when: When) {
    _eventQueue.append(when)
    if !_processing {
        processQueue()
    }
}
```

---

## Additional Concerns

### Non-Critical Issues

1. **addMiddleWare() callable during update()** (Line 53-54 in StatoscopeAccessControl.swift)
   - Severity: MEDIUM
   - Can modify middleware chain during execution

2. **injectObject() callable during update()** (Line 63 in StatoscopeAccessControl.swift)
   - Severity: MEDIUM
   - Can modify injection tree mid-update

3. **_parentNode accessible during update()** (Line 57 in StatoscopeAccessControl.swift)
   - Severity: LOW
   - Could enable dangerous scope tree manipulation

---

## Testing Status

### Current Test Coverage

- ✅ Basic state updates work
- ✅ Effects are triggered
- ✅ Middleware intercepts events
- ✅ Dependency injection works

### Missing Test Coverage

- ❌ Reentrancy protection (Statostore only)
- ❌ Parent-child send cycles (Statostore only — not applicable to Reducer)
- ❌ Direct update() call detection (Statostore only)
- ❌ Release build behavior validation

### Reducer Pattern Test Coverage (as of 2026-03-09)

- ✅ MiddlewareReducer.updateSubstate is invoked during WHEN test steps
  (fixed: StoreTestPlan now uses `_throwingSendImplementation` which respects the
  `HierarchialScopeMiddleWare` chain, previously bypassed with `_unsafeSendImplementation`)
- ✅ Multi-level middleware chain tested
- ✅ Child store lifecycle (wireChildren) tested
- ✅ Delegation and selective interception tested

---

## Recommended Action Plan

### For Reducer Pattern Users (Recommended)

**Status:** ✅ **PRODUCTION READY**

✅ **All critical issues addressed:**
- Issue #1: Compile-time reentrancy protection (static update, no self)
- Issue #2: Static methods are pure functions + instance method is @_spi(Internal)
- Issue #3: Low risk — main attack vector blocked at compile time
- Issue #4: Structurally impossible — static update() and updateSubstate() cannot call send()

**Remaining best practices:**
1. Use `@MainActor` or ensure `send()` is always called from main thread
2. Avoid infinite effect chains (logic bugs, not framework issues)
3. Consider `@MainActor` annotations on Store for thread safety guarantees

### For Statostore Pattern Users (Legacy)

**Status:** ❌ **NOT PRODUCTION READY**

### Phase 1: Immediate (Block Production Use)

1. Add runtime reentrancy guard with `fatalError()`
2. Make `update()` internal via `@_spi(Internal)`
3. Add cycle detection to `send()`

### Phase 2: Short-term (Stabilization)

1. Implement serial effect queue
2. Add comprehensive reentrancy tests
3. Document safe usage patterns

### Phase 3: Long-term (Recommended Migration)

1. ✅ **Migrate to Reducer pattern** (compile-time safety already implemented!)
2. Actor-based effect execution (future enhancement)
3. Event queue architecture (future enhancement)

---

## Sign-off

**Reducer Pattern Status:** ✅ APPROVED FOR PRODUCTION

**Statostore Pattern Status:** NOT APPROVED FOR PRODUCTION — Next Review after Phase 1 implementation

---

## Related Documents

- `Tests/StatoscopeTests/StatoscopeAccessControl.swift` - Current known issues
- `MEMORY.md` - Critical issues summary
- `UPDATE_CONTEXT.md` - Proposed compile-time reentrancy fix (if exists)

## Revision History

- 2026-03-09: Issue #4 (send cycles) confirmed SOLVED for Reducer pattern — static update() and updateSubstate() have no send() access; cycles are structurally impossible. Reducer pattern status upgraded to PRODUCTION READY.
- 2026-03-09: Fixed testing infrastructure — StoreTestPlan WHEN steps now use `_throwingSendImplementation` so MiddlewareReducer.updateSubstate is properly invoked in tests.
- 2026-03-01: Removed Issue #4 (Effect races) - Analysis confirmed it's not a real issue due to actor-based serialization and MainActor guarantees
- 2026-03-01: Added Reducer pattern analysis - Issues #1, #2, #3 are solved/mitigated
- 2026-02-21: Initial audit
