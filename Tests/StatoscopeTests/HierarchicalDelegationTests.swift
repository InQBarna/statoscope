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
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws {
        // BEFORE forwarding
        beforeCount += 1
        interceptedEvents.append("Root BEFORE: \(when)")

        // Forward to child (Phase 1: single-level only)
        try child._unsafeSendImplementation(when)

        // AFTER child completes
        afterCount += 1
        interceptedEvents.append("Root AFTER: \(when)")
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
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws {
        // BEFORE forwarding
        beforeCount += 1
        interceptedEvents.append("Parent BEFORE: \(when)")

        // Check if we should delegate to self
        if let childWhen = when as? ChildScope.When {
            if case .taskCompleted(let task) = childWhen {
                // Delegate before forwarding
                send(.childDelegated(task))
            }
        }

        // Forward to child (Phase 1: single-level only)
        try child._unsafeSendImplementation(when)

        // AFTER child completes
        afterCount += 1
        interceptedEvents.append("Parent AFTER: \(when)")
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
        _ child: Child,
        _ when: Child.When,
        _ keyPath: AnyKeyPath
    ) throws {
        if let childWhen = when as? RestrictedChild.When {
            // Block unauthorized events
            if case .unauthorizedAction = childWhen, isAuthEnabled {
                blockedEvents.append(childWhen)
                return  // Don't forward to child - event blocked!
            }
        }

        // Forward allowed events - use _unsafeSendImplementation to bypass hierarchy check
        try child._unsafeSendImplementation(when)
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

    // MARK: - Multi-Level Tests (Future Phase)

    // TODO: Multi-level parent chains require additional framework support
    // Phase 1 only supports single-level parent-child interception
    // These tests document the expected behavior for future implementation

    func testMultipleLevelsIntercept_NotYetSupported() throws {
        // This test is disabled until Phase 2 implements proper multi-level chain handling
        // Expected behavior: Root → Parent → Child with each level intercepting
        throw XCTSkip("Multi-level interception requires Phase 2 implementation")
    }

    func testTopDownOrderPreservation_NotYetSupported() throws {
        // This test is disabled until Phase 2 implements proper multi-level chain handling
        // Expected order: Root BEFORE → Parent BEFORE → Child → Parent AFTER → Root AFTER
        throw XCTSkip("Multi-level interception requires Phase 2 implementation")
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

    func testDeepHierarchy_NotYetSupported() throws {
        // This test requires multi-level parent chains which are not yet supported in Phase 1
        // Expected: Root → Parent → Child with all levels intercepting
        throw XCTSkip("Multi-level interception requires Phase 2 implementation")
    }
}
