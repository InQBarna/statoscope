//
//  MiddlewareReducerTests.swift
//  Statoscope
//
//  Tests for MiddlewareReducer protocol integration with @Reducer macro
//

import XCTest
@_spi(Internal) @testable import Statoscope

// MARK: - Test Reducers with MiddlewareReducer

@Reducer
struct ParentMiddlewareReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: ChildReducer.State?
        var delegatedTasks: [String] = []
        var interceptedEvents: Int = 0
    }

    enum When {
        case createChild
        case childDelegated(String)
    }

    // MiddlewareReducer implementation
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        parentState.interceptedEvents += 1

        guard let when = childWhen as? ChildReducer.When else { return .pass }

        switch when {
        case .taskCompleted(let task):
            return .react(.childDelegated(task))
        case .simpleAction:
            return .pass
        }
    }

    // Regular reducer update
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createChild:
            state.child = ChildReducer.State()

        case .childDelegated(let task):
            state.delegatedTasks.append(task)
        }
    }
}

@Reducer
struct ChildReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var executedEvents: [When] = []
    }

    enum When {
        case taskCompleted(String)
        case simpleAction
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        state.executedEvents.append(when)
    }
}

// Root middleware that intercepts everything in subtree
@Reducer
struct RootMiddlewareReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var parent: ParentMiddlewareReducer.State?
        var rootInterceptions: Int = 0
    }

    enum When {
        case createParent
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        parentState.rootInterceptions += 1
        return .pass
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createParent:
            state.parent = ParentMiddlewareReducer.State()
        }
    }
}

/// Parent with two children. When primaryChild sends taskCompleted, updateSubstate
/// creates secondaryChild. This exercises the write-back in updateSubscope:
/// since _secondaryChild is nil when the event arrives, a new child store must
/// be created from the assigned state value.
@Reducer
struct TwoChildParentReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var primaryChild: ChildReducer.State?
        @SubState var secondaryChild: ChildReducer.State?
    }

    enum When {
        case setup
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        guard let when = childWhen as? ChildReducer.When,
              case .taskCompleted = when else { return .pass }
        // Create secondaryChild when primaryChild sends taskCompleted
        // At this point _$secondaryChild is nil, so this creates a pending binding
        parentState.secondaryChild = ChildReducer.State()
        return .pass
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .setup:
            state.primaryChild = ChildReducer.State()
        }
    }
}

// MARK: - Test Cases

final class MiddlewareReducerTests: XCTestCase {

    // MARK: - Basic Middleware Tests

    func testMiddlewareReducerInterceptsChildEvents() throws {
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())

        // Create child. parent is ROOT (no ancestors) → _unsafeSendImplementation, no updateSubscope called.
        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        XCTAssertEqual(parent.state.interceptedEvents, 0, "No updateSubstate for parent's own events: parent is root, updateSubscope never called")

        // Get child store
        guard let child = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Child sends event
        child.send(.taskCompleted("task1"))

        // Parent intercepts child's .taskCompleted → interceptedEvents = 1
        // parent.send(.childDelegated): parent is ROOT → _unsafeSendImplementation directly, no self-interception
        XCTAssertEqual(parent.state.interceptedEvents, 1, "Parent intercepts child's event only")
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"], "Parent should receive delegation")

