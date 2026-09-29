//
//  SwiftUIBindingsTests.swift
//  Statoscope
//
//  Covers Sources/Statoscope/SwiftUI/SwiftUIBindings.swift — previously entirely uncovered.
//  None of this is SwiftUI View-rendering code; every symbol here just constructs a plain
//  SwiftUI.Binding from get/set closures, which is exercised the same way StoreBindTests.swift
//  already exercises the separate dismissWhen-based bind() helpers: by reading/writing
//  `.wrappedValue` directly, no view host needed.
//

import Foundation
import XCTest
import SwiftUI
@testable import Statoscope

private final class BindableScope: Statostore, ObservableObject {
    typealias When = Void
    var value: Int = 0
    var optionalValue: Int?
    func update(_ when: Void) throws { }
}

final class SwiftUIBindingsTests: XCTestCase {

    // MARK: - Free function bind(viewShows:_:_:) — keyPath overload

    func testFreeBindKeyPathReadsCurrentValue() {
        struct Shown: Sendable { let count: Int }
        let binding = Statoscope.bind(viewShows: Shown(count: 5), \.count) { _ in }
        XCTAssertEqual(binding.wrappedValue, 5)
    }

    func testFreeBindKeyPathSetCallsWhenClosure() {
        struct Shown: Sendable { let count: Int }
        var received: Int?
        let binding = Statoscope.bind(viewShows: Shown(count: 5), \.count) { newValue in
            received = newValue
            return newValue
        }
        binding.wrappedValue = 9
        XCTAssertEqual(received, 9)
    }

    // MARK: - Free function bind(viewShows:_:) — whole-object overload

    func testFreeBindWholeObjectReadsCurrentValue() {
        struct Shown: Sendable, Equatable { let count: Int }
        let shown = Shown(count: 3)
        let binding = Statoscope.bind(viewShows: shown) { _ in }
        XCTAssertEqual(binding.wrappedValue, shown)
    }

    func testFreeBindWholeObjectSetCallsWhenClosure() {
        struct Shown: Sendable, Equatable { let count: Int }
        var received: Shown?
        let binding = Statoscope.bind(viewShows: Shown(count: 3)) { newValue in
            received = newValue
            return newValue
        }
        let newShown = Shown(count: 8)
        binding.wrappedValue = newShown
        XCTAssertEqual(received, newShown)
    }

    // MARK: - StoreProtocol.bindNotNilBool

    func testBindNotNilBoolReadsFalseWhenNil() {
        let scope = BindableScope()
        let binding = scope.bindNotNilBool(\.optionalValue)
        XCTAssertFalse(binding.wrappedValue)
    }

    func testBindNotNilBoolReadsTrueWhenSet() {
        let scope = BindableScope()
        scope.optionalValue = 1
        let binding = scope.bindNotNilBool(\.optionalValue)
        XCTAssertTrue(binding.wrappedValue)
    }

    func testBindNotNilBoolWithoutWhenIgnoresSet() {
        let scope = BindableScope()
        scope.optionalValue = 1
        let binding = scope.bindNotNilBool(\.optionalValue)
        binding.wrappedValue = false
        // No `when` closure was provided — set is a no-op, state is untouched.
        XCTAssertEqual(scope.optionalValue, 1)
    }

    func testBindNotNilBoolWithWhenSendsOnSet() {
        let scope = BindableScope()
        var sentValues: [Bool] = []
        let binding = scope.bindNotNilBool(\.optionalValue) { newBool in
            sentValues.append(newBool)
        }
        binding.wrappedValue = false
        XCTAssertEqual(sentValues, [false])
    }

    // MARK: - StoreProtocol.bindIsPresented

    func testBindIsPresentedReadsFalseWhenNil() {
        let scope = BindableScope()
        let binding = scope.bindIsPresented(\.optionalValue)
        XCTAssertFalse(binding.wrappedValue)
    }

    func testBindIsPresentedReadsTrueWhenSet() {
        let scope = BindableScope()
        scope.optionalValue = 42
        let binding = scope.bindIsPresented(\.optionalValue)
        XCTAssertTrue(binding.wrappedValue)
    }

    func testBindIsPresentedWithoutWhenIgnoresSet() {
        let scope = BindableScope()
        scope.optionalValue = 42
        let binding = scope.bindIsPresented(\.optionalValue)
        binding.wrappedValue = false
        XCTAssertEqual(scope.optionalValue, 42)
    }

    func testBindIsPresentedSettingFalsePassesNilToWhen() {
        let scope = BindableScope()
        scope.optionalValue = 42
        var receivedValues: [Int?] = []
        let binding = scope.bindIsPresented(\.optionalValue) { value in
            receivedValues.append(value)
        }
        binding.wrappedValue = false
        XCTAssertEqual(receivedValues, [Optional<Int>.none])
    }

