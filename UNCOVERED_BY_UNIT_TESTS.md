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

## Group D: Effects and misc

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

### Discovered bugs (new failing test — do not fix without a deliberate TDD pass)

#### `EffectsState._cancelOlderEffect()` corrupts `enquedEffects` with unrelated pending effects

- **Test**: `EffectsStateDirectTests.testCancelOlderEffectDoesNotPolluteEnquedEffectsWithOtherPendingEffects`
  (`Tests/StatoscopeTests/EffectsHanlderImplementationTests.swift`) — currently failing.
- **Root cause**: `EffectsState._cancelOlderEffect()` (`Sources/Statoscope/Effects/EffectsState.swift`)
  does:
  ```swift
  currentRequestedEffects = currentRequestedEffects.filter { uuid, _ in uuid != olderUUID }
  enquedEffects = currentRequestedEffects.filter { uuid, _ in uuid != olderUUID }
  ```
  The second line reassigns `enquedEffects` from `currentRequestedEffects` — which, by that point,
  is already filtered down to "every other still-pending effect" — instead of filtering
  `enquedEffects` itself. Since none of those survivors equal `olderUUID`, the second `filter` is a
  no-op, so `enquedEffects` ends up containing every other in-flight effect rather than staying
  empty (which is what it should be: `_cancelOlderEffect` is called between update cycles, after
  `_unsafeSendImplementation` has already reset `enquedEffects` to `[]`, and nothing new has been
  freshly enqueued).
- **Why it matters**: `StatoscopeTesting`'s `WHEN_OlderEffectCompletes` (`StoreTestPlan+Effects.swift`)
  calls this method directly on a live scope's `effectsState`. Whenever 2+ effects are pending at
  once and a test simulates the oldest one completing, `enquedEffects` is left non-empty
  afterwards. The very next `send`/`sendUnsafe` call on that scope starts with
  `assert(effectsState.enquedEffects.count == 0)` (`Sources/Statoscope/ScopeImplementation.swift`,
  `_unsafeSendImplementation`) — so this isn't just a stale/unused field, it's a live
  assertion-crash risk in exactly the "multiple concurrent pending effects +
  `WHEN_OlderEffectCompletes`" scenario the API exists for. Every existing test using
  `WHEN_OlderEffectCompletes` happens to only ever have a single effect pending at the time it's
  called, which is why this was never caught before.
- **Fix shape** (not implemented): the second line should read
  `enquedEffects = enquedEffects.filter { uuid, _ in uuid != olderUUID }`.

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