        // Child should have executed
        XCTAssertEqual(child.state.executedEvents.count, 1)
    }

    func testMiddlewareReducerSelectiveDelegation() throws {
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Send taskCompleted - should delegate
        child.send(.taskCompleted("task1"))
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"])

        // Send simpleAction - should NOT delegate
        child.send(.simpleAction)
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"], "No new delegation for simpleAction")

        // Parent intercepts: taskCompleted + simpleAction = 2
        // Self-interception of .childDelegated occurs but cast to ChildReducer.Store fails → no extra count
        XCTAssertEqual(parent.state.interceptedEvents, 2, "Parent intercepts child events only, not its own sends")

        // Child should have executed both events
        XCTAssertEqual(child.state.executedEvents.count, 2)
    }

    // MARK: - Multi-Level Middleware Tests

    func testMultiLevelMiddlewareChain() throws {
        let root = RootMiddlewareReducer.Store(initialState: RootMiddlewareReducer.State())

        // Create parent
        root.send(.createParent)

        guard let parent = root.children.parent else {
            XCTFail("Parent store not found")
            return
        }

        // Create child
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Child sends event
        child.send(.taskCompleted("task1"))

        // Root intercepts ALL descendant events: parent.createChild + child.taskCompleted + parent.childDelegated = 3
        //   createParent: root has no ancestors (it IS the root) → no updateSubscope
        //   createChild: root sees parent's event → rootInterceptions = 1
        //   taskCompleted: root sees child's event directly (ReducerDispatchable) → rootInterceptions = 2
        //   childDelegated: root sees parent's event (delegated by parent) → rootInterceptions = 3
        //   self-interception (delegateWhen chain): excluded via ObjectIdentifier check
        XCTAssertEqual(root.state.rootInterceptions, 3, "Root intercepts events from all descendants")

        // Parent intercepts: taskCompleted from child = 1
        //   createChild: parent is child's ancestor but NOT a MiddlewareReducer itself in this context
        //   childDelegated self-interception: excluded via ObjectIdentifier(self) != ObjectIdentifier(parent) check
        XCTAssertEqual(parent.state.interceptedEvents, 1, "Parent intercepts only child's events")
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"])

        // Child should have executed
        XCTAssertEqual(child.state.executedEvents.count, 1)
    }

    func testMultiLevelMultipleEvents() throws {
        let root = RootMiddlewareReducer.Store(initialState: RootMiddlewareReducer.State())
        root.send(.createParent)

        guard let parent = root.children.parent else {
            XCTFail("Parent store not found")
            return
        }

        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not found")
            return
        }

        // Send 3 events
        child.send(.taskCompleted("task1"))
        child.send(.simpleAction)
        child.send(.taskCompleted("task2"))

        // Root intercepts ALL descendant events:
        //   parent.createChild (1)
        //   child.taskCompleted1 (2)  — new: ReducerDispatchable propagates grandchild events
        //   parent.childDelegated1 (3)
        //   child.simpleAction (4)    — new: ReducerDispatchable propagates grandchild events
        //   child.taskCompleted2 (5)  — new: ReducerDispatchable propagates grandchild events
        //   parent.childDelegated2 (6)
        //   self-interceptions excluded via ObjectIdentifier check
        XCTAssertEqual(root.state.rootInterceptions, 6, "Root intercepts events from all descendants")

        // Parent intercepts child events: task1 + simpleAction + task2 = 3
        //   self-interceptions (.childDelegated): excluded via ObjectIdentifier check → no extra count
        XCTAssertEqual(parent.state.interceptedEvents, 3)
        XCTAssertEqual(parent.state.delegatedTasks, ["task1", "task2"])

        // Child executes all 3
        XCTAssertEqual(child.state.executedEvents.count, 3)
    }

    // MARK: - Conformance Tests

    func testStoreConformsToHierarchialScopeMiddleWare() throws {
        // Verify that Store generated from MiddlewareReducer conforms to protocol
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())

        XCTAssertTrue(parent is HierarchialScopeMiddleWare, "Store should conform to HierarchialScopeMiddleWare")
    }

    func testNonMiddlewareReducerDoesNotConform() throws {
        // ChildReducer does NOT conform to MiddlewareReducer
        let child = ChildReducer.Store(initialState: ChildReducer.State())

        XCTAssertFalse(child is HierarchialScopeMiddleWare, "Store without MiddlewareReducer should not conform")
    }

    // MARK: - Child store write-back in updateSubscope

    func testUpdateSubscopeCreatesChildStoreViaUpdateSubstate() throws {
        // TwoChildParentReducer creates secondaryChild inside updateSubstate when
        // primaryChild sends taskCompleted. The write-back code in updateSubscope
        // detects that _secondaryChild is nil and creates a new child Store.
        let parent = TwoChildParentReducer.Store(initialState: TwoChildParentReducer.State())
        parent.send(.setup)

        guard let primary = parent.children.primaryChild else {
            XCTFail("primaryChild store not created")
            return
        }

        XCTAssertNil(parent.children.secondaryChild, "secondaryChild should not exist yet")

        // primaryChild.send(.taskCompleted) → updateSubstate → parentState.secondaryChild = ChildReducer.State()
        // updateSubscope write-back detects nil _secondaryChild and creates the Store
        primary.send(.taskCompleted("trigger"))

        XCTAssertNotNil(
            parent.children.secondaryChild,
            "Write-back must create the secondaryChild Store from assigned state"
        )
        XCTAssertNotNil(
            parent.state.secondaryChild,
            "state.secondaryChild must be accessible after creation via updateSubstate"
        )
    }

    func testReassigningChildStateAlwaysCreatesNewStore() throws {
        // Any dirty assignment to a @SubState property always produces a fresh child store.
        // The parent cannot mutate a live child store's state directly — encapsulation is preserved.
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())
        parent.send(.createChild)

        guard let storeAfterCreate = parent.children.child else {
            XCTFail("Child store must exist after createChild")
            return
        }

        // Second createChild: even though _child already exists, reassignment creates a new store
        parent.send(.createChild)

        guard let storeAfterSecond = parent.children.child else {
            XCTFail("Child store must still exist after second createChild")
            return
        }

        XCTAssertFalse(
            storeAfterCreate === storeAfterSecond,
            "Reassigning child state always replaces the Store — parent cannot mutate child state directly"
        )
    }

    func testDestroyAndRecreateChildCreatesNewStore() throws {
        // Explicitly destroying (nil) then reassigning also produces a fresh Store.
        let parent = AutoInitParentReducer.Store(initialState: AutoInitParentReducer.State())
        parent.send(.createChild)

        guard let storeAfterCreate = parent.children.child else {
            XCTFail("Child store must exist after createChild")
            return
        }

        parent.send(.destroyChild)
        XCTAssertNil(parent.children.child, "Child store must be nil after destroyChild")

        parent.send(.createChild)

        guard let storeAfterRecreate = parent.children.child else {
            XCTFail("Child store must exist after recreate")
            return
        }

        XCTAssertFalse(
            storeAfterCreate === storeAfterRecreate,
            "Destroy + create produces a fresh Store"
        )
    }
}

