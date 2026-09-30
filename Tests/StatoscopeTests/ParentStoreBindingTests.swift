//
//  ParentStoreBindingTests.swift
//  Statoscope
//
//  Covers @SuperScope / ParentStoreBinding — the incremental-migration bridge letting a
//  Reducer's State read a not-yet-migrated legacy Statostore parent's live state. Previously
//  untested: no test exercised @SuperScope, ParentStoreBinding, or resolveAncestor at all.
//

import Foundation
import XCTest
@testable import Statoscope

private final class LegacyParentStore: Statostore, Injectable, ObservableObject {
    typealias When = Void
    @Published var count: Int = 0
    @Subscope var child: MigratedChildReducer.Store?
    static var defaultValue: LegacyParentStore { LegacyParentStore() }
    func update(_ when: Void) throws { }
}

@Reducer
private struct MigratedChildReducer {
    struct State {
        @SuperScope var parent: LegacyParentStore
        var doubled: Int = 0
    }
    enum When { case sync }
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .sync: state.doubled = state.parent.count * 2
        }
    }
}

private final class ObservedParentStore: Statostore, Injectable, ObservableObject {
    typealias When = Void
    @Published var count: Int = 0
    @Subscope var child: ObservingChildReducer.Store?
    static var defaultValue: ObservedParentStore { ObservedParentStore() }
    func update(_ when: Void) throws { }
}

@Reducer
private struct ObservingChildReducer {
    struct State {
        @SuperScope(observed: true) var parent: ObservedParentStore
    }
    enum When { case noop }
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws { }
}

final class ParentStoreBindingTests: XCTestCase {

    func testSuperScopeResolvesLiveParentState() throws {
        let parent = LegacyParentStore()
        parent.child = MigratedChildReducer.Store(initialState: .init())

        parent.count = 21
        try parent.child?.send(.sync)

        XCTAssertEqual(parent.child?.state.doubled, 42)
    }

    func testSuperScopeReflectsParentStateChangesAcrossUpdates() throws {
        let parent = LegacyParentStore()
        parent.child = MigratedChildReducer.Store(initialState: .init())

        parent.count = 2
        try parent.child?.send(.sync)
        XCTAssertEqual(parent.child?.state.doubled, 4)

        parent.count = 10
        try parent.child?.send(.sync)
        XCTAssertEqual(parent.child?.state.doubled, 20)
    }

    func testSuperScopeFallsBackToDefaultValueWhenNoParentInTree() {
        let orphan = MigratedChildReducer.Store(initialState: .init())
        // No ancestor of type LegacyParentStore exists in this tree — resolveAncestor()
        // falls back to LegacyParentStore.defaultValue, a fresh instance with count == 0.
        XCTAssertEqual(orphan.state.parent.count, 0)
    }

    func testSuperScopeObservedRelaysParentObjectWillChangeExactlyOnce() {
        let parent = ObservedParentStore()
        parent.child = ObservingChildReducer.Store(initialState: .init())

        var notificationCount = 0
        let cancellable = parent.child?.objectWillChange.sink { _ in notificationCount += 1 }

        parent.count = 99

        // Not just "did it fire" — a naive wiring fix (e.g. re-subscribing on every
        // reassignment) could easily fire the child's objectWillChange 2+ times for a single
        // parent mutation, which is its own performance bug even though it wouldn't fail an
        // "at least once" check.
        XCTAssertEqual(notificationCount, 1, "child's objectWillChange should fire exactly once per parent mutation")

        cancellable?.cancel()
    }

    func testSuperScopeObservedDoesNotDoubleWireOnRedundantReassignment() {
        let parent = ObservedParentStore()
        let child = ObservingChildReducer.Store(initialState: .init())
        parent.child = child
        // Reassigning the same already-parented child instance again must not add a second,
        // duplicate subscription to the parent's objectWillChange — otherwise a single parent
        // mutation would relay as 2+ notifications to the child.
        parent.child = child

        var notificationCount = 0
        let cancellable = parent.child?.objectWillChange.sink { _ in notificationCount += 1 }

        parent.count = 42

        XCTAssertEqual(notificationCount, 1, "reassigning the same child must not multiply the relay's fan-out")

        cancellable?.cancel()
    }

    func testSuperScopeObservedRelaysMultipleMutationsOneNotificationEach() {
        let parent = ObservedParentStore()
        parent.child = ObservingChildReducer.Store(initialState: .init())

        var notificationCount = 0
        let cancellable = parent.child?.objectWillChange.sink { _ in notificationCount += 1 }

        parent.count = 1
        parent.count = 2
        parent.count = 3

        XCTAssertEqual(notificationCount, 3, "each parent mutation should relay exactly one notification, not more")

        cancellable?.cancel()
    }

    // MARK: - ParentStoreBinding itself (dynamicMemberLookup, Equatable, Hashable)

    func testDynamicMemberLookupReadsThroughToWrappedValue() {
        let store = LegacyParentStore()
        store.count = 7
        let binding = ParentStoreBinding<LegacyParentStore> { store }
        XCTAssertEqual(binding.count, 7)
        XCTAssertEqual(binding.wrappedValue.count, 7)
    }

    func testDefaultValueUsesInjectableDefault() {
        let binding = ParentStoreBinding<LegacyParentStore>.defaultValue
        XCTAssertEqual(binding.wrappedValue.count, LegacyParentStore.defaultValue.count)
    }

    private final class EquatableParentStore: Injectable, ObservableObject, Equatable, Hashable {
        let id: Int
        init(id: Int) { self.id = id }
        static var defaultValue: EquatableParentStore { EquatableParentStore(id: 0) }
        static func == (lhs: EquatableParentStore, rhs: EquatableParentStore) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    func testEquatableComparesThroughWrappedValue() {
        let a = ParentStoreBinding<EquatableParentStore> { EquatableParentStore(id: 1) }
        let b = ParentStoreBinding<EquatableParentStore> { EquatableParentStore(id: 1) }
        let c = ParentStoreBinding<EquatableParentStore> { EquatableParentStore(id: 2) }
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testHashableHashesThroughWrappedValue() {
        let a = ParentStoreBinding<EquatableParentStore> { EquatableParentStore(id: 1) }
        let b = ParentStoreBinding<EquatableParentStore> { EquatableParentStore(id: 1) }
        XCTAssertEqual(a.hashValue, b.hashValue)
    }
}
