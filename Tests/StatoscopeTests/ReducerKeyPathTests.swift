//
//  ReducerKeyPathTests.swift
//  Statoscope
//
//  Covers `ReducerKeyPath` (Sources/Statoscope/Reducer/ReducerKeyPath.swift) — the position-based
//  path from a root Store down to a descendant, replacing `ReducerStoreRegistry`'s type-keyed
//  weak stack. Exercises real `@Reducer`/`@SubState` types end to end: the macro-generated
//  `_childSlots` registering each hop with `_SubStateHopRegistry`, and `ReducerKeyPath.append`
//  resolving through it — not just the registry in isolation.
//

import XCTest
@testable import Statoscope

// MARK: - Test Reducers (File Scope)

@Reducer
private struct RKPGrandchildReducer {
    struct State {
        var label: String = "grandchild"
    }
    enum When {}
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {}
}

@Reducer
private struct RKPChildReducer {
    struct State {
        var label: String = "child"
        @SubState var grandchild: RKPGrandchildReducer.State?
    }
    enum When {
        case showGrandchild
        case hideGrandchild
    }
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showGrandchild: state.grandchild = RKPGrandchildReducer.State()
        case .hideGrandchild: state.grandchild = nil
        }
    }
}

@Reducer
private struct RKPParentReducer {
    struct State {
        var label: String = "parent"
        @SubState var child: RKPChildReducer.State?
    }
    enum When {
        case showChild
        case hideChild
    }
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showChild: state.child = RKPChildReducer.State()
        case .hideChild: state.child = nil
        }
    }
}

// A second, sibling child slot sharing RKPChildReducer's own State type, so the hop registry's
// per-property (not per-type-pair) keying is actually exercised, not just assumed.
@Reducer
private struct RKPParentWithTwoSameTypeChildrenReducer {
    struct State {
        @SubState var first: RKPChildReducer.State?
        @SubState var second: RKPChildReducer.State?
    }
    enum When { case showFirst, showSecond }
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .showFirst: state.first = RKPChildReducer.State()
        case .showSecond: state.second = RKPChildReducer.State()
        }
    }
}

// Exclusively for testPreviewPathResolvesNilWithoutTouchingTheRegistry — never otherwise
// constructed anywhere in this file, so no Store of either type ever gets created, and no
// _SubStateHopRegistry entry for this pair can exist from some other test's side effects.
@Reducer
private struct RKPNeverInstantiatedChildReducer {
    struct State { var label: String = "never instantiated" }
    enum When {}
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {}
}

@Reducer
private struct RKPNeverInstantiatedParentReducer {
    struct State { @SubState var child: RKPNeverInstantiatedChildReducer.State? }
    enum When {}
    static func update(
        _ when: When, state: inout State,
        effectsState: inout EffectsState<When>, dependencies: ReducerDependencies
    ) throws {}
}

final class ReducerKeyPathTests: XCTestCase {

    func testRootResolvesToTheRootStoreItself() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        let path = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
        XCTAssertTrue(path.resolve(from: store) === store)
    }

    func testPreviewPathResolvesNilWithoutTouchingTheRegistry() {
        // Built before any Store of this pair exists anywhere in the process (these two
        // reducers are scoped exclusively to this test) — if `.preview` touched
        // _SubStateHopRegistry the way `.root.append(_:as:)` does, this line itself would hit
        // its fatalError fallback instead of constructing successfully.
        let path = ReducerKeyPath<RKPNeverInstantiatedParentReducer, RKPNeverInstantiatedChildReducer>.preview
        let store = RKPNeverInstantiatedParentReducer.Store(initialState: RKPNeverInstantiatedParentReducer.State())
        XCTAssertNil(path.resolve(from: store))
    }

    func testOneHopResolvesNilWhenChildAbsent() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        let childPath = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
            .append(\.child, as: RKPChildReducer.self)
        XCTAssertNil(childPath.resolve(from: store))
    }

    func testOneHopResolvesTheLiveChildStoreOnceCreated() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        store.send(.showChild)
        let childPath = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
            .append(\.child, as: RKPChildReducer.self)
        XCTAssertTrue(childPath.resolve(from: store) === store.children.child)
    }

    func testTwoHopsResolveTheLiveGrandchildStore() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        store.send(.showChild)
        store.children.child?.send(.showGrandchild)

        let grandchildPath = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
            .append(\.child, as: RKPChildReducer.self)
            .append(\.grandchild, as: RKPGrandchildReducer.self)

        XCTAssertTrue(grandchildPath.resolve(from: store) === store.children.child?.children.grandchild)
        XCTAssertEqual(grandchildPath.resolve(from: store)?.state.label, "grandchild")
    }

    func testTwoHopsResolveNilWhenOnlyTheFirstHopExists() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        store.send(.showChild)
        // Grandchild never created.

        let grandchildPath = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
            .append(\.child, as: RKPChildReducer.self)
            .append(\.grandchild, as: RKPGrandchildReducer.self)

        XCTAssertNil(grandchildPath.resolve(from: store))
    }

    func testTwoHopsResolveNilAfterTheFirstHopIsTornDown() {
        let store = RKPParentReducer.Store(initialState: RKPParentReducer.State())
        store.send(.showChild)
        store.children.child?.send(.showGrandchild)
        store.send(.hideChild)

        let grandchildPath = ReducerKeyPath<RKPParentReducer, RKPParentReducer>.root
            .append(\.child, as: RKPChildReducer.self)
            .append(\.grandchild, as: RKPGrandchildReducer.self)

        XCTAssertNil(grandchildPath.resolve(from: store), "a torn-down ancestor must not resolve a stale descendant")
    }

    func testSiblingSlotsOfTheSameChildReducerTypeResolveIndependently() {
        let store = RKPParentWithTwoSameTypeChildrenReducer.Store(
            initialState: RKPParentWithTwoSameTypeChildrenReducer.State()
        )
        store.send(.showFirst)

        let firstPath = ReducerKeyPath<RKPParentWithTwoSameTypeChildrenReducer, RKPParentWithTwoSameTypeChildrenReducer>.root
            .append(\.first, as: RKPChildReducer.self)
        let secondPath = ReducerKeyPath<RKPParentWithTwoSameTypeChildrenReducer, RKPParentWithTwoSameTypeChildrenReducer>.root
            .append(\.second, as: RKPChildReducer.self)

        XCTAssertNotNil(firstPath.resolve(from: store))
        XCTAssertNil(secondPath.resolve(from: store), "a same-type sibling slot must not resolve the other slot's store")
    }
}
