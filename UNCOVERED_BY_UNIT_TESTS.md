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

## Group A: Injection internals

Coverage pass over `InjectionTreeNode.swift`, `Superscope.swift`, `InjectionTreeNodeBox.swift`,
`StatoscopeLogger.swift`, and `InjectionStore.swift` (the "not yet investigated" bullets above for
these five files). Most of the real gaps turned out to have clear, testable intended behavior and
got new tests (`InjectTests.swift`, `Tutorial05_Scopes.swift`'s `Favorites.MiddlewareTests`,
`LogsTests.swift`, `InjectionStoreTests.swift`) rather than being ambiguous. The following specific
lines were left uncovered on purpose:

### `InjectionTreeNodeProtocol`'s fatalError default implementations — untestable, not ambiguous

`Sources/Statoscope/Injection/InjectionTreeNode.swift`, the `extension InjectionTreeNodeProtocol`
block providing default `_parentNode`/`_keyPathToSelfOnParent` get/set (both call `fatalError`).
These exist purely so a type that forgets to conform via the real `InjectionTreeNode` (or the
`Optional` conditional conformance) gets a crash with an explanatory message instead of silently
wrong behavior — see the comment "Don't try implementing ChainLinkProtocol...". Calling either
accessor would crash the test process itself; there's no way to assert "this fatalErrors" in plain
XCTest here. Not a behavior question — just not exercisable safely.

### `Superscope.swift`'s subscript setter fatalError branch — untestable in-process

The `else { fatalError("Don't assign values to an injected property wrapper") }` branch (setter,
non-XCTest/non-preview path) can never be reached from inside this test target: the guard is
`NSClassFromString("XCTest") != nil || …`, and that's true for the entire duration of any XCTest
run in this repo. Exercising the `fatalError` branch would require running outside XCTest
altogether, which isn't practical here.

### `InjectionTreeNodeBox.map(expr:)` — the "Optional type" branch (`expr as? InjectionTreeNode?`)

The middle branch of `map`'s three-way cast (`Class type` / `Optional type` / final `else`) never
fires in the `llvm-cov` run. Working through the generic instantiation by hand: for a property
declared `@Subscope var x: X? = ...`, the wrapper's `Value` is `X?` itself, so a nil assignment to
an *already-non-nil* `x` should, by this reasoning, box a `X?.none` as `InjectionTreeNodeProtocol?`
inside `assignChild`, and `expr as? InjectionTreeNode` should fail on that (nil can't produce a
non-optional instance) while `expr as? InjectionTreeNode?` should succeed, landing exactly in this
branch. But this is exactly the shape of "set an optional Subscope back to nil" that several
existing tests already do (e.g. `LogsTests.swift`'s `.childAppeared(false)` case, `child = nil`),
and none of them hit it either — so either the reasoning above is wrong somewhere in how Swift's
dynamic casting actually bridges nested optionals through an existential box (plausible — this is
deep, undocumented runtime cast behavior, not something to assert from static reading alone), or
the real trigger is a different, narrower shape than "any nil assignment". Not confident enough in
either direction to write a test that would actually prove which — a test that "passes" by
accident here would be worse than no test. Leaving for a deliberate follow-up with a debugger/print
in `map` itself to observe the real dynamic types involved.

### `StatoscopeLogger`'s three `print(...)` fallback branches

Each of the three `LOG` overloads has an inner
`if #available(iOS 14.0, *), let logger = loggers[level] { os_log(...) } else { print(...) }`.
The new `testLogFallsBackToOSLogWhenNoReplacementSet` (`LogsTests.swift`) exercises the
`os_log` side of all three overloads directly, but the `print(...)` fallback itself is only
reachable pre-iOS 14 or if `loggers[level]` were somehow missing a key — neither happens on any
OS version this test suite runs on (the dictionary is built from `LogLevel.allCases` up front, so
it can't be missing a key either). Not writing a test for a branch that's structurally unreachable
in this environment.