    func testBindIsPresentedSettingTruePassesCurrentValueToWhen() {
        let scope = BindableScope()
        scope.optionalValue = 42
        var receivedValues: [Int?] = []
        let binding = scope.bindIsPresented(\.optionalValue) { value in
            receivedValues.append(value)
        }
        binding.wrappedValue = true
        XCTAssertEqual(receivedValues, [42])
    }

    // MARK: - StoreProtocol.bind(constant:_:)

    func testBindConstantAlwaysReadsTheSameValue() {
        let scope = BindableScope()
        let binding = scope.bind(constant: "fixed") { _ in }
        XCTAssertEqual(binding.wrappedValue, "fixed")
    }

    func testBindConstantSetCallsWhenClosure() {
        let scope = BindableScope()
        var received: String?
        let binding = scope.bind(constant: "fixed") { newValue in
            received = newValue
        }
        binding.wrappedValue = "changed"
        XCTAssertEqual(received, "changed")
    }

    // MARK: - StoreProtocol.bind(_ keyPath:_:) — reads through _scopeImpl

    func testBindKeyPathReadsLiveScopeState() {
        let scope = BindableScope()
        scope.value = 11
        let binding = scope.bind(\.value) { _ in }
        XCTAssertEqual(binding.wrappedValue, 11)
    }

    func testBindKeyPathSetCallsWhenClosure() {
        let scope = BindableScope()
        var received: Int?
        let binding = scope.bind(\.value) { newValue in
            received = newValue
        }
        binding.wrappedValue = 77
        XCTAssertEqual(received, 77)
    }

    // MARK: - StoreProtocol.weakBind

    func testWeakBindReadsLiveScopeState() {
        let scope = BindableScope()
        scope.value = 3
        let binding = scope.weakBind(\.value, { _ in }, defaultValue: -1)
        XCTAssertEqual(binding.wrappedValue, 3)
    }

    func testWeakBindReadsDefaultValueWhenScopeDeallocated() {
        var scope: BindableScope? = BindableScope()
        scope?.value = 3
        let binding = scope!.weakBind(\.value, { _ in }, defaultValue: -1)
        scope = nil
        XCTAssertEqual(binding.wrappedValue, -1, "weak self is gone — falls back to defaultValue")
    }

    func testWeakBindSetCallsWhenClosure() {
        let scope = BindableScope()
        var received: Int?
        let binding = scope.weakBind(\.value, { newValue in received = newValue }, defaultValue: -1)
        binding.wrappedValue = 5
        XCTAssertEqual(received, 5)
    }

    // MARK: - StoreProtocol.bind(_ getter:_:) — closure-based overload

    func testBindGetterClosureReadsCurrentValueAtCallTime() {
        let scope = BindableScope()
        scope.value = 1
        let binding = scope.bind({ $0.value * 2 }, { _ in })
        XCTAssertEqual(binding.wrappedValue, 2)
    }

    func testBindGetterClosureReflectsLiveChangesAfterCreation() {
        let scope = BindableScope()
        scope.value = 1
        let binding = scope.bind({ $0.value * 2 }, { _ in })
        scope.value = 10
        XCTAssertEqual(binding.wrappedValue, 20, "getter re-reads self, not a snapshot taken at bind() time")
    }

    func testBindGetterClosureFallsBackToCapturedValueWhenScopeDeallocated() {
        var scope: BindableScope? = BindableScope()
        scope?.value = 4
        let binding = scope!.bind({ $0.value * 2 }, { _ in })
        scope = nil
        XCTAssertEqual(binding.wrappedValue, 8, "weak self is gone — falls back to currentValue captured at bind() time")
    }

    func testBindGetterClosureSetCallsWhenClosure() {
        let scope = BindableScope()
        var received: Int?
        let binding = scope.bind({ $0.value }, { newValue in received = newValue })
        binding.wrappedValue = 6
        XCTAssertEqual(received, 6)
    }

    // MARK: - ?? operator for Binding<T?>

    func testNilCoalescingBindingReadsWrappedValueWhenPresent() {
        var backing: Int? = 5
        let optionalBinding = Binding<Int?>(get: { backing }, set: { backing = $0 })
        let coalesced = optionalBinding ?? -1
        XCTAssertEqual(coalesced.wrappedValue, 5)
    }

    func testNilCoalescingBindingReadsDefaultWhenNil() {
        var backing: Int?
        let optionalBinding = Binding<Int?>(get: { backing }, set: { backing = $0 })
        let coalesced = optionalBinding ?? -1
        XCTAssertEqual(coalesced.wrappedValue, -1)
    }

    func testNilCoalescingBindingSetWritesThroughToUnderlyingBinding() {
        var backing: Int?
        let optionalBinding = Binding<Int?>(get: { backing }, set: { backing = $0 })
        let coalesced = optionalBinding ?? -1
        coalesced.wrappedValue = 42
        XCTAssertEqual(backing, 42)
    }
}