// MARK: - Deep Hierarchy Test Reducers (Root → Child → Grandchild)



/// Leaf reducer — no children, just increments a counter
@Reducer
struct GrandchildCounterReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var value: Int = 0
    }

    enum When {
        case setValue(Int)
        case reset
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .setValue(let v): state.value = v
        case .reset: state.value = 0
        }
    }
}

/// Intermediate reducer — MiddlewareReducer but returns nil for all grandchild events.
/// No artificial forwarding event needed; root handles grandchild events directly.
@Reducer
struct ChildContainerReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var grandchild: GrandchildCounterReducer.State?
        var childInterceptions: Int = 0
    }

    enum When {
        case createGrandchild
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        parentState.childInterceptions += 1
        // Deliberately passes through — root will handle grandchild events directly
        return .pass
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createGrandchild:
            state.grandchild = GrandchildCounterReducer.State()
        }
    }
}

/// Root reducer — intercepts grandchild events directly without any forwarding from ChildContainerReducer
@Reducer
struct RootDeepReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: ChildContainerReducer.State?
        var grandchildValue: Int = -1
        var rootInterceptions: Int = 0
    }

    enum When {
        case createChild
        case grandchildUpdated(Int)
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        parentState.rootInterceptions += 1
        // React directly to GrandchildCounterReducer events — no forwarding needed in ChildContainerReducer
        if let when = childWhen as? GrandchildCounterReducer.When {
            switch when {
            case .setValue(let v):
                return .react(.grandchildUpdated(v))
            case .reset:
                return .react(.grandchildUpdated(0))
            }
        }
        return .pass
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createChild:
            state.child = ChildContainerReducer.State()
        case .grandchildUpdated(let v):
            state.grandchildValue = v
        }
    }
}

// MARK: - Deep Hierarchy Tests

final class DeepHierarchyReducerTests: XCTestCase {

    func testRootInterceptsGrandchildEventDirectlyWithoutForwarding() throws {
        let root = RootDeepReducer.Store(initialState: RootDeepReducer.State())
        root.send(.createChild)

        guard let child = root.children.child else {
            XCTFail("child store not created")
            return
        }

        child.send(.createGrandchild)

        guard let grandchild = child.children.grandchild else {
            XCTFail("grandchild store not created")
            return
        }

        XCTAssertEqual(root.state.grandchildValue, -1, "No update yet")

        // Grandchild sends setValue(42). Root's updateSubstate handles it directly,
        // returning .grandchildUpdated(42) — no forwarding event needed in ChildContainerReducer.
        grandchild.send(.setValue(42))

        XCTAssertEqual(
            root.state.grandchildValue, 42,
            "Root must intercept grandchild event directly via ReducerDispatchable"
        )
        XCTAssertEqual(grandchild.state.value, 42, "Grandchild must still process its own event")
    }

    func testParentStillInterceptsGrandchildEvents() throws {
        let root = RootDeepReducer.Store(initialState: RootDeepReducer.State())
        root.send(.createChild)
        guard let child = root.children.child else { XCTFail("child not created"); return }
        child.send(.createGrandchild)
        guard let grandchild = child.children.grandchild else { XCTFail("grandchild not created"); return }

        grandchild.send(.setValue(10))
        grandchild.send(.reset)

        // ChildContainerReducer.updateSubstate is called for grandchild events too (unchanged)
        XCTAssertEqual(child.state.childInterceptions, 2, "Intermediate parent still intercepts grandchild events")
    }

