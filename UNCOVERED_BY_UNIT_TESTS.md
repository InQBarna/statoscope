# Uncovered by unit tests

Generated from an `llvm-cov` run scoped to `Sources/Statoscope` + `Sources/StatoscopeTesting`
(macro-plugin code excluded). Trivial guard/early-return lines are not listed here. This file
tracks two different things:

1. **Genuinely ambiguous uncovered areas** — no test was written because the right behavior (or
   whether the code should exist at all) isn't obvious from reading it; needs a human decision.
2. **Discovered bugs** — a new test was written for clearly-intended behavior, the test fails
   because of an actual implementation bug, and per instructions it was **not fixed** — left
   failing/skipped for deliberate TDD later.

## Discovered bugs (new failing tests — do not fix without a deliberate TDD pass)

### `@SuperScope(observed: true)` relay never fires for its own documented use case

- **Test**: `ParentStoreBindingTests.testSuperScopeObservedRelaysParentObjectWillChange`
  (currently failing — times out waiting for `objectWillChange`).
- **Root cause**: `Store<R>._wireSuperSlots()` (`Sources/Statoscope/Reducer/Store.swift`) is only
  ever invoked from `Store<R>.applyChildSlots`, i.e. only when a Reducer child is created via
  `@SubState` on a parent **Reducer's** `State`. `@SuperScope` (`Sources/Statoscope/Reducer/ParentStoreBinding.swift`,
  `Sources/StatoscopeMacros/SuperScopeMacro.swift`) exists specifically so a Reducer's `State` can
  reference a **legacy, not-yet-migrated Statostore parent** — and the only way to host that
  Reducer's `Store` under such a parent is the classic `@Subscope` property wrapper
  (`Sources/Statoscope/Injection/Subscope.swift`), since a plain `Statostore` has no `@SubState`
  slot mechanism at all. `@Subscope` never calls `_wireSuperSlots()`. So `@SuperScope(observed:
  true)`'s relay is wired for a composition shape (Reducer-parent + `@SubState`) that
  `@SuperScope` itself is never used for, and unwired for the one shape it exists for.
- **Fix shape** (not implemented): `Subscope.swift`'s child-assignment path needs to also call
  `(child as? any _SuperSlotWireable)?._wireSuperSlots()` when the assigned child conforms to it
  — mirroring what `Store<R>.applyChildSlots` already does for `@SubState` children. `_SuperSlotWireable`
  is currently `fileprivate` to `Store.swift`; it would need to become at least `internal` (or the
  wiring call moved somewhere both files can reach) to be callable from `Subscope.swift`.

## Ambiguous — needs a human decision, not a test

### `Inject.swift` (`@Inject` property wrapper) — appears dead

`grep` across `Sources/`, `Tests/`, and `Documentation.docc/` found zero usages of `@Inject`
outside its own definition. It's a different property wrapper from `@Injected` (takes
`wrappedValue:` directly, no `Injectable` conformance required, falls back to that literal value)
and looks superseded by `@Injected`/`Injectable`. Options: (a) it's intentionally kept as public
API for a use case not yet exercised in this repo — write tests treating it as supported API, or
(b) it's leftover dead code from before `Injectable` existed — delete it. Not testing it blindly
since which of these is true changes what a "correct" test would even assert.

### `InjectedWithDefault.swift` — appears dead

Same situation as `Inject.swift`: zero usages anywhere outside its own file. Also contains a
`#if false` block (an abandoned caching mechanism) that will never compile either way. Same two
options as above apply.

### `Sources/Statoscope/Helpers/DummyScopeImplementation.swift` — appears dead

`public protocol DummyScopeImplementation: ScopeImplementation` with a default no-op `update`.
Zero adopters anywhere in `Sources/` or `Tests/`. Likely scaffolding left over from an earlier
design; either write a minimal conformance test or remove it.

## Not yet investigated

Coverage gaps in the following files are real (per the `llvm-cov` numbers below) but haven't been
triaged yet as this file is being built up incrementally during an ongoing session:

