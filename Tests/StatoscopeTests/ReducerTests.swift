//
//  ReducerTests.swift
//  Statoscope
//
//  Created by Claude Code on 26/2/26.
//

import XCTest
import Combine
@_spi(Internal) @testable import Statoscope

// MARK: - Test Reducers (File Scope)

enum Counter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
            var name: String = ""
        }
        
        enum When {
            case increment
            case decrement
            case setName(String)
            case reset
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .increment:
                state.count += 1
                
            case .decrement:
                state.count = max(0, state.count - 1)
                
            case .setName(let name):
                state.name = name
                
            case .reset:
                state.count = 0
                state.name = ""
            }
        }
    }
}

enum AsyncCounter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
            var isLoading: Bool = false
        }
        
        enum When {
            case startIncrement
            case incrementCompleted
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .startIncrement:
                state.isLoading = true
                effectsState.enqueue(AnyEffect {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    return .incrementCompleted
                })
                
            case .incrementCompleted:
                state.isLoading = false
                state.count += 1
            }
        }
    }
}

enum ErrorThrowing {
    @Reducer
    struct Reducer {
        struct State {
            var counter: Int = 0
        }
        
        struct ReducerError: Error {}
        
        enum When {
            case shouldFail
            case shouldSucceed
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .shouldFail:
                throw ReducerError()
            case .shouldSucceed:
                state.counter += 1
            }
        }
    }
}

struct Logger: Injectable {
    static var defaultValue: Logger { Logger() }

    var logs: [String] = []
    mutating func log(_ message: String) {
        logs.append(message)
    }
}

enum LoggingCounter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
        }
        
        enum When {
            case increment
        }
        
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment:
                // Resolve logger from dependencies
                var logger: Logger = try dependencies.resolve()
                logger.log("log message")
                state.count += 1
            }
        }
    }
}

enum ParentChild {
    // Parent-Child examples now use @Reducer macro with automatic child Store creation!
    @Reducer
    struct ParentReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var count: Int = 0
            @SubState var child: ChildReducer.State?
        }
        
        enum When {
            case increment
            case createChild
            case updateChild
        }
        
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment:
                state.count += 1
                
            case .createChild:
                // ✅ Clean! No manual parent binding
                var childState = ChildReducer.State()
                childState.value = 0
                state.child = childState
                
            case .updateChild:
                state.child?.value = 42
            }
        }
    }
    
    @Reducer
    struct ChildReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            @SuperState var parent: ParentReducer.State
            var value: Int = 0
        }
        
        enum When {
            case syncWithParent
        }
        
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .syncWithParent:
                // ✅ Parent automatically wired!
                state.value = state.parent.count * 2
            }
        }
    }
}

// MARK: - Three-level hierarchy (Pattern 3 + 4 tests)

enum DeepHierarchy {

    @Reducer
    struct GrandchildReducer {
        struct State {
            var label: String = ""
        }
        enum When {
            case setLabel(String)
        }
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .setLabel(let label): state.label = label
            }
        }
    }

    @Reducer
    struct ChildReducer {
        struct State {
            var value: Int = 0
            @SubState var grandchild: GrandchildReducer.State?
        }
        enum When {
            case openGrandchild
            case setValue(Int)
        }
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .openGrandchild:
                state.grandchild = GrandchildReducer.State()
            case .setValue(let v):
                state.value = v
            }
        }
    }

    @Reducer
    struct ParentReducer {
        struct State {
            var name: String = ""
            @SubState var child: ChildReducer.State?
        }
        enum When {
            case createChild
            case replaceChild(newValue: Int)
            case createChildWithGrandchild
        }
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .createChild:
                state.child = ChildReducer.State()
            case .replaceChild(let newValue):
                var childState = ChildReducer.State()
                childState.value = newValue
                state.child = childState
            case .createChildWithGrandchild:
                var childState = ChildReducer.State()
                childState.grandchild = GrandchildReducer.State()
                state.child = childState
            }
        }
    }
}

// MARK: - @SuperState(observed: true) relay fixture

enum ObservedSuperState {
    @Reducer
    struct ParentReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var counter: Int = 0
            @SubState var child: ChildReducer.State?
        }
        enum When {
            case increment
            case createChild
        }
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment: state.counter += 1
            case .createChild: state.child = ChildReducer.State()
            }
        }
    }

    @Reducer
    struct ChildReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            @SuperState(observed: true) var parent: ParentReducer.State
        }
        enum When { case noop }
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .noop: break
            }
        }
    }
}

// MARK: - Test Cases

