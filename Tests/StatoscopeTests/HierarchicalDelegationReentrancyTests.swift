//
//  HierarchicalDelegationReentrancyTests.swift
//  Statoscope
//
//  Confirms the hierarchical delegation mechanism (see Store.updateSubscope in
//  Sources/Statoscope/Reducer/Store.swift) is safe even when an ancestor's reaction tears down
//  the very subtree the triggering event came from.
//
//  Mechanism under test, with a 3-level Child -> Parent -> GrandParent hierarchy:
//
//   1. Child sends `.ping`. `event.forward()` always runs first, so Child's own `update()`
//      processes `.ping` on a still-valid, not-yet-torn-down copy of itself.
//   2. Only after that does the event reach `GrandParent.updateSubstate(...)` — per the
//      framework's own "grandparents see the original grandchild" design, GrandParent receives
//      Child's event and When type directly (Parent is skipped, no relay needed there).
//   3. GrandParent reacts by tearing down the Parent/Child subtree the event came from
//      (`state.parent = nil`) and delegates `.teardownSubtree`.
//
//  Because forwarding always happens before any ancestor reaction, there is no ordering in
//  which a reaction can destroy a subtree before the event it's reacting to has already been
//  safely applied to it — the race `SubstateOutcome.intercept` used to exist to guard against
//  (see git history) cannot occur under this ordering, so there's nothing left to intercept.
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
    ) throws -> When? {
        guard let when = childWhen as? RTChildReducer.When else { return nil }
        switch when {
        case .ping:
            return .teardownSubtree
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

    /// Child's own `.ping` handler always runs first — safely, on a still-valid subtree — and
    /// only afterward does GrandParent's reaction get to tear that subtree down. Both effects
    /// are observed: the child's own update applied, and the subtree is gone.
    func testChildsOwnUpdateAppliesSafelyBeforeAncestorReactionTearsDownItsSubtree() throws {
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

        // Child's own update() ran first, on the still-live object, before anything tore it down.
        XCTAssertEqual(childStore.state.pings, 1, "Child's own .ping handler applied safely")

        // GrandParent's reaction then ran, and did tear the subtree down.
        XCTAssertEqual(grandParent.state.teardownCount, 1, "GrandParent's delegated reaction should run once")
        XCTAssertNil(grandParent.state.parent, "GrandParent's reaction removed the Parent/Child subtree")
    }
}