- `Statoscope/SwiftUI/AutoConnectedView.swift` (19% lines), `StoreView.swift` (0%),
  `SwiftUIBindings.swift` (0%) — SwiftUI View code; may need view-rendering test infra
  (ViewInspector or similar) rather than plain XCTest, which is itself worth a decision.
- `Statoscope/Injection/InjectionTreeNode.swift` (76.6%, 63 missed lines — the largest single gap
  by line count in the whole library).
- `Statoscope/Injection/Superscope.swift` (50%), `InjectionTreeNodeBox.swift` (60%).
- `Statoscope/Logging/StatoscopeLogger.swift` (62.5%).
- `Statoscope/Reducer/ReducerDependencies.swift` (37.5%), `SubState.swift` (63.64%),
  `SuperState.swift` (54.55%).
- `StatoscopeTesting/StoreTestPlan/Fork.swift` (33.33%), `Then.swift` (45.83%),
  `TestPlan+Snapshot.swift` (50%), `XCTAssert+Statoscope.swift` (60%),
  `StoreTestPlan+EffectsFork.swift` (0%).

## Group B: Reducer internals

Scope: `Sources/Statoscope/Reducer/ReducerDependencies.swift`, `SubState.swift`,
`SuperState.swift`, `ChildStoreSlots.swift`, `ReducerInjected.swift` (the "Not yet investigated"
section above lists stale coverage percentages for the first three from an earlier run — see
below for the current state).

New tests were added to close essentially all real gaps in these five files:

- `ReducerDependencies.swift`: `inject<T>(_:)` (previously never called by any test) is now
  exercised by `ReducerTests.testDependenciesInjectRegistersDependencyForLaterResolve` — a
  reducer injects a dependency mid-`update()`, and a later `update()` call resolves it.
  `InjectionError.description` is covered by `ReducerTests.testInjectionErrorDescription`.
- `SubState.swift`: `init(wrappedValue:)` (the initializer the compiler calls for `@SubState var
  child: T? = someValue`, i.e. an inline default at declaration, as distinct from a later
  assignment through the `wrappedValue` setter) is covered by
  `ReducerTests.testSubStateWrappedValueInitializerIsNotDirty`, confirming it does not mark the
  slot dirty per its own doc comment. `Equatable`/`Hashable` conformances are covered by
  `ReducerTests.testSubStateEquatable` / `testSubStateHashable`.
- `SuperState.swift`: the `projectedValue` getter, and `Equatable`/`Hashable` conformances, are
  covered by direct property-wrapper tests in `ReducerTests.swift`
  (`testSuperStateProjectedValueGetterReturnsSelf`, `testSuperStateEquatable`,
  `testSuperStateHashable`), using a small dedicated `Injectable & Hashable` fixture value.
- `ChildStoreSlots.swift`: `EmptyChildStores.init(cache:)` (the default `ChildStores` for a
  Reducer with no `@SubState` children) was never reached because no existing test accessed
  `.children` on such a reducer. Covered by
  `ReducerInjectedProtocolTests.testChildlessReducerExposesEmptyChildStores`, reusing the
  already-childless `AuditedCounter` fixture.
- `ReducerInjected.swift`: the `projectedValue` getter and `Equatable`/`Hashable` conformances are
  covered by direct property-wrapper tests added to `ReducerInjectedProtocolTests.swift`
  (`testReducerInjectedProjectedValueGetterReturnsSelf`, `testReducerInjectedEquatable`,
  `testReducerInjectedHashable`).

No bugs were discovered while writing these tests — all new assertions pass against the existing
implementation.

The only line left uncovered across these five files is the trivial guard branch in
`ReducerDependencies.resolve()` (`guard let node = node else { throw InjectionError.noInjectionTree
}`) — excluded per this file's own header ("Trivial guard/early-return lines are not listed
here"). No genuinely ambiguous or dead code was found in this group.
