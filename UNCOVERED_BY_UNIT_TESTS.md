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

## Group E: SwiftUI (`Sources/Statoscope/SwiftUI/`) — triaged

`SwiftUIBindings.swift` and `StoreView.swift`'s non-rendering surface are now fully covered
(`SwiftUIBindingsTests.swift`, `StoreViewTests.swift`) — none of that code actually depends on
SwiftUI's render engine, it's all plain `Binding(get:set:)` construction over closures, testable
by reading/writing `.wrappedValue` directly. `ReducerStoreRegistry`
(`AutoConnectedView.swift`) — a plain `ObservableObject` holding a per-type weak-reference stack,
also render-independent — is now covered too (`ReducerStoreRegistryTests.swift`): push/current
keyed-by-type lookup, re-push-moves-to-top, weak-deallocation skip-over, and the deferred
`objectWillChange` scheduling.

### Ambiguous — needs an infrastructure decision, not a test

The remaining uncovered surface in `AutoConnectedView.swift` — `ReducerStoreView`,
`AutoConnectedView`, `_ConnectedChildView`, `ReducerObservedView`, `_ReducerChildObservingView`,
`ReducerRegistryCapture`, `_ReducerRegistryObservingCapture`, `_ReducerChildViewConnector`,
`ReducerEnvironmentCapture` — is all in `body` implementations that resolve `@EnvironmentObject`
and rely on SwiftUI's real environment-propagation behavior (including, per their own doc
comments, specific `NavigationStack`/lazy-destination-evaluation semantics that were "confirmed
device-tested" rather than derivable from reading the code alone). Plain XCTest can construct
these View structs and read their stored properties (not useful here — the logic under test is
entirely inside `body`), but actually exercising `body` needs a real SwiftUI rendering host.
`Package.swift` has no dependency today on ViewInspector, a snapshot-testing library, or any
other view-rendering test harness — adding one is a real infrastructure decision (which library,
whether to add a `StatoscopeTestingUI`-style test target, CI implications for a UI-capable
runner) rather than something to default into while writing missing unit tests. Similarly,
`StoreView.body`/`StoreView<S,V>` itself (`StoreView.swift`) and the `body` of the
`StoreViewProtocol`-conforming test fixtures already added are equally out of reach without the
same infrastructure — only their non-rendering init/binding logic is covered.

## Not yet investigated

Coverage gaps in the following files are real (per the `llvm-cov` numbers below) but haven't been
triaged yet as this file is being built up incrementally during an ongoing session:

- `Statoscope/Injection/InjectionTreeNode.swift` (76.6%, 63 missed lines — the largest single gap
  by line count in the whole library).
- `Statoscope/Injection/Superscope.swift` (50%), `InjectionTreeNodeBox.swift` (60%).
- `Statoscope/Logging/StatoscopeLogger.swift` (62.5%).
- `Statoscope/Reducer/ReducerDependencies.swift` (37.5%), `SubState.swift` (63.64%),
  `SuperState.swift` (54.55%).
- `StatoscopeTesting/StoreTestPlan/Fork.swift` (33.33%), `Then.swift` (45.83%),
  `TestPlan+Snapshot.swift` (50%), `XCTAssert+Statoscope.swift` (60%),
  `StoreTestPlan+EffectsFork.swift` (0%).

(As of this writing, four parallel agents are investigating the InjectionTreeNode/Superscope/
Logger group, the Reducer-internals group, the Testing-DSL group, and the Effects/misc group
respectively, on separate worktree branches to be merged back into `test/coverage-analysis`.)
