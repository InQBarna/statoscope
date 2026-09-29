//
//  ReducerStoreRegistryTests.swift
//  Statoscope
//
//  Covers ReducerStoreRegistry (Sources/Statoscope/SwiftUI/AutoConnectedView.swift) — previously
//  entirely uncovered. Unlike the View structs in that same file (ReducerStoreView,
//  AutoConnectedView, ReducerObservedView, ReducerRegistryCapture, ReducerEnvironmentCapture,
//  etc.), ReducerStoreRegistry is a plain ObservableObject holding a per-type weak-reference
//  stack — no SwiftUI rendering/environment resolution involved, so it's directly testable.
//  The View structs themselves are NOT covered here: exercising their `body` requires actually
//  rendering into a SwiftUI host (e.g. via ViewInspector or a UIHostingController snapshot),
//  which this package has no dependency on today — see UNCOVERED_BY_UNIT_TESTS.md.
//

import Foundation
import XCTest
@testable import Statoscope

private final class RegistryTestStoreA {}
private final class RegistryTestStoreB {}

final class ReducerStoreRegistryTests: XCTestCase {

    func testCurrentReturnsNilWhenNothingRegistered() {
        let registry = ReducerStoreRegistry()
        XCTAssertNil(registry.current(RegistryTestStoreA.self))
    }

    func testPushThenCurrentReturnsTheRegisteredStore() {
        let registry = ReducerStoreRegistry()
        let store = RegistryTestStoreA()
        registry.push(store)
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === store)
    }

    func testCurrentIsKeyedByConcreteType() {
        let registry = ReducerStoreRegistry()
        let storeA = RegistryTestStoreA()
        registry.push(storeA)
        XCTAssertNil(registry.current(RegistryTestStoreB.self), "different concrete type must not resolve")
    }

    func testPushingTwoInstancesReturnsTheMostRecentlyPushed() {
        let registry = ReducerStoreRegistry()
        let first = RegistryTestStoreA()
        let second = RegistryTestStoreA()
        registry.push(first)
        registry.push(second)
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === second)
    }

    func testRePushingAnAlreadyTopmostStoreIsANoOp() {
        let registry = ReducerStoreRegistry()
        let store = RegistryTestStoreA()
        registry.push(store)
        registry.push(store)
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === store)
    }

    func testRePushingAnOlderStoreMovesItBackToTop() {
        let registry = ReducerStoreRegistry()
        let first = RegistryTestStoreA()
        let second = RegistryTestStoreA()
        registry.push(first)
        registry.push(second)
        registry.push(first)
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === first,
                      "re-pushing an older entry must move it back to the top of its type's stack")
    }

    func testDeallocatedStoreIsSkippedByCurrent() {
        let registry = ReducerStoreRegistry()
        var first: RegistryTestStoreA? = RegistryTestStoreA()
        let second = RegistryTestStoreA()
        registry.push(first!)
        registry.push(second)

        first = nil
        // second is still topmost regardless, but confirm deallocating an older, non-topmost
        // entry doesn't disturb lookups for the type at all.
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === second)
    }

    func testTopmostStoreDeallocatedFallsBackToNextLiveOne() {
        let registry = ReducerStoreRegistry()
        let first = RegistryTestStoreA()
        var second: RegistryTestStoreA? = RegistryTestStoreA()
        registry.push(first)
        registry.push(second!)

        second = nil
        XCTAssertTrue(registry.current(RegistryTestStoreA.self) === first,
                      "current() must skip weakly-nil entries and fall back to the next live one")
    }

    func testPushSchedulesDeferredObjectWillChange() {
        let registry = ReducerStoreRegistry()
        let store = RegistryTestStoreA()
        let expectation = expectation(description: "objectWillChange fires on next run loop turn")
        let cancellable = registry.objectWillChange.sink { _ in expectation.fulfill() }
        registry.push(store)
        wait(for: [expectation], timeout: 1.0)
        cancellable.cancel()
    }
}
