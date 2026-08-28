//
//  HierarchicalDelegationReentrancyTests.swift
//  Statoscope
//
//  Regression test for a synchronous-reentrancy defect in the MiddlewareReducer / hierarchical
//  delegation mechanism (see Store.updateSubscope in Sources/Statoscope/Reducer/Store.swift).
//
//  Mechanism under test, with a 3-level Child -> Parent -> GrandParent hierarchy:
//
//   1. Child sends `.ping`. Because GrandParent conforms to MiddlewareReducer, the event
//      is routed (top-down) into `GrandParent.updateSubstate(...)` BEFORE Child's own
//      `update()` runs. Per the framework's own "grandparents see the original grandchild"
//      design, GrandParent receives Child's event and When type directly (Parent is skipped).
//   2. GrandParent's `updateSubstate` reacts to `.ping` by tearing down the Parent/Child
//      subtree the event came from (`state.parent = nil`), and returns `.intercept(...)`
//      to say so explicitly.
//   3. `Store.updateSubscope` honors that: it sends the delegated When, but does NOT call
//      `event.forward()` — Child's original `.ping` is consumed rather than delivered into
//      a subtree that was just synchronously destroyed by a reaction to that very event.
//
//  Before the fix, `updateSubstate` returned a plain `When?` and `Store.updateSubscope` called
//  `event.forward()` unconditionally, with no way for a reaction to block delivery. A middleware
//  that tore its own child down still had that child's original event land on it afterward —
//  state silently written to an object no longer reachable from the tree. `SubstateOutcome`
//  (Sources/Statoscope/MiddlewareReducer.swift) makes that an explicit, atomic choice: `.pass`/
//  `.react` still forward, `.intercept` consumes the event. This test pins the `.intercept` case.
//

import XCTest
@_spi(Internal) @testable import Statoscope

// MARK: - Test Reducers

@Reducer
private struct RTChildReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var pings: Int = 0
    }

    enum When {
        case ping
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .ping:
            state.pings += 1
        }
    }
}

@Reducer
private struct RTParentReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: RTChildReducer.State?
    }

    enum When {
        case setup
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .setup:
            state.child = RTChildReducer.State()
        }
    }
}

/// GrandParent reacts to the CHILD's own event type directly (grandparents see the original
/// grandchild, not a Parent-level proxy), and tears down the whole Parent/Child subtree in
/// response — simulating a realistic "reset on repeated ping" or "cascading invalidation" rule.
@Reducer
private struct RTGrandParentReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var parent: RTParentReducer.State?
        var teardownCount: Int = 0
    }

    enum When {
        case setup
        case teardownSubtree
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When> {
        guard let when = childWhen as? RTChildReducer.When else { return .pass }
        switch when {
        case .ping:
            // Tearing the subtree down makes forwarding the ping unsafe — consume it.
            return .intercept(.teardownSubtree)
        }
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .setup:
            state.parent = RTParentReducer.State()
        case .teardownSubtree:
            state.teardownCount += 1
            state.parent = nil
        }
    }
}

// MARK: - Test Case

final class HierarchicalDelegationReentrancyTests: XCTestCase {

    /// Once GrandParent's middleware has torn the Parent/Child subtree down in reaction to
    /// Child's `.ping` (via `.intercept`), that same `.ping` must not also silently land on
    /// Child's state — the event is consumed, not forwarded.
    func testInterceptedChildEventDoesNotApplyAfterMiddlewareTearsDownItsOwnSubtree() throws {
        let grandParent = RTGrandParentReducer.Store(initialState: RTGrandParentReducer.State())
        grandParent.send(.setup)

        guard let parentStore = grandParent.children.parent else {
            XCTFail("Parent store not created")
            return
        }
        parentStore.send(.setup)

        guard let childStore = parentStore.children.child else {
            XCTFail("Child store not created")
            return
        }

        // Child sends the event that triggers GrandParent's delegation and subtree teardown.
        childStore.send(.ping)

        // GrandParent's middleware did react and did tear the subtree down.
        XCTAssertEqual(grandParent.state.teardownCount, 1, "GrandParent's delegated reaction should run once")
        XCTAssertNil(grandParent.state.parent, "GrandParent's reaction removed the Parent/Child subtree")

        // FIXED: `.intercept` stopped `event.forward()` from running, so Child's own `.ping`
        // never reached its `update()` — no write landed on the now-unreachable object.
        XCTAssertEqual(
            childStore.state.pings,
            0,
            "Child's ping must not silently apply once its own subtree was torn down mid-flight " +
            "by the very middleware reaction that ping triggered"
        )
    }
}
