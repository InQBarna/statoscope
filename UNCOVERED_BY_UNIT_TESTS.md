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

### `EffectsState._cancelOlderEffect()` corrupts `enquedEffects` whenever 2+ effects are pending

- **Test**: `EffectsStateDirectTests.testCancelOlderEffectDoesNotPolluteEnquedEffectsWithOtherPendingEffects`
  (currently failing).
- **Root cause**: `EffectsState._cancelOlderEffect()` (`Sources/Statoscope/Effects/EffectsState.swift`)
  reassigns `enquedEffects` from `currentRequestedEffects` instead of filtering `enquedEffects`
  itself, so it spuriously repopulates `enquedEffects` with every other still-pending effect
  whenever two or more effects are pending at once. This corrupts the invariant
  `_unsafeSendImplementation`'s `assert(effectsState.enquedEffects.count == 0)` relies on — a real
  crash risk whenever `WHEN_OlderEffectCompletes` is used with multiple pending effects. Every
  existing usage in the suite happened to only ever have one pending effect at a time, which is
  why this was never caught before.
- **Fix shape** (not implemented): filter `enquedEffects` itself (removing the completed/cancelled
  entry), not `currentRequestedEffects`.

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

### `ChainContinuationScope` (private, in `Sources/Statoscope/ScopeImplementation.swift`) — appears dead

`private final class ChainContinuationScope<W>: ScopeImplementation` (a "virtual scope that
represents a continuation in the parent chain") is entirely unreferenced anywhere outside its own
~30-line definition — no call site constructs one. It accounts for effectively the entire
coverage gap in `ScopeImplementation.swift` (20 of its 20 missed lines). Unlike the three `public`
dead-code candidates above, this one is `private` and has zero external API surface, so removing
it carries no compatibility risk — but it's still a source-code change beyond "write the missing
test," so flagged here rather than deleted. Likely a leftover from an earlier design of the
`HierarchialScopeMiddleWare` continuation chain, superseded by the closure-based continuation
built directly in `callParentEnclosedHierarchialUpdate`.

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

## Not yet investigated

- `StatoscopeTesting/StoreTestPlan/StoreTestPlan.swift` (87.91%, 27 missed lines — notably the
  entire `WITH(keyPath)` child-scope-navigation API, `WithStoreTestPlan.addStep`/`buildLinkedFork`),
  `GrabEffects.swift` (small gap), `StoreTestPlan+Effects.swift` (small gap) — adjacent to the
  Testing-DSL group but not covered by it (see Group C below — it covered `Fork.swift`,
  `Then.swift`, `TestPlan+Snapshot.swift`, `XCTAssert+Statoscope.swift`,
  `StoreTestPlan+EffectsFork.swift`, `Given.swift`, `ScopeTreeRetrieval.swift`, but not these
  three). Still unassigned — the only remaining known gap as of this writing (all of Groups
  A–E below are done).

## Group C: Testing DSL (StatoscopeTesting) — done

Coverage pass over `Fork.swift`, `Then.swift`, `TestPlan+Snapshot.swift`, `XCTAssert+Statoscope.swift`,
`StoreTestPlan+EffectsFork.swift`, `Given.swift`, and `ScopeTreeRetrieval.swift`. Most gaps were
missing scenarios in already-existing test files (extended in place: `StatoscopeTestingForkWithTests.swift`,
`StatoscopeTestingEffectsTests.swift`, `StatoscopeTestingThenTests.swift`, `StatiscopeTestingSnapshot.swift`,
`ScopeTreeRetrievalTests.swift`). One item below was left undone as genuinely ambiguous/dead code,
and one new bug was discovered (documented above, under "Discovered bugs").

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

One new bug was discovered while writing these tests (documented above, under "Discovered bugs"):
`EffectsState._cancelOlderEffect()` corrupts `enquedEffects` whenever 2+ effects are pending.

### Ambiguous — needs a human decision, not a test

#### `associateObject(base:key:value:)` (`Sources/Statoscope/Helpers/Statoscope+ObjcRuntime.swift`) — appears dead

Zero call sites anywhere in `Sources/` or `Tests/` — only its sibling
`associateOptionalObject(base:key:value:)` is ever called. Same shape of question as the other
dead-code entries already in this file: it's `internal` (not public API, so no external
compatibility risk either way), and either (a) it's meant to back some future non-optional
associated-storage use case and should get a test treating it as supported, or (b) it's leftover
from before `associateOptionalObject` existed and should be deleted. Not testing it blindly since
which is true isn't answerable from reading the file alone.

#### `Effect._injectNode`'s superclass-mirror walk (`Sources/Statoscope/Effects/InjectedForEffect.swift`) — appears unreachable for how `Effect` is actually used

```swift
var mirror = Mirror(reflecting: self)
while let current = mirror.superclassMirror {
    mirror = current
}
```
walks up a class hierarchy to reach the ultimate superclass's mirror before scanning its children
for `@InjectedForEffect`-wrapped properties. Every `Effect` conformer in this codebase — and every
one the `@EffectStruct` macro generates — is a `struct`, which has no `superclassMirror`, so the
loop body never executes. This would only matter if `Effect` were ever adopted by a `class` with
its own superclass chain, which isn't a documented or exercised use case anywhere. Options: (a) a
class-based `Effect` fixture with a superclass should be written to exercise this as deliberate
forward-compatibility, or (b) it's speculative code that should be removed since `Effect`
conformers are conventionally structs. Not testing it blindly since which is true isn't answerable
from reading `Effect`/`AnyEffect`/`InjectedForEffect` alone.

#### `EffectsHandlerImplementation`'s "Can we ever get here?" branch (`Sources/Statoscope/Effects/EffectsHandlerImplementation.swift`)

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
itself and mapped a cancelled task to `nil`/`.failure`, not `.success`. Constructing a scenario
where the task is *reported* cancelled at this later checkpoint without having gone through that
earlier check would mean deliberately racing cooperative cancellation against the task's own
completion — not something a deterministic unit test can force. Left for a human to decide whether
to delete this branch (per the comment's own suggestion) rather than writing a test around a race
condition.
