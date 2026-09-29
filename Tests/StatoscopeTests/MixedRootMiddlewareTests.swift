//
//  MixedRootMiddlewareTests.swift
//  Statoscope
//
//  Proves the non-invasive design end to end: a classic Statostore root, sitting above an
//  all-Reducer subtree, can transform an event before it reaches a Reducer descendant's own
//  update() and can capture an error that descendant throws — using only
//  SubscopeEvent.forward(transformedWhen:), a change to the shared engine
//  (ScopeImplementation.swift). Nothing in MiddlewareReducer, Store<R>, ReducerDispatchable, or
//  ReducerMacro.swift changed to make this work.
//

import Foundation
import XCTest
@_spi(Internal) @testable import Statoscope

private struct MixedTestError: Error, Equatable {
    let context: String
}

@Reducer
private struct MixedGrandchildReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var lastProcessed: String?
    }

    enum When {
        case raw(String)
        case fail
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .raw(let s): state.lastProcessed = s
        case .fail: throw MixedTestError(context: "grandchild failed")
        }
    }
}

@Reducer
private struct MixedParentReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        @SubState var grandchild: MixedGrandchildReducer.State?
    }

    enum When { case createGrandchild }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .createGrandchild: state.grandchild = MixedGrandchildReducer.State()
        }
    }
}

/// Classic Statostore root — hand-written, full freedom over updateSubscope, unlike a Reducer's
/// macro-generated one. Sits two levels above MixedGrandchildReducer (Root → Parent → Grandchild,
/// matching this project's established "prove any-depth" convention).
private final class MixedRootScope: Statostore, HierarchialScopeMiddleWare, ObservableObject {
    @Subscope var parent: MixedParentReducer.Store?
    private(set) var capturedErrors: [Error] = []
    private(set) var transformedCount = 0

    enum When { case noop }
    func update(_ when: When) throws { }

    func updateSubscope<Child: ScopeImplementation>(_ event: SubscopeEvent<Child>) throws {
        // Transform: uppercase any .raw(_) from the grandchild before it ever reaches the
        // Reducer's own update() — impossible with bare forward(), which is parameterless.
        if let childWhen = event.when as? MixedGrandchildReducer.When,
           case .raw(let s) = childWhen,
           let transformed = MixedGrandchildReducer.When.raw(s.uppercased()) as? Child.When {
            transformedCount += 1
            do {
                try event.forward(transformedWhen: transformed)
            } catch {
                capturedErrors.append(error)
            }
            return
        }

        // Catch: any other event (including .fail) forwards unchanged, wrapped so a thrown
        // error from the Reducer descendant's own update() is captured here, not just logged.
        do {
            try event.forward()
        } catch {
            capturedErrors.append(error)
        }
    }
}

final class MixedRootMiddlewareTests: XCTestCase {

    func testClassicRootTransformsReducerGrandchildEvent() throws {
        let root = MixedRootScope()
        root.parent = MixedParentReducer.Store(initialState: .init())
        root.parent?.send(.createGrandchild)

        root.parent?.children.grandchild?.send(.raw("hello"))

        XCTAssertEqual(root.transformedCount, 1)
        XCTAssertEqual(root.parent?.children.grandchild?.state.lastProcessed, "HELLO",
                        "the Reducer's own update() received the transformed event, not the original")
    }

    func testClassicRootCapturesReducerGrandchildThrownError() throws {
        let root = MixedRootScope()
        root.parent = MixedParentReducer.Store(initialState: .init())
        root.parent?.send(.createGrandchild)

        root.parent?.children.grandchild?.send(.fail)

        XCTAssertEqual(root.capturedErrors.count, 1)
        XCTAssertEqual(root.capturedErrors.first as? MixedTestError, MixedTestError(context: "grandchild failed"))
    }
}
