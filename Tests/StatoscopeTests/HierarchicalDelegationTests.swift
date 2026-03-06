//
//  HierarchicalDelegationTests.swift
//  Statoscope
//
//  Tests for multi-level hierarchical delegation using HierarchialScopeMiddleWare
//

import Foundation
import XCTest
@_spi(Internal) @testable import Statoscope

// MARK: - Test Scopes

// Shared event log for capturing execution order across all scopes
private var globalEventLog: [String] = []

/// Root scope that intercepts all descendant events
final class RootScope: Statostore, HierarchialScopeMiddleWare, ObservableObject {
    @Subscope var parent: ParentScope?
    var interceptedEvents: [String] = []
    var beforeCount: Int = 0
    var afterCount: Int = 0

    enum When {
        case createParent
    }

    func update(_ when: When) throws {
        switch when {
        case .createParent:
            parent = ParentScope()
        }
    }

    func updateSubscope<Child: ScopeImplementation>(
        _ event: SubscopeEvent<Child>
    ) throws {
        // BEFORE forwarding
        beforeCount += 1
        let beforeMsg = "Root BEFORE: \(event.when)"
        interceptedEvents.append(beforeMsg)
        globalEventLog.append(beforeMsg)

        // Forward to next level in chain
        try event.forward()

        // AFTER child completes
        afterCount += 1
        let afterMsg = "Root AFTER: \(event.when)"
        interceptedEvents.append(afterMsg)
        globalEventLog.append(afterMsg)
    }
}

/// Parent scope that intercepts child events and can delegate to itself
final class ParentScope: Statostore, HierarchialScopeMiddleWare, ObservableObject {
    @Subscope var child: ChildScope?
    var interceptedEvents: [String] = []
    var receivedDelegations: [String] = []
    var beforeCount: Int = 0
    var afterCount: Int = 0

    enum When {
        case createChild
        case childDelegated(String)
    }

    func update(_ when: When) throws {
        switch when {
        case .createChild:
            child = ChildScope()
        case .childDelegated(let task):
            receivedDelegations.append(task)
        }
    }

    func updateSubscope<Child: ScopeImplementation>(
        _ event: SubscopeEvent<Child>
    ) throws {
        // BEFORE forwarding
        beforeCount += 1
        let beforeMsg = "Parent BEFORE: \(event.when)"
        interceptedEvents.append(beforeMsg)
        globalEventLog.append(beforeMsg)

        // Check if we should delegate to self
        if let childWhen = event.when as? ChildScope.When {
            if case .taskCompleted(let task) = childWhen {
                // Delegate before forwarding
                send(.childDelegated(task))
            }
        }

        // Forward to next level in chain
        try event.forward()

        // AFTER child completes
        afterCount += 1
        let afterMsg = "Parent AFTER: \(event.when)"
        interceptedEvents.append(afterMsg)
        globalEventLog.append(afterMsg)
    }
}

/// Child scope that performs actual work
final class ChildScope: Statostore, ObservableObject {
    var executedEvents: [When] = []

    enum When {
        case taskCompleted(String)
        case simpleAction
    }

    func update(_ when: When) throws {
        executedEvents.append(when)
    }
}

/// Parent that can block unauthorized events
final class AuthParent: Statostore, HierarchialScopeMiddleWare, ObservableObject {
    @Subscope var child: RestrictedChild?
    var blockedEvents: [RestrictedChild.When] = []
    var isAuthEnabled: Bool = true

    enum When {
        case createChild
        case toggleAuth
    }

    func update(_ when: When) throws {
        switch when {
        case .createChild:
            child = RestrictedChild()
        case .toggleAuth:
            isAuthEnabled.toggle()
        }
    }

    func updateSubscope<Child: ScopeImplementation>(
        _ event: SubscopeEvent<Child>
    ) throws {
        if let childWhen = event.when as? RestrictedChild.When {
            // Block unauthorized events
            if case .unauthorizedAction = childWhen, isAuthEnabled {
                blockedEvents.append(childWhen)
                return  // Don't forward - event blocked!
            }
        }

        // Forward allowed events
        try event.forward()
    }
}

final class RestrictedChild: Statostore, ObservableObject {
    var executedEvents: [When] = []

    enum When {
        case authorizedAction
        case unauthorizedAction
    }

    func update(_ when: When) throws {
        executedEvents.append(when)
    }
}

// MARK: - Test Cases

final class HierarchicalDelegationTests: XCTestCase {

    // MARK: - Single Level Tests

    func testParentInterceptsChildEvent() throws {
        let parent = ParentScope()
        parent.child = ChildScope()

        // Child sends event
        parent.child?.send(.taskCompleted("task1"))

        // Parent intercepts twice: once for child event, once for its own .childDelegated event (self-interception)
        XCTAssertEqual(parent.beforeCount, 2, "Parent intercepts child event + self delegation")
        XCTAssertEqual(parent.afterCount, 2, "Parent reacts after both interceptions")
        XCTAssertEqual(parent.receivedDelegations, ["task1"], "Parent should receive delegation")

        // Child should have executed
        XCTAssertEqual(parent.child?.executedEvents.count, 1)
    }

