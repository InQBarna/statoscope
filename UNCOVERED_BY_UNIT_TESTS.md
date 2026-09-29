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

### `takeSnapshot()` doesn't block re-entrant events during rendering, unlike every automatic snapshot point

- **Test**: `StatoscopeTestingSnapshot.testExplicitTakeSnapshot`
  (currently failing — `XCTFail("we don't want on Appear to be called on snapshot method")`).
- **Root cause**: `StoreTestPlan.safeSnapshot(sut:name:)` (`StoreTestPlan.swift`) is what installs a
  middleware on every scope in the tree that blocks forwarding of any event received while
  `takingSnapshot == true`, and it's this flag — set immediately before calling `snapshot?(sut,
  name)` and reset in a `defer` right after — that keeps SwiftUI side effects (like `.onAppear`
  firing during `NSHostingView`/`UIHostingController` rendering) from reaching `update(_:)` and
  corrupting the scope under test. Every *automatic* snapshot call (the initial "GIVEN" snapshot
  and the one taken after each `WHEN` step, both in `StoreTestPlan.runAllSteps`) goes through
  `safeSnapshot` and is correctly protected. `takeSnapshot()` (`TestPlan+Snapshot.swift`) instead
  calls `self.snapshot?(sut, name)` directly from its `Step` closure, bypassing `safeSnapshot`
  entirely — so `takingSnapshot` is never set to `true` for this call, and the very re-entrancy
  the mechanism exists to prevent goes right through, even though `takeSnapshot()`'s whole purpose
  (per its name and its use as a manual counterpart to the automatic snapshot points) is to behave
  identically to them.
- **Fix shape** (not implemented): `takeSnapshot()`'s step closure should call
  `self.safeSnapshot(sut: sut, name: name)` instead of `self.snapshot?(sut, name)` directly — but
  `safeSnapshot` is currently declared in an `internal extension StoreTestPlan` in `StoreTestPlan.swift`
  and both files are already in the same module, so no visibility change should even be needed;
  this looks like a straightforward oversight (invoking the closure directly instead of the
  wrapper) rather than a structural blocker.

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

## Group C: Testing DSL (StatoscopeTesting)

Coverage pass over `Fork.swift`, `Then.swift`, `TestPlan+Snapshot.swift`, `XCTAssert+Statoscope.swift`,
`StoreTestPlan+EffectsFork.swift`, `Given.swift`, and `ScopeTreeRetrieval.swift`. Most gaps were
missing scenarios in already-existing test files (extended in place: `StatoscopeTestingForkWithTests.swift`,
`StatoscopeTestingEffectsTests.swift`, `StatoscopeTestingThenTests.swift`, `StatiscopeTestingSnapshot.swift`,
`ScopeTreeRetrievalTests.swift`). One item below was left undone as genuinely ambiguous/dead code.

### `GIVEN<Store: ScopeImplementation>(_:)` free function (`Given.swift`, lines 12-16) — appears dead

This is a top-level `GIVEN { ... }` entry point, distinct from the two extension-based `.GIVEN`
static methods (`ScopeImplementation.GIVEN` and `Store.GIVEN`) that every single test in the suite
actually uses. `grep -rn "\bGIVEN(" Tests/ | grep -v "\.GIVEN("` across the whole `Tests/` directory
returns zero hits — nobody calls the free function form anywhere, including in the tutorials/examples
that exercise nearly every other public testing entry point. Its behavior is trivially identical to
`ScopeImplementation.GIVEN` (both just build a `StoreTestPlan(given: builder)`), so this isn't
ambiguous in the "what would the test assert" sense — it's ambiguous in the "should this API exist
at all" sense, same shape as the `Inject.swift`/`InjectedWithDefault.swift` entries above. Options:
(a) it's intentionally kept as an alternative call syntax for some external caller/use case not
present in this repo — write a direct test for it, or (b) it's a leftover first-draft entry point
superseded by the extension-based `.GIVEN` methods once those were added — delete it. Not writing a
test blindly since which of these is true determines whether the "correct" fix is a test or a
deletion.