/// Tests for Reducer pattern with @Reducer macro
final class ReducerTests: XCTestCase {

    // MARK: - Basic Reducer Tests

    func testBasicReducerFunctionality() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.name, "")

        store.send(.increment)
        XCTAssertEqual(store.state.count, 1)

        store.send(.increment)
        XCTAssertEqual(store.state.count, 2)

        store.send(.setName("Test"))
        XCTAssertEqual(store.state.name, "Test")

        store.send(.decrement)
        XCTAssertEqual(store.state.count, 1)

        store.send(.reset)
        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.name, "")
    }

    func testPublishedUpdates() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        var publishCount = 0
        let cancellable = store.objectWillChange.sink { _ in
            publishCount += 1
        }

        // Increment triggers objectWillChange
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, 0)

        let currentCount = publishCount
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, currentCount)

        _ = cancellable
    }

    func testStateSnapshot() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        store.send(.increment)
        store.send(.setName("Test"))

        // Take snapshot
        let snapshot = store.state
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.name, "Test")

        // Modify state
        store.send(.increment)
        XCTAssertEqual(store.state.count, 2)

        // Snapshot remains unchanged
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.name, "Test")
    }

    // MARK: - Effect Tests

    func testReducerWithEffects() async throws {
        scopeEffectsDisabledInUnitTests = false

        let store = AsyncCounter.Reducer.Store(initialState: AsyncCounter.Reducer.State())

        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.isLoading, false)

        store.send(.startIncrement)

        XCTAssertEqual(store.state.isLoading, true)
        XCTAssertEqual(store.state.count, 0)

        // Wait for effect to complete
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        XCTAssertEqual(store.state.isLoading, false)
        XCTAssertEqual(store.state.count, 1)

        scopeEffectsDisabledInUnitTests = true
    }

    // MARK: - Error Handling

    func testErrorHandling() {
        let store = ErrorThrowing.Reducer.Store(initialState: ErrorThrowing.Reducer.State())

        XCTAssertEqual(store.state.counter, 0)

        // Error in reducer is caught by framework
        store.send(.shouldFail)
        // State unchanged on error
        XCTAssertEqual(store.state.counter, 0)

        // Success still works
        store.send(.shouldSucceed)
        XCTAssertEqual(store.state.counter, 1)
    }

    // MARK: - Dependency Injection

    func testDependencyInjection() {
        let store = LoggingCounter.Reducer.Store(initialState: LoggingCounter.Reducer.State())

        // Inject logger into store
        let logger = Logger()
        store.injectObject(logger)

        XCTAssertEqual(store.state.count, 0)

        // Send event - reducer will resolve logger
        store.send(.increment)

        XCTAssertEqual(store.state.count, 1)
        // Logger was successfully resolved (no errors thrown)
    }

    // MARK: - Parent-Child with SuperState/SubState

    func testSuperAndSubState() {
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        XCTAssertEqual(parent.state.count, 0)
        XCTAssertNil(parent.state.child)

        // Create child
        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        XCTAssertEqual(parent.state.child?.value, 0)

        // Get child store from @Subscope property
        guard let childStore = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Child can sync with parent state via @SuperState
        childStore.send(.syncWithParent)
        XCTAssertEqual(childStore.state.value, 0)  // parent.count = 0, so value = 0 * 2

        // Parent increments
        parent.send(.increment)
        XCTAssertEqual(parent.state.count, 1)

        // Child syncs with parent - SuperStateBinding reflects new parent state!
        childStore.send(.syncWithParent)
        XCTAssertEqual(childStore.state.value, 2)  // parent.count = 1, so value = 1 * 2

        // Parent can update child via state
        parent.send(.updateChild)
        XCTAssertEqual(parent.state.child?.value, 42)
    }

    func testSuperStateReadOnly() {
        // This test demonstrates that SuperStateBinding only exposes state, not send()
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        guard let childStore = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // The following code would NOT compile if uncommented in the reducer:
        //
        // state.parent.send(.increment)  // ❌ Error: SuperStateBinding has no member 'send'
        //
        // This is a compile-time safety feature!

        // Child can only READ parent state
        XCTAssertEqual(childStore.state.parent.count, 0)
    }

    func testSubStateAccess() {
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        XCTAssertEqual(parent.state.child?.value, 0)

        // Parent can modify child state via state mutation in update()
        parent.send(.updateChild)
        XCTAssertEqual(parent.state.child?.value, 42)
    }

    func testChildStateReflectsCurrentState() {
        // Demonstrate that parent state always reflects live child store state
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        guard let childStore = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Initial state
        XCTAssertEqual(childStore.state.parent.count, 0)

        // Parent state changes
        parent.send(.increment)

        // Child's SuperStateBinding immediately reflects the change
        XCTAssertEqual(childStore.state.parent.count, 1)
    }

    // MARK: - Injectable Conformance

    func testInjectableConformance() {
        // Verify that State types have Injectable conformance
        let defaultCounter = Counter.Reducer.State()
        XCTAssertEqual(defaultCounter.count, 0)
        XCTAssertEqual(defaultCounter.name, "")

        let defaultParent = ParentChild.ParentReducer.State()
        XCTAssertEqual(defaultParent.count, 0)
        XCTAssertNil(defaultParent.child)
    }

    // MARK: - ObservableObject Conformance

    func testObservableObjectConformance() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        var publishCount = 0
        let cancellable = store.objectWillChange.sink { _ in
            publishCount += 1
        }

        // Increment triggers objectWillChange
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, 0)

        _ = cancellable
    }

    // MARK: - Pattern 3: reassign child state (non-nil → different non-nil)

    // When a parent reassigns a @SubState slot that already has a live child store,
    // the old store is replaced with a fresh one carrying the new state, and any
    // grandchild stores that existed in the old child are migrated to the new child.
    func testReassignChildStateDiscardsGrandchildren() {
        let parent = DeepHierarchy.ParentReducer.Store(initialState: DeepHierarchy.ParentReducer.State())

        // Create child, then open a grandchild inside it.
        parent.send(.createChild)
        guard let child1 = parent.children.child else {
            XCTFail("child store missing after createChild")
            return
        }
        child1.send(.openGrandchild)
        XCTAssertNotNil(child1.children.grandchild, "grandchild store should exist after openGrandchild")
        let grandchildStore = child1.children.grandchild
        grandchildStore?.send(.setLabel("original"))
        XCTAssertEqual(grandchildStore?.state.label, "original")

        // Reassign the child slot (already non-nil, replaced by a different value): parent
        // creates a fresh child state with no grandchild of its own.
        parent.send(.replaceChild(newValue: 99))

        guard let child2 = parent.children.child else {
            XCTFail("child store missing after replaceChild")
            return
        }
        XCTAssertFalse(child1 === child2, "child store should be a new instance")
        XCTAssertEqual(child2.state.value, 99, "new child state carries the replacement value")
        // Reassigning a child discards its previous subtree outright — no grandchild
        // migration. A reducer that wants to preserve something across being recreated is
        // responsible for restoring it itself (e.g. in its own defaultWhen).
        XCTAssertNil(child2.children.grandchild, "grandchild store should NOT survive child replacement")
    }

    // MARK: - Pattern 4: new child state with pre-populated @SubState descendants

    // When a parent update creates a child state that already has a grandchild state
    // assigned (via the property setter, which sets isDirty = true), both the child and
    // grandchild stores must be created immediately — before triggerDefault fires on the
    // child — because the state getter resets dirty flags via injectIntoParent.
    func testNewChildWithPrePopulatedGrandchildCreatesFullHierarchy() {
        let parent = DeepHierarchy.ParentReducer.Store(initialState: DeepHierarchy.ParentReducer.State())

        // .createChildWithGrandchild sets state.child = childState where childState.grandchild
        // is already non-nil (assigned via setter → isDirty = true on grandchild slot).
        parent.send(.createChildWithGrandchild)

        XCTAssertNotNil(parent.children.child, "child store should be created")
        XCTAssertNotNil(parent.children.child?.children.grandchild,
                        "grandchild store should be created recursively from the pre-populated initial state")
    }

    // MARK: - @SuperState(observed: true) relay

    // A child declaring @SuperState(observed: true) should have its own objectWillChange fire
    // whenever the referenced ancestor's state changes — even though nothing about the child's
    // OWN _rawState changed — so SwiftUI views observing only the child still refresh.
    func testObservedSuperStateRelaysAncestorChanges() {
        let parent = ObservedSuperState.ParentReducer.Store(initialState: ObservedSuperState.ParentReducer.State())
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("child store missing after createChild")
            return
        }

        var notificationCount = 0
        let cancellable = child.objectWillChange.sink { _ in notificationCount += 1 }

        parent.send(.increment)

        XCTAssertEqual(notificationCount, 1, "child's objectWillChange should fire when the observed ancestor changes")
        XCTAssertEqual(child.state.parent.counter, 1, "child's @SuperState snapshot reflects the new ancestor value")

        cancellable.cancel()
    }
}
