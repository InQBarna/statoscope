//
//  ReducerUpdateSubstateErrorTests.swift
//  Statoscope
//
//  Does MiddlewareReducer.updateSubstate see a grandchild's thrown error the way the classic
//  Statostore's HierarchialScopeMiddleWare.updateSubscope can? No — the generated updateSubscope
//  (Sources/Statoscope/Reducer/Store.swift) calls `try event.forward()` with no do/catch, so a
//  throw from the child's own update() propagates straight past updateSubstate, which is never
//  invoked for that event. See HierarchicalMiddlewareErrorTests for the classic-pattern contrast,
//  where a custom updateSubscope CAN choose to catch it.
//

import Foundation
import XCTest
@_spi(Internal) @testable import Statoscope

private struct DeliberateReducerTestError: Error, Equatable {
    let context: String
}

@Reducer
private struct ErrorCaptureChildReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var succeededCount: Int = 0
    }

    enum When {
        case succeed
        case fail
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .succeed: state.succeededCount += 1
        case .fail: throw DeliberateReducerTestError(context: "child failed")
        }
    }
}

@Reducer
private struct ErrorCaptureParentReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var child: ErrorCaptureChildReducer.State?
    }

    enum When { case createChild }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createChild: state.child = ErrorCaptureChildReducer.State()
        }
    }
}

@Reducer
private struct ErrorCaptureRootReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var parent: ErrorCaptureParentReducer.State?
        var interceptionCount: Int = 0
    }

    enum When {
        case createParent
        case intercepted
    }

    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> When? {
        .intercepted
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createParent: state.parent = ErrorCaptureParentReducer.State()
        case .intercepted: state.interceptionCount += 1
        }
    }
}

final class ReducerUpdateSubstateErrorTests: XCTestCase {

    func testUpdateSubstateIsNotCalledWhenGrandchildThrows() throws {
        let root = ErrorCaptureRootReducer.Store(initialState: .init())
        root.send(.createParent)
        // .createChild is Parent's own event — Parent is itself a descendant of Root, so this
        // self-send already bubbles up to Root's updateSubstate once (same "self-delegation
        // bubbles to root" behavior proven for the classic pattern in
        // HierarchicalDelegationTests.testMultipleLevelsIntercept). Capture the count *after*
        // setup, before the event actually under test, so that baseline doesn't confound the
        // assertion below.
        root.children.parent?.send(.createChild)
        let interceptionsBeforeEvent = root.state.interceptionCount

        // Two levels below the root — the grandchild, not a direct child. Non-throwing send(),
        // matching how the app actually dispatches events (errors are logged, not propagated to
        // the caller) — see StatoscopeLogger's ".errors" output for where it actually goes.
        root.children.parent?.children.child?.send(.fail)

        XCTAssertEqual(
            root.state.interceptionCount, interceptionsBeforeEvent,
            "updateSubstate did not run for the failing event — the throw pre-empted it"
        )
    }

    func testUpdateSubstateIsCalledWhenGrandchildSucceeds() throws {
        let root = ErrorCaptureRootReducer.Store(initialState: .init())
        root.send(.createParent)
        root.children.parent?.send(.createChild)
        let interceptionsBeforeEvent = root.state.interceptionCount

        root.children.parent?.children.child?.send(.succeed)

        XCTAssertEqual(
            root.state.interceptionCount, interceptionsBeforeEvent + 1,
            "updateSubstate runs normally when nothing throws"
        )
        XCTAssertEqual(root.children.parent?.children.child?.state.succeededCount, 1)
    }
}
