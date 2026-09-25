# Statoscope Production Readiness Audit

**Date:** 2026-03-09 (technical refresh: 2026-09-18, ahead of RC1)
**Status:** 🟡 **REDUCER PATTERN: PRODUCTION READY** / 🔴 **STATOSTORE PATTERN: NOT PRODUCTION READY**
**Reviewer:** Architecture Review

> **2026-09-18 refresh note:** `MiddlewareReducer`/`updateSubstate` changed substantially after
> this audit's original 2026-03-09 date. Issue #4 below is updated to match; the "structurally
> impossible" cycle conclusion still holds. Two new, real risks surfaced since the original
> audit — an event ordering hazard (Issue #5) and a staleness trap in multi-level `@SuperState`
> reads (Issue #6) — both fixed now, not just documented:
> - **Issue #6**: a genuine one-line framework fix (`Sources/StatoscopeMacros/ReducerMacro.swift`,
>   `@SuperState`'s injection), verified by a regression test that fails without it.
> - **Issue #5**: the framework itself changed to eliminate the hazard structurally, matching a
>   unified decision made across Statoscope's sibling ports (`statoscope-zustand`, and a planned
>   `statoscope-android`) — see the "Issue #5" section below for the full rationale. `updateSubstate`
>   now runs *after* the child's own `update()` for the same event, always, with no way to
>   intercept or veto — so `SubstateOutcome`'s `.intercept` case no longer exists; the type itself
>   is gone, replaced by a plain `When?`.
>
> Neither blocks the Reducer pattern's PRODUCTION READY verdict.

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

2. **`MiddlewareReducer.updateSubstate` is also pure** — Parameters are value types only, and
   the signature has changed twice since the original 2026-03-09 audit (`parentState` was
   `inout`, then read-only; the return was a bare `When?`, then `SubstateOutcome<When>`, then
   back to a plain `When?` — see Issue #5 for why):
   ```swift
   static func updateSubstate<Child: Reducer>(
       _ childType: Child.Type,
       childState: Child.State,          // value type, read-only, already post-update
       childWhen: Child.When,
       parentState: State,               // value type, read-only
       dependencies: ReducerDependencies  // no send() access
   ) throws -> When?                      // the delegated reaction, or nil
   ```
   The returned `When?` is the only delegation mechanism — strictly **child → parent**
   direction. It's delivered to the parent's own `update()`, which is the only place `State` is
   ever mutated; there is still no path back to `self`/`send()` from inside `updateSubstate` or
   `update()`, so it cannot cycle back to the child synchronously. `parentState` being read-only
   (rather than `inout`, as in the original audit) *tightens* this guarantee further: a prior
   revision could in principle have mutated parent state directly from `updateSubstate` without
   going through `update()` at all; the current signature makes that a compile error.

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

### 5. ✅ Event ordering hazard in child→parent reactions — RESOLVED by switching to child-first

**Severity:** MEDIUM → **RESOLVED 2026-09-18 (second follow-up)** — real, production-confirmed,
and turned out to have a genuine framework fix once the alternative ordering was analyzed
properly, not just a design-guidance workaround
**Added:** 2026-09-18, after the original audit — not present in the 2026-03-09 version because
this mechanism (then returning a bare `When?`, with no ordering guarantee documented either way)
predates the `SubstateOutcome` API this issue was first found in

#### Original problem (as first found)

`updateSubstate` ran, and any `.react`/`.intercept` reaction it delegated was applied to the
parent's own `update()` **before** the triggering event was forwarded to the child's own
`update()`. A real app (familymealplan) hit this directly: a login screen's `LoginReducer.update()`
guarded `.userSubmitsForm` on `!state.submitting`, where `submitting` was computed from an
ancestor's `Loading` field. The ancestor's `AccountReducer.updateSubstate` reacted to that *same*
`.userSubmitsForm` event with `.react(.signIn(...))`, which set the ancestor's loading state to
`.signingInTo(...)` — before `LoginReducer.update()` ever ran for the event that triggered it.
Every legitimate submit was rejected, because by the time the guard ran, `submitting` was already
`true` — flipped by the reaction to the very event being guarded.

#### Why the first fix attempt (documentation + a pinning test) wasn't the end of it

This audit originally concluded changing the order "would just relocate the hazard rather than
remove it," reasoning that some existing usage depended on the before-forwarding order. That
reasoning didn't hold up once the actual motivating use case for that order — `.intercept` — was
examined directly (`Tests/StatoscopeTests/HierarchicalDelegationReentrancyTests.swift`, which
pins the exact scenario: a parent tearing down the very child subtree an event came from,
needing to prevent that event from still being delivered into the now-torn-down subtree
afterward). Under child-first ordering, **that race cannot occur at all**: the child always
processes its own event on a still-valid, not-yet-torn-down copy of itself, and only afterward
can an ancestor's reaction destroy or replace it. `.intercept` wasn't a safety feature
child-first gives up — it was a workaround for a hazard that stops existing once forwarding
always happens first. Rewriting that exact test to assert the child-first outcome (still safe,
just an ordering the old test wasn't written to expect) confirmed this directly rather than by
argument alone.

Separately, this decision was also made to keep Statoscope's ordering semantics identical across
its sibling ports: `statoscope-zustand`'s `onChildAction(action, childState)` already documents
firing "after every action the child processes," with "the child's already-updated state" — the
opposite of what Swift did until now. A planned `statoscope-android` port would have been a third,
independent choice; unifying on child-first here means all three (present and future) share one
model rather than three teams each re-deriving — or re-discovering the hard way — the same tradeoff.

#### The fix

`Sources/Statoscope/Reducer/Store.swift`'s `updateSubscope` now calls `event.forward()`
**unconditionally first**, then calls `updateSubstate` (whose `childState` parameter is
therefore always the child's post-update state) and applies any returned reaction. `SubstateOutcome`
is removed entirely — `MiddlewareReducer.updateSubstate` returns a plain `When?`, exactly
matching `statoscope-zustand`'s `onChildAction` return shape. There is no `.intercept` equivalent
because there's nothing left to intercept: forwarding is no longer a decision, it always happens,
safely, before any reaction.

#### Mitigation still worth stating even though the hazard is gone

A child's own handler for an event a parent also reacts to now correctly sees pre-reaction
parent state, by construction — the original guidance (use a locally-owned flag rather than a
parent-derived one for a "not already in progress" check) is no longer *necessary* for
correctness, but remains good practice for the unrelated reason that a child generally shouldn't
depend on an ancestor's internal implementation details regardless of ordering.

#### Test coverage

**Rewritten 2026-09-18:** `ReactOrderingRegressionTests.testChildsOwnUpdateRunsBeforeParentReactionForTheSameEvent`
(previously pinned the old, now-removed ordering under a name asserting the opposite) now
asserts the child observes the *pre*-reaction value. `HierarchicalDelegationReentrancyTests`
rewritten similarly — asserts the child's own event applies safely (`pings == 1`) *and* the
ancestor's subsequent teardown still happens (`teardownCount == 1`), proving both are safe
together, by construction, rather than needing one to prevent the other.

**Status:** ✅ **RESOLVED** — genuine framework fix (and API simplification), not a documented
workaround. No known remaining risk. Also unifies ordering semantics with `statoscope-zustand`
and the planned `statoscope-android` port.

---

### 6. ✅ Multi-level `@SuperState` reads can go stale — FIXED

**Severity:** MEDIUM → **RESOLVED 2026-09-18** — real, production-confirmed, and turned out to
have a genuine one-line framework fix rather than only a documentation mitigation
**Impact:** A child's `@SuperState` snapshot of a skipped-level ancestor can silently reflect
stale data
**Added:** 2026-09-18, after the original audit

#### Problem

`@SuperState<X>` resolves by walking the ancestor chain for a `Store<X>` and reading its
`_rawState` directly — always fresh, because `_rawState` is committed immediately after every one
of `X`'s own `update()` calls, before any descendant dispatch. That guarantee is airtight for
data declared **directly** on `X`'s own `State`.

It is not airtight for data reached **through** `X`'s own `State` into one of *its* `@SubState`
fields mirroring a *different*, independently-updated descendant. That mirrored field is a cache,
refreshed only when `X` itself next processes an event — not automatically whenever the mirrored
descendant changes. If events are sent directly to that descendant (bypassing `X`), `X`'s cached
mirror of it goes stale, and anything reading through `X.State.thatMirroredField` sees the stale
value.

#### Confirmed real, not theoretical

Same app, same migration: `AcceptInvitationReducer` (a direct child of `AccountReducer`) declared
`@SuperState var preLanding: PreLandingReducer.State` — skipping its direct parent to read its
*grandparent*, `PreLandingReducer` — then computed `isUserAnonymous` as
`preLanding.account?.profile?.isAnonymous`. `preLanding.account` is `PreLandingReducer`'s own
`@SubState` mirror of `AccountReducer`'s state, refreshed only when `PreLandingReducer` itself
processes an event. Since the profile update was dispatched directly to `AccountReducer` (never
routing back through `PreLandingReducer`), the mirror was stale — `isUserAnonymous` reported
`true` for a user who had just logged in, producing the wrong `CurrentUserType` in a real
invitation-acceptance flow. Fixed by adding a **second** `@SuperState` pointing directly at the
data's actual owner (`AccountReducer`) instead of tunneling through the grandparent's cache.

#### Root cause and fix

`@SuperState`'s macro-generated injection (`Sources/StatoscopeMacros/ReducerMacro.swift`, the
`_superSlots` `inject` closure) read `parentStore._rawState` — the ancestor's raw stored
property. `@SubState`-wrapped fields on that raw struct are unreliable to read directly: the
dirty-flag machinery (`resetDirty`) clears the wrapper's backing value after each of the
ancestor's own `update()` calls, and it's only repopulated with the live child's current data
when going through the ancestor's **computed** `state` property (which calls
`injectIntoParent(_childCache[slot.key], &s)` for each child slot). Reading `_rawState` directly
bypasses that repopulation, so a mirrored field is `nil` or stale depending on timing — not
"frozen at creation time" as originally suspected while writing this section, but functionally
the same production symptom either way.

**Fix:** changed the injection to `parentStore.state` (one token). `Store<R>.state`'s existing
`injectIntoParent` machinery — already used for exactly this purpose when a *direct* parent
reads its *own* children — now also runs for the ancestor being read via a skipped-level
`@SuperState`, so the injected snapshot is always current, however many levels are skipped.

Verified: `swift test` after a clean `rm -rf .build` (to rule out macro-plugin caching, which
initially masked the bug on an incremental build) — 277/277 tests pass with the fix, including
a new regression test that fails without it (confirmed by reverting the one-line change and
re-running: `nil` instead of the expected live value).

Documented as of this session in the `05-Scopes-Reducer` tutorial's "Reacting to child events"
section and in `Overview-article.md` — that prose still holds as *guidance for why the ownership
convention matters*, even though the specific staleness failure mode it was warning about is now
prevented by the framework itself rather than left to discipline alone.

#### Test coverage

**Added 2026-09-18:** `SkipLevelSuperStateStalenessTests.testSkipLevelSuperStateReflectsLiveMiddleStateNotStaleRootMirror`
— a 3-level hierarchy (root → middle → leaf) where the leaf skips its direct parent to read the
root, the middle is mutated directly (bypassing the root, which `.pass`es the event), and the
leaf's skip-level read must still observe the middle's current value. Fails without the fix,
passes with it.

**Status:** ✅ **RESOLVED** — genuine framework fix, not just a documented workaround. No known
remaining risk.

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

### Reducer Pattern Test Coverage (refreshed 2026-09-18, updated again same day)

`MiddlewareReducerTests.swift` grew substantially through this period and now covers:

- ✅ `updateSubstate`'s delegated `When?` reaching the parent's `update()`, with the child's own
  `update()` always having already run first (child-first ordering, since the second follow-up)
- ✅ Multi-level chaining without relay code in intermediate reducers (`testRootInterceptsGrandchildEventDirectlyWithoutForwarding`, `testParentStillInterceptsGrandchildEvents`)
- ✅ Child store lifecycle on reassignment/destruction (recreate always gets a fresh `Store`)
- ✅ `defaultTrigger` firing exactly once per child creation
- ✅ `ReactOrderingRegressionTests` — locks in Issue #5's *current* (child-first) ordering
  contract explicitly, having been rewritten from pinning the old order to pinning the new one
- ✅ `SkipLevelSuperStateStalenessTests` — reproduces and confirms the fix for Issue #6
- ✅ `HierarchicalDelegationReentrancyTests` — rewritten to confirm the teardown-safety scenario
  `.intercept` used to exist for is still safe under child-first ordering, without needing
  `.intercept` at all

**Still open:** none.

- ✅ `ReducerStore<R>` — **removed 2026-09-18.** Deleted `Sources/Statoscope/Reducer/ReducerStore.swift`
  outright (confirmed zero usage in familymealplan, the only real app built on this library, as
  well as in every test/tutorial) and rewrote `Reducer.swift`'s own protocol doc comment to show
  the actual `@Reducer` macro + `Store<R>` pattern instead of the dead one. `ReducerDispatchable.swift`'s
  doc comment updated to drop its stale mention too. 277/277 tests still pass after a clean
  rebuild; DocC build clean.

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

**Reducer Pattern Status:** ✅ APPROVED FOR PRODUCTION (RC1) — Issues #5 and #6 both fixed and
regression-tested. No open, accepted-risk items remain from this audit's Reducer-pattern
findings.

**Statostore Pattern Status:** NOT APPROVED FOR PRODUCTION — Next Review after Phase 1 implementation

---

## Related Documents

- `Tests/StatoscopeTests/StatoscopeAccessControl.swift` - Current known issues
- `MEMORY.md` - Critical issues summary
- `UPDATE_CONTEXT.md` - Proposed compile-time reentrancy fix (if exists)
- `NAVIGATION_ENVIRONMENT_FIX.md` - SwiftUI navigation-layer crash fix and its own known gaps
  (separate from this audit's Reducer-pattern/state-layer scope, same RC1 sign-off treatment)
- `HIERARCHICAL_RESOLUTION_PLAN.md` - The one navigation-layer gap deferred past RC1

## Revision History

- 2026-09-18 (follow-up 3): Resolved Issue #5 for real, not just documented/tested around.
  Switched `MiddlewareReducer.updateSubstate` to child-first ordering: `Store.swift`'s
  `updateSubscope` now calls `event.forward()` unconditionally before checking for a reaction,
  so the child's own `update()` always runs first. `SubstateOutcome` removed entirely —
  `updateSubstate` returns a plain `When?`. `.intercept` no longer exists; its one safety-motivated
  use case (`HierarchicalDelegationReentrancyTests`, preventing a stale event from reaching a
  subtree an ancestor's reaction just tore down) is now handled structurally by the ordering
  itself — rewrote that test to confirm the teardown scenario is still safe without it. Also
  unifies ordering semantics with `statoscope-zustand`'s `onChildAction`, and is the decision
  recorded for the planned `statoscope-android` port. Updated: `MiddlewareReducer.swift`,
  `Store.swift`, `ReducerDispatchable.swift`, the Favorites tutorial fixture and its generated
  docc snippets, `01-05-Scopes-Reducer.tutorial`, `01-03-Middleware-Reducer.tutorial`,
  `Overview-article.md`, and all 6 `MiddlewareReducer` conformances in familymealplan-ios
  (mechanical `.react(x)` → `x`, `.pass` → `nil`; zero `.intercept` usages there, so no logic
  needed redesigning). Verified: clean-build `swift test` (277/277), clean DocC build, and
  familymealplan-ios's own `familymealplanTests` re-run against the updated local package.
- 2026-09-18 (follow-up 2): Removed `ReducerStore<R>` (`Sources/Statoscope/Reducer/ReducerStore.swift`)
  entirely — confirmed unused in familymealplan and every test/tutorial first. Rewrote
  `Reducer.swift`'s protocol doc comment to show the real `@Reducer` + `Store<R>` pattern, and
  fixed the stale mention in `ReducerDispatchable.swift`'s doc comment. 277/277 tests pass after
  a clean rebuild; DocC build clean.
- 2026-09-18 (follow-up): Fixed Issue #6 for real — `Sources/StatoscopeMacros/ReducerMacro.swift`'s
  `@SuperState` injection changed from `parentStore._rawState` to `parentStore.state` (one
  token), so a skipped-level `@SuperState` read is always current instead of depending on
  whether the skipped ancestor happened to process an event of its own recently. Verified via a
  clean `rm -rf .build` + `swift test`: 277/277 pass with the fix; the new regression test fails
  without it. Also added a regression test for Issue #5, pinning its documented ordering
  contract explicitly rather than leaving it to prose. Issue #6 reclassified from "accepted risk"
  to "resolved."
- 2026-09-18: Technical refresh ahead of RC1. Issue #4's code sample updated to the current
  `SubstateOutcome`-based `updateSubstate` signature (`parentState` is now read-only, was
  `inout`; return type is `SubstateOutcome<When>`, was `When?`) — the "structurally impossible"
  cycle conclusion re-verified against it and still holds. Added Issue #5 (event ordering hazard
  in `.react`/`.intercept`, confirmed via a real bug in a production migration) and Issue #6
  (multi-level `@SuperState` staleness trap, confirmed via a second real bug in the same
  migration) — both accepted as non-blocking for RC1, both flagged for fast-follow regression
  tests. Testing Status section refreshed to reflect `MiddlewareReducerTests.swift`'s current
  (2026-08-29) coverage. Noted `ReducerStore<R>` as untested, unused legacy API surface worth
  resolving (not a correctness risk).
- 2026-03-09: Issue #4 (send cycles) confirmed SOLVED for Reducer pattern — static update() and updateSubstate() have no send() access; cycles are structurally impossible. Reducer pattern status upgraded to PRODUCTION READY.
- 2026-03-09: Fixed testing infrastructure — StoreTestPlan WHEN steps now use `_throwingSendImplementation` so MiddlewareReducer.updateSubstate is properly invoked in tests.
- 2026-03-01: Removed Issue #4 (Effect races) - Analysis confirmed it's not a real issue due to actor-based serialization and MainActor guarantees
- 2026-03-01: Added Reducer pattern analysis - Issues #1, #2, #3 are solved/mitigated
- 2026-02-21: Initial audit
