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
        parentState: inout State
    ) throws -> When? {
        parentState.interceptedEvents += 1

        guard let when = childWhen as? ChildReducer.When else { return nil }

        switch when {
        case .taskCompleted(let task):
            return .childDelegated(task)
        case .simpleAction:
            return nil
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
        parentState: inout State
    ) throws -> When? {
        parentState.rootInterceptions += 1
        return nil
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

// MARK: - Test Cases

final class MiddlewareReducerTests: XCTestCase {

    // MARK: - Basic Middleware Tests

    func testMiddlewareReducerInterceptsChildEvents() throws {
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())

        // Create child
        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        // Self-interception: updateSubscope is called but cast to ChildReducer.Store fails → no count
        XCTAssertEqual(parent.state.interceptedEvents, 0, "No self-interception: type cast fails for parent's own events")

        // Get child store
        guard let child = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Child sends event
        child.send(.taskCompleted("task1"))

        // Parent intercepts child's .taskCompleted → interceptedEvents = 1
        // parent.send(.childDelegated) is self-interception → cast fails → no extra count
        XCTAssertEqual(parent.state.interceptedEvents, 1, "Parent intercepts child's event only")
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"], "Parent should receive delegation")

        // Child should have executed
        XCTAssertEqual(child.state.executedEvents.count, 1)
    }

    func testMiddlewareReducerSelectiveDelegation() throws {
        let parent = ParentMiddlewareReducer.Store(initialState: ParentMiddlewareReducer.State())
        parent.send(.createChild)

        guard let child = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Send taskCompleted - should delegate
        child.send(.taskCompleted("task1"))
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"])

        // Send simpleAction - should NOT delegate
        child.send(.simpleAction)
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"], "No new delegation for simpleAction")

        // Parent intercepts: taskCompleted + simpleAction = 2 (self-events don't count: type cast fails)
        XCTAssertEqual(parent.state.interceptedEvents, 2, "Parent intercepts child events only, not its own sends")

        // Child should have executed both events
        XCTAssertEqual(child.state.executedEvents.count, 2)
    }

    // MARK: - Multi-Level Middleware Tests

    func testMultiLevelMiddlewareChain() throws {
        let root = RootMiddlewareReducer.Store(initialState: RootMiddlewareReducer.State())

        // Create parent
        root.send(.createParent)

        guard let parent = root._parent else {
            XCTFail("Parent store not found")
            return
        }

        // Create child
        parent.send(.createChild)

        guard let child = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Child sends event
        child.send(.taskCompleted("task1"))

        // Root intercepts: parent.createChild + parent.childDelegated = 2
        //   (root can only see ParentMiddlewareReducer.Store events; ChildReducer events fail the cast)
        //   createParent: root has no ancestors (it IS the root)
        //   taskCompleted: root sees it but cast to ParentMiddlewareReducer.Store fails → no count
        XCTAssertEqual(root.state.rootInterceptions, 2, "Root intercepts parent-level events only")

        // Parent intercepts: taskCompleted from child = 1
        //   createChild self-intercept: cast to ChildReducer.Store fails → no count
        //   childDelegated self-intercept: same, cast fails → no count
        XCTAssertEqual(parent.state.interceptedEvents, 1, "Parent intercepts only child's events")
        XCTAssertEqual(parent.state.delegatedTasks, ["task1"])

        // Child should have executed
        XCTAssertEqual(child.state.executedEvents.count, 1)
    }

    func testMultiLevelMultipleEvents() throws {
        let root = RootMiddlewareReducer.Store(initialState: RootMiddlewareReducer.State())
        root.send(.createParent)

        guard let parent = root._parent else {
            XCTFail("Parent store not found")
            return
        }

        parent.send(.createChild)

        guard let child = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Send 3 events
        child.send(.taskCompleted("task1"))
        child.send(.simpleAction)
        child.send(.taskCompleted("task2"))

        // Root intercepts parent-level events: createChild + childDelegated1 + childDelegated2 = 3
        //   (ChildReducer events fail the ParentMiddlewareReducer.Store cast at root level)
        XCTAssertEqual(root.state.rootInterceptions, 3, "Root intercepts parent-level events only")

        // Parent intercepts child events: task1 + simpleAction + task2 = 3
        //   (self-sent .childDelegated events fail the ChildReducer.Store cast)
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
}
