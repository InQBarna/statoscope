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

### `@SuperScope(observed: true)` relay never fired for its own documented use case — FIXED

Was: `Store<R>._wireSuperSlots()` was only ever invoked from `Store<R>.applyChildSlots` (the
`@SubState`-on-a-Reducer-parent path), never from `@Subscope` (the classic-pattern property
wrapper that's the *only* way to host a Reducer `Store` under a legacy, not-yet-migrated
Statostore parent — `@SuperScope`'s whole reason to exist). Investigating the fix turned up a
**second, independent bug**: the `@Reducer` macro's own codegen for `@SuperScope` properties
(`Sources/StatoscopeMacros/ReducerMacro.swift`) never emitted a `subscribe:` closure at all,
regardless of the `observed:` argument's value — unlike the parallel `@SuperState` codegen, which
does. Both had to be fixed together:

1. **Macro codegen** (`ReducerMacro.swift`): the `parentStoreProperties` loop now emits the same
   conditional `subscribe:` closure shape as `superStateProperties`, resolving the *classic*
   parent type directly (`resolveAncestor(\(parentType).self, from: store)`) rather than a
   `Store<SomeReducer>`.
2. **Runtime wiring** (`Subscope.swift`): the setter now calls
   `(newValue as? any _SuperSlotWireable)?._wireSuperSlots()` after `_parentNode` is established,
   guarded by whether the child was already parented *before* this assignment — so reassigning
   the same already-wired child instance never adds a second, duplicate Combine subscription.
   `_SuperSlotWireable` (`Store.swift`) was bumped from `fileprivate` to `internal` so
   `Subscope.swift` (same module) can see it.

Verified with three new tests in `ParentStoreBindingTests.swift`
(`testSuperScopeObservedRelaysParentObjectWillChangeExactlyOnce`,
`testSuperScopeObservedDoesNotDoubleWireOnRedundantReassignment`,
`testSuperScopeObservedRelaysMultipleMutationsOneNotificationEach`) asserting an *exact*
notification count per mutation, specifically to catch a naive fix that wires correctly but fires
2+ times per single ancestor mutation (a distinct, easy-to-introduce performance bug that an
"at least once" check wouldn't catch). A symmetric regression guard
(`ReducerTests.testObservedSuperStateDoesNotDoubleWireWhenChildIsRecreated`) confirms the
already-working `@SuperState(observed: true)` path isn't affected and still wires exactly once
even when its child is destroyed and recreated.

### `takeSnapshot()` didn't block re-entrant events during rendering, unlike every automatic snapshot point — FIXED

Was: `StoreTestPlan.safeSnapshot(sut:name:)` (`StoreTestPlan.swift`) is what installs a middleware
on every scope in the tree that blocks forwarding of any event received while `takingSnapshot ==
true`, keeping SwiftUI side effects (like `.onAppear` firing during
`NSHostingView`/`UIHostingController` rendering) from reaching `update(_:)` and corrupting the
scope under test. Every *automatic* snapshot call (the initial "GIVEN" snapshot and the one taken
after each `WHEN` step) went through `safeSnapshot` and was correctly protected;
`takeSnapshot()` (`TestPlan+Snapshot.swift`) instead called `self.snapshot?(sut, name)` directly,
bypassing `safeSnapshot` entirely. Fixed by calling `self.safeSnapshot(sut: sut, name: name)`
instead — a straightforward oversight, not a structural blocker; `safeSnapshot` was already
reachable (same module).
`StatoscopeTestingSnapshot.testExplicitTakeSnapshot` now passes.

### `EffectsState._cancelOlderEffect()` corrupted `enquedEffects` whenever 2+ effects are pending — FIXED

Was: `EffectsState._cancelOlderEffect()` (`Sources/Statoscope/Effects/EffectsState.swift`)
reassigned `enquedEffects` from `currentRequestedEffects` instead of filtering `enquedEffects`
itself, so it spuriously repopulated `enquedEffects` with every other still-pending effect
whenever two or more effects were pending at once. This corrupted the invariant
`_unsafeSendImplementation`'s `assert(effectsState.enquedEffects.count == 0)` relies on — a real
crash risk whenever `WHEN_OlderEffectCompletes` was used with multiple pending effects. Every
existing usage in the suite happened to only ever have one pending effect at a time, which is why
this was never caught before. Fixed by filtering `enquedEffects` itself instead of
`currentRequestedEffects`; `EffectsStateDirectTests.testCancelOlderEffectDoesNotPolluteEnquedEffectsWithOtherPendingEffects`
now passes.

## Ambiguous — needs a human decision, not a test

(None remaining — the four dead-code candidates previously listed here — `Inject.swift`,
`InjectedWithDefault.swift`, the private `ChainContinuationScope`, and
`DummyScopeImplementation.swift` — were confirmed to have zero usages anywhere outside their own
definitions and were removed in a single commit, "Removed dead code: Inject, InjectedWithDefault,
ChainContinuationScope, DummyScopeImplementation", so they're recoverable from git history if a
real use case ever turns up.)

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
other view-rendering test harness — adding one directly to this package is a real infrastructure
decision (which library, whether to add a `StatoscopeTestingUI`-style test target, CI
implications for a UI-capable runner) rather than something to default into while writing missing
unit tests. Similarly, `StoreView.body`/`StoreView<S,V>` itself (`StoreView.swift`) and the `body`
of the `StoreViewProtocol`-conforming test fixtures already added are equally out of reach without
the same infrastructure — only their non-rendering init/binding logic is covered.

**Follow-up plan**: rather than adding a view-rendering test dependency to this package, this
gap can likely be closed from the separate iOS Examples project (a real, runnable app already
exercising these connectors through actual navigation) via **XCUITest**. An XCUITest suite there
would drive the app through real `NavigationStack` push/pop, `.sheet`/`.fullScreenCover`
presentation, and nested destinations — exercising `ReducerStoreView`, `AutoConnectedView`,
`ReducerObservedView`, `ReducerRegistryCapture`, `ReducerEnvironmentCapture`, and the
`ReducerStoreRegistry` multi-level-push scenario their own doc comments describe as "confirmed
device-tested" — without needing ViewInspector/snapshot-testing or any new dependency in
`Statoscope` itself. Not yet started; noted here as the planned next step for this gap.

## Group B: Reducer internals — done

Scope: `Sources/Statoscope/Reducer/ReducerDependencies.swift`, `SubState.swift`,
`SuperState.swift`, `ChildStoreSlots.swift`, `ReducerInjected.swift`.

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
implementation. The only line left uncovered across these five files is the trivial guard branch
in `ReducerDependencies.resolve()` (`guard let node = node else { throw
InjectionError.noInjectionTree }`) — excluded per this file's own header. No genuinely ambiguous
or dead code was found in this group.

## Group F: `StoreTestPlan.swift` `WITH()` API, `GrabEffects.swift`, `StoreTestPlan+Effects.swift` — done

The last remaining gap after Groups A–E: `StoreTestPlan.swift`'s entire `WITH(keyPath)`
non-optional overload (`WithStoreTestPlan.addStep`/`buildLinkedFork`) had zero coverage — every
existing `.WITH()` test used the *optional*-keyPath overload (`WithOptStoreTestPlan`). New tests
added directly to `StatoscopeTestingWithTests.swift`:

- `testWithNonOptionalKeyPathNavigatesToSuperscope` — `.WITH(nonOptionalKeyPath)` on a
  `@Superscope` reference (always non-optional), exercising `WithStoreTestPlan.addStep`.
- `testWithNonOptionalKeyPathSupportsLinkedFork` — `.WITH(nonOptionalKeyPath).FORK(...)`,
  exercising `WithStoreTestPlan.buildLinkedFork`.
- `testWithOptionalKeyPathFailsWhenChildIsNilAtStepTime` — the `WithOptStoreTestPlan.addStep`
  unwrap-failure `XCTFail`/`throw` branch, previously uncovered (every existing `.WITH()` test
  only ever ran once the optional child was already known non-nil).

`GrabEffects.swift`'s `getSingleEffect` "found effects of the matching type, but none equal the
expected value" branch — distinct from the already-covered "no effect of that type exists at
all" branch — is now covered by `StatoscopeTestingThenTests.testXCTAssertEffectsIncludeFailsIfWrongValue`.
`StoreTestPlan+Effects.swift`'s `WHEN_OlderEffectCompletes` "no pending effect to cancel"
`XCTFail` branch is now covered by
`StatoscopeTestingEffectsTests.testWhenOlderEffectCompletesFailsIfNoEffectPending`.

### `WithStoreTestPlan.POP()` was missing `public` (compile-time API gap, not a runtime bug) — FIXED

Was: `WithStoreTestPlan.POP()` (`StoreTestPlan.swift`, the non-optional-keyPath `.WITH()` variant)
had no access modifier (`internal`), while its sibling `WithOptStoreTestPlan.POP()` (the
optional-keyPath variant) is `public` — a compile-time accessibility gap that made
`.WITH(nonOptionalKeyPath)` chains unable to ever call `.POP()` to navigate back to the parent
plan from outside the module, unlike every optional-keyPath `.WITH()` chain. Likely why nobody
had written a test for the non-optional overload before: any natural
`.WITH(...).THEN(...).POP()...` chain modeled on the existing optional-keyPath tests simply
wouldn't have compiled for it. Fixed by adding `public`; the two tests above (previously working
around it by never calling `.POP()`) now call it like every other `.WITH()` chain does.

### Ambiguous — structurally very hard to trigger without a contrived cross-type effect fixture

`WHEN_EffectCompletes`/`WHEN_EffectFails` (`StoreTestPlan+Effects.swift`) each have a
`guard ... as? T.When else { throw InvalidPristineResult() }` after a successful
`_pristineCompletes`/`_pristineFails` call. Working through when this could actually fail: an
enqueued effect's `ResultType` is tied to the store's own `When` by construction once it's been
through `.map(When.someCase)` (the standard, and only observed, way effects are enqueued anywhere
in this codebase or its tests) — `_pristineCompletes`/`_pristineFails` then produce exactly that
`ResultType`, which trivially satisfies the outer `as? T.When`. Reaching the `else` branch seems
to require an effect enqueued without going through `.map(...)` at all (an effect whose
`ResultType` never became the store's `When` in the first place) — but `EffectsState.enqueue`'s
own signature ties its parameter to `AnyEffect<When>`, so a genuinely unmapped effect doesn't
appear constructible for a given store through public API at all. Not confident this is reachable
without deliberately bypassing the type system (e.g. via `Any`-erasure tricks), so not writing a
test that might just be exercising an artificial setup rather than real behavior.

## Group C: Testing DSL (StatoscopeTesting) — done

Coverage pass over `Fork.swift`, `Then.swift`, `TestPlan+Snapshot.swift`, `XCTAssert+Statoscope.swift`,
`StoreTestPlan+EffectsFork.swift`, `Given.swift`, and `ScopeTreeRetrieval.swift`. Most gaps were
missing scenarios in already-existing test files (extended in place: `StatoscopeTestingForkWithTests.swift`,
`StatoscopeTestingEffectsTests.swift`, `StatoscopeTestingThenTests.swift`, `StatiscopeTestingSnapshot.swift`,
`ScopeTreeRetrievalTests.swift`). One new bug was discovered (documented above, under "Discovered
bugs").

### `GIVEN<Store: ScopeImplementation>(_:)` free function — REMOVED

Was a top-level `GIVEN { ... }` entry point, distinct from the two extension-based `.GIVEN` static
methods (`ScopeImplementation.GIVEN` and `Store.GIVEN`) that every single test in the suite
actually used. Confirmed zero call sites anywhere (including tutorials/examples), trivially
identical behavior to `ScopeImplementation.GIVEN`. Removed from `Given.swift`; recoverable from
git history if a real use case ever turns up.

## Group A: Injection internals — done

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

## Group D: Effects and misc — done

Scope: `Sources/Statoscope/Effects/EffectsState.swift`, `EffectsHandlerImplementation.swift`,
`AnyEffect.swift`, `InjectedForEffect.swift`, `EffectfullImplementation.swift`,
`Sources/Statoscope/Logging/Scope+DebugDescription.swift`, `Sources/Statoscope/Statostore.swift`,
`Sources/Statoscope/StoreProtocol.swift`, `Sources/Statoscope/Helpers/Statoscope+ObjcRuntime.swift`,
and `Sources/Statoscope/Helpers/String+removeOptionalDescription.swift`.

`Scope+DebugDescription.swift` and `EffectfullImplementation.swift` turned out to already be
effectively fully covered once trivial guard/early-return lines are excluded (`EffectfullImplementation.swift`'s
one remaining gap — the `effectsState` property's setter re-running its own associated-object
initializer branch, for the edge case where a scope's `effectsState` is assigned before it's ever
read — is now covered directly, see `EffectsStateSetterBeforeGetterTests` below).

New/extended tests:

- `Tests/StatoscopeTests/EffectsHanlderImplementationTests.swift` — added a new
  `EffectsStateDirectTests` class that exercises `EffectsState.cancelEffect` (removing an effect
  that was enqueued in the *same* update cycle, before it's ever flushed to the handler) and
  `EffectsState._cancelOlderEffect()` directly (see "Discovered bugs" below).
- `Tests/StatoscopeTests/EffectsTests.swift` — extended `EffectPristineCompletesOrFailsTests` with
  `AnyEffect`'s type-mismatch safety net: the `guard let result = try $0() as? E.ResultType else {
  throw InvalidPristineResult() }` branches in both `init(effect:)` (used by `eraseToAnyEffect()`)
  and `init(_:mapper:)` (used by `.map`), plus the equivalent fall-through-without-throwing case in
  `init(_:errorMapper:)`'s non-nested branch, and the `catch` in that same init's nested
  ("already an `AnyEffect`") branch when chaining `.map` then `.mapToResultWithError`.
- `Tests/StatoscopeTests/EffectStructInjectedParamProtocolTests.swift` — added direct tests for
  `InjectedForEffect.debugDescription` and its (deliberately type-only) `Equatable` conformance.
- `Tests/StatoscopeTests/StoreProtocolTests.swift` (new file) — `Statostore.set(_:_:)`,
  `StoreProtocol.sendUnsafe(_:)` (both success and error-propagation), and the `effectsState`
  setter's lazy-init branch mentioned above.
- `Tests/StatoscopeTests/RemoveOptionalDescriptionTests.swift` (new file) — the "Optional<...>"
  (describing-a-*type*) branch of `removeOptionalDescription`, which no existing test exercised;
  only the "Optional(...)" (describing-a-*value*) branch was previously covered.

One new bug was discovered while writing these tests, since fixed (documented above, under
"Discovered bugs"): `EffectsState._cancelOlderEffect()` used to corrupt `enquedEffects` whenever
2+ effects were pending.

### Decisions made

#### `associateObject(base:key:value:)` — kept intentionally

Zero call sites anywhere in `Sources/` or `Tests/` today — only its sibling
`associateOptionalObject(base:key:value:)` is ever called. **Decision: keep.** It's a small
library on top of the Objective-C associated-object runtime that may get a non-optional use case
later; not worth deleting just because nothing currently calls it. Left uncovered/untested since
there's no real usage to test against yet.

#### `Effect._injectNode`'s superclass-mirror walk — proven real and working, not dead

```swift
var mirror = Mirror(reflecting: self)
while let current = mirror.superclassMirror {
    mirror = current
}
```
walks up a class hierarchy to reach the ultimate superclass's mirror before scanning its children
for `@InjectedForEffect`-wrapped properties. Every `Effect` conformer generated by `@EffectStruct`
is a struct (which has no `superclassMirror`), so this was never exercised by any existing test —
but a hand-written **class**-conforming `Effect` is entirely valid, supported API (`Effect` itself
has no struct-only constraint). `Tests/StatoscopeTests/EffectClassConformanceTests.swift` proves
it end to end with `ClassBasedStampEffect: Effect` (a plain class, `@InjectedForEffect`-wrapped
property): both the default-value path (nothing injected) and the tree-injected-override path
resolve correctly through a real `effectsState.enqueue(...)` → async completion cycle. The `while`
loop's own body (climbing an *actual* multi-level subclass chain) still isn't separately
exercised — the simple, non-subclassed case already proves the mechanism works; a genuine
subclass scenario would be the next incremental addition if ever needed.

#### `EffectsHandlerImplementation`'s "Can we ever get here?" branch — kept intentionally

```swift
case .success(let when):
    guard !Task.isCancelled else {
        assertionFailure("Can we ever get here ? I don't think so. Delete if never fails?")
        StatoscopeLogger.LOG(...)
        throw CancellationError()
    }
```
The comment is the original author's own doubt about whether this branch is reachable at all: by
the time `.success` is matched here, `buildEffectTask` has already checked `Task.isCancelled`
itself and mapped a cancelled task to `nil`/`.failure`, not `.success`. **Decision: keep.**
Constructing the race deterministically isn't practical for a unit test, but real-world SDK usage
"in the wild" surfaces timing/cancellation edge cases that never show up in a controlled test
environment — this stays as a defensive backstop (log + throw rather than silently proceeding)
rather than being deleted on the assumption it's unreachable.