    func testRootInterceptionCountForDeepHierarchy() throws {
        let root = RootDeepReducer.Store(initialState: RootDeepReducer.State())

        // root.send(.createChild): root is ROOT, no ancestors → no updateSubscope
        root.send(.createChild)
        XCTAssertEqual(root.state.rootInterceptions, 0)

        guard let child = root.children.child else { XCTFail("child not created"); return }

        // child.send(.createGrandchild): root intercepts child's event → rootInterceptions = 1
        child.send(.createGrandchild)
        XCTAssertEqual(root.state.rootInterceptions, 1, "Root intercepts child's createGrandchild event")

        guard let grandchild = child.children.grandchild else { XCTFail("grandchild not created"); return }

        // grandchild.send(.setValue): root intercepts grandchild's event directly → rootInterceptions = 2
        // root.send(.grandchildUpdated): root is ROOT → no updateSubscope → rootInterceptions stays 2
        grandchild.send(.setValue(5))
        XCTAssertEqual(root.state.rootInterceptions, 2, "Root intercepts grandchild event directly")
        XCTAssertEqual(root.state.grandchildValue, 5)

        // grandchild.send(.reset): root intercepts → rootInterceptions = 3, grandchildValue = 0
        grandchild.send(.reset)
        XCTAssertEqual(root.state.rootInterceptions, 3)
        XCTAssertEqual(root.state.grandchildValue, 0)
    }

    func testGrandchildStoreConformsToReducerDispatchable() throws {
        let grandchild = GrandchildCounterReducer.Store(initialState: GrandchildCounterReducer.State())
        XCTAssertTrue(grandchild is any ReducerDispatchable, "All @Reducer-generated Stores must conform to ReducerDispatchable")
    }
}

// MARK: - defaultTrigger Test Reducers

@Reducer
struct AutoInitChildReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var initializeCount: Int = 0
        var lastEvent: String = ""
    }

    enum When {
        case onAppear
        case doSomething
    }

    // Declare default trigger: sent automatically when child store is wired
    static var defaultTrigger: When? { .onAppear }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .onAppear:
            state.initializeCount += 1
            state.lastEvent = "onAppear"
        case .doSomething:
            state.lastEvent = "doSomething"
        }
    }
}

@Reducer
struct AutoInitParentReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: AutoInitChildReducer.State?
    }

    enum When {
        case createChild
        case destroyChild
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createChild:
            state.child = AutoInitChildReducer.State()
        case .destroyChild:
            state.child = nil
        }
    }
}

// MARK: - defaultTrigger Tests

final class DefaultTriggerReducerTests: XCTestCase {

    func testDefaultTriggerIsSentWhenChildIsWired() throws {
        let parent = AutoInitParentReducer.Store(initialState: AutoInitParentReducer.State())

        XCTAssertNil(parent.children.child, "No child before createChild")

        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not created")
            return
        }

        // defaultTrigger .onAppear should have been dispatched automatically
        XCTAssertEqual(child.state.initializeCount, 1, "defaultTrigger should fire once on wiring")
        XCTAssertEqual(child.state.lastEvent, "onAppear")
    }

    func testDefaultTriggerFiresOnlyOnce() throws {
        let parent = AutoInitParentReducer.Store(initialState: AutoInitParentReducer.State())
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not created")
            return
        }

        // Send additional events — initializeCount must not increase
        child.send(.doSomething)
        XCTAssertEqual(child.state.initializeCount, 1, "defaultTrigger fires only on wiring, not on subsequent events")
    }

    func testDefaultTriggerFiresAgainWhenChildIsRecreated() throws {
        let parent = AutoInitParentReducer.Store(initialState: AutoInitParentReducer.State())
        parent.send(.createChild)
        parent.send(.destroyChild)
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not recreated")
            return
        }

        // A new store is created — defaultTrigger fires again
        XCTAssertEqual(child.state.initializeCount, 1, "New child store gets its own defaultTrigger")
    }

    func testNoDefaultTriggerForReducerWithoutIt() throws {
        // ChildReducer (used in other tests) has no defaultTrigger
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())
        parent.send(.createChild)

        guard let child = parent.children.child else {
            XCTFail("Child store not created")
            return
        }

        // No default trigger — child should have no executed events
        XCTAssertEqual(child.state.executedEvents.count, 0, "No defaultTrigger means no automatic event")
    }
}