    func testParentDelegationPattern() throws {
        let parent = ParentScope()
        parent.child = ChildScope()

        // Multiple child events
        parent.child?.send(.taskCompleted("task1"))
        parent.child?.send(.simpleAction)
        parent.child?.send(.taskCompleted("task2"))

        // Parent received delegations only for taskCompleted
        XCTAssertEqual(parent.receivedDelegations, ["task1", "task2"])

        // Parent intercepted: 2 taskCompleted (each with self-delegation) + 1 simpleAction = 5 total
        // (taskCompleted triggers 2 interceptions each: child event + own .childDelegated event)
        XCTAssertEqual(parent.beforeCount, 5, "2 taskCompleted (2 interceptions each) + 1 simpleAction = 5")
        XCTAssertEqual(parent.afterCount, 5)

        // Child executed all events
        XCTAssertEqual(parent.child?.executedEvents.count, 3)
    }

    // MARK: - Multi-Level Tests (Phase 2)

    func testMultipleLevelsIntercept() throws {
        let root = RootScope()
        root.parent = ParentScope()
        root.parent?.child = ChildScope()

        // Child sends event
        root.parent?.child?.send(.taskCompleted("task1"))

        // Root intercepts ALL events in subtree: child event + parent's self-delegation = 2
        XCTAssertEqual(root.beforeCount, 2, "Root intercepts child event + parent self-delegation")
        XCTAssertEqual(root.afterCount, 2, "Root reacts after both events")

        // Parent intercepts: child event + self delegation = 2
        XCTAssertEqual(root.parent?.beforeCount, 2, "Parent intercepts child + self delegation")
        XCTAssertEqual(root.parent?.afterCount, 2, "Parent reacts after both")

        // Parent should have delegated to itself
        XCTAssertEqual(root.parent?.receivedDelegations, ["task1"])

        // Child should have executed once
        XCTAssertEqual(root.parent?.child?.executedEvents.count, 1)
    }

    func testTopDownOrderPreservation() throws {
        globalEventLog = []  // Reset global log
        let root = RootScope()
        root.parent = ParentScope()
        root.parent?.child = ChildScope()

        // Child sends event
        root.parent?.child?.send(.simpleAction)

        // Verify order: Root BEFORE → Parent BEFORE → Child → Parent AFTER → Root AFTER
        let expectedOrder = [
            "Root BEFORE: simpleAction",
            "Parent BEFORE: simpleAction",
            "Parent AFTER: simpleAction",
            "Root AFTER: simpleAction"
        ]

        XCTAssertEqual(globalEventLog, expectedOrder, "Top-down flow not preserved")
    }

    // MARK: - Blocking Tests

    func testParentBlocksUnauthorizedEvents() throws {
        let parent = AuthParent()
        parent.child = RestrictedChild()

        // Authorized event - should reach child
        parent.child?.send(.authorizedAction)
        XCTAssertEqual(parent.child?.executedEvents.count, 1, "Authorized event should execute")
        XCTAssertEqual(parent.blockedEvents.count, 0, "No events should be blocked")

        // Unauthorized event - should be blocked
        parent.child?.send(.unauthorizedAction)
        XCTAssertEqual(parent.child?.executedEvents.count, 1, "Child should still have only 1 event")
        XCTAssertEqual(parent.blockedEvents.count, 1, "Parent should block unauthorized event")
    }

    func testBlockingCanBeToggled() throws {
        let parent = AuthParent()
        parent.child = RestrictedChild()

        // With auth enabled, event is blocked
        parent.child?.send(.unauthorizedAction)
        XCTAssertEqual(parent.child?.executedEvents.count, 0)
        XCTAssertEqual(parent.blockedEvents.count, 1)

        // Disable auth
        parent.send(.toggleAuth)

        // Now event is allowed
        parent.child?.send(.unauthorizedAction)
        XCTAssertEqual(parent.child?.executedEvents.count, 1, "Event should be allowed when auth disabled")
    }

    // MARK: - Edge Cases

    func testChildWithoutMiddlewareParent() throws {
        // Child created without parent implementing HierarchialScopeMiddleWare
        let child = ChildScope()

        // Should work normally (no interception)
        child.send(.simpleAction)

        XCTAssertEqual(child.executedEvents.count, 1, "Child should execute without parent")
    }

    func testParentWithoutChild() throws {
        let parent = ParentScope()

        // Parent can still send events to itself
        parent.send(.createChild)

        XCTAssertNotNil(parent.child, "Parent should create child")
    }

    func testDeepHierarchy() throws {
        // Create 3-level hierarchy: Root → Parent → Child
        let root = RootScope()
        root.parent = ParentScope()
        root.parent?.child = ChildScope()

        // Send multiple events
        for i in 1...5 {
            root.parent?.child?.send(.taskCompleted("task\(i)"))
        }

        // Root intercepts ALL events in subtree: 5 child + 5 parent self-delegations = 10
        XCTAssertEqual(root.beforeCount, 10, "Root intercepts all events: 5 child + 5 parent self = 10")
        XCTAssertEqual(root.afterCount, 10, "Root reacts 10 times")

        // Parent intercepts: 5 child events + 5 self delegations = 10 total
        XCTAssertEqual(root.parent?.beforeCount, 10, "Parent intercepts 5 child + 5 self = 10")
        XCTAssertEqual(root.parent?.afterCount, 10, "Parent reacts 10 times")

        // Child executed all 5 events
        XCTAssertEqual(root.parent?.child?.executedEvents.count, 5, "Child executes 5 events")

        // Parent delegated all 5
        XCTAssertEqual(root.parent?.receivedDelegations.count, 5, "Parent delegated 5 times")
    }
}
