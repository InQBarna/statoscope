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
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When? {
        // Track interception
        parentState.interceptedEvents += 1

        // Type-cast to specific child
        if let childWhen = childWhen as? ChildReducer.When {
            switch childWhen {
            case .taskCompleted(let task):
                // React BEFORE child processes event
                return .childDelegated(task)  // Delegate to parent

            case .simpleAction:
                return nil  // No delegation needed
            }
        }
        return nil
        // Framework automatically forwards to child
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

    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When? {
        // Root intercepts ALL events in subtree
        parentState.rootInterceptions += 1
        return nil  // No delegation
        // Framework automatically forwards
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
        // Parent intercepts its own .createChild event (self-interception)
        XCTAssertEqual(parent.state.interceptedEvents, 1, "Parent self-intercepts .createChild")

        // Get child store
        guard let child = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Child sends event
        child.send(.taskCompleted("task1"))

        // Parent intercepts: child's .taskCompleted + parent's .childDelegated (self) = 2 more
        XCTAssertEqual(parent.state.interceptedEvents, 3, "Parent intercepts child + self delegation")
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

        // Parent should have intercepted: createChild(self) + taskCompleted + childDelegated(self) + simpleAction = 4
        XCTAssertEqual(parent.state.interceptedEvents, 4, "Parent intercepts all events including self")

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

        // Root should have intercepted (all events in subtree)
        // Root intercepts: createParent(self) + createChild + taskCompleted + childDelegated = 4
        XCTAssertEqual(root.state.rootInterceptions, 4, "Root intercepts all subtree events")

        // Parent should have intercepted: createChild(self) + taskCompleted + childDelegated(self) = 3
        XCTAssertEqual(parent.state.interceptedEvents, 3, "Parent intercepts child + self events")
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

        // Root intercepts: createParent + createChild + task1 + childDelegated1 + simpleAction + task2 + childDelegated2 = 7
        XCTAssertEqual(root.state.rootInterceptions, 7, "Root intercepts all events")

        // Parent intercepts: createChild + task1 + childDelegated1 + simpleAction + task2 + childDelegated2 = 6
        XCTAssertEqual(parent.state.interceptedEvents, 6)
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
