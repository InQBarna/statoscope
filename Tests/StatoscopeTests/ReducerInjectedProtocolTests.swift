//
//  ReducerInjectedProtocolTests.swift
//  Statoscope
//
//  @ReducerInjected with a genuine Swift protocol (not just an Injectable value type). Mirrors
//  Tutorial04b_ReducerInjected.swift's own tests, but with a real protocol (AuditLoggerProtocol)
//  instead of a struct-of-closures, proving the motivating scenario end to end: declarative,
//  State-ambient injection for a genuine Swift protocol.
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

protocol AuditLoggerProtocol {
    func log(_ message: String)
}

final class CapturingAuditLogger: AuditLoggerProtocol {
    private(set) var messages: [String] = []
    func log(_ message: String) { messages.append(message) }
}

// SilentAuditLogger conforms to Injectable itself — declares its default with a protocol return
// type instead of Self, discoverable through the type's own name, not a separately-named global.
final class SilentAuditLogger: AuditLoggerProtocol, Injectable {
    func log(_ message: String) { }
    static var defaultValue: AuditLoggerProtocol { SilentAuditLogger() }
}

@Reducer
struct AuditedCounter {
    struct State {
        var count: Int = 0
        @ReducerInjected(SilentAuditLogger.self) var logger: AuditLoggerProtocol
    }

    enum When {
        case increment
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .increment:
            state.logger.log("increment: \(state.count) → \(state.count + 1)")
            state.count += 1
        }
    }
}

@Reducer
struct ChildCounter {
    struct State {
        var value: Int = 0
        @ReducerInjected(SilentAuditLogger.self) var logger: AuditLoggerProtocol
    }

    enum When {
        case add(Int)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .add(let n):
            state.logger.log("child add \(n)")
            state.value += n
        }
    }
}

@Reducer
struct ParentWithChild {
    struct State {
        @ReducerInjected(SilentAuditLogger.self) var logger: AuditLoggerProtocol
        @SubState var child: ChildCounter.State?
    }

    enum When {
        case openChild
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .openChild:
            state.logger.log("opening child")
            state.child = ChildCounter.State()
        }
    }
}

final class ReducerInjectedProtocolTests: XCTestCase {

    func testDefaultValueUsedWhenNoInjection() throws {
        // SilentAuditLogger's own default is used — no crash, no visible side effect.
        try AuditedCounter.Store.GIVEN {
            AuditedCounter.Store(initialState: .init())
        }
        .THEN(\.state.count, equals: 0)
        .WHEN(.increment)
        .THEN(\.state.count, equals: 1)
        .runTest()
    }

    func testInjectedProtocolConformanceIsUsedDuringUpdate() throws {
        let logger = CapturingAuditLogger()

        try AuditedCounter.Store.GIVEN {
            AuditedCounter.Store(initialState: .init())
                .injectObject(logger, for: SilentAuditLogger.self)
        }
        .WHEN(.increment)
        .THEN(\.state.count, equals: 1)
        .runTest()

        XCTAssertEqual(logger.messages, ["increment: 0 → 1"])
    }

    func testChildInheritsInjectedLoggerFromParent() throws {
        let logger = CapturingAuditLogger()

        let parentStore = ParentWithChild.Store(initialState: .init())
            .injectObject(logger, for: SilentAuditLogger.self)

        parentStore.send(.openChild)

        guard let childStore = parentStore.children.child else {
            XCTFail("Child store was not created")
            return
        }
        childStore.send(.add(5))

        XCTAssertEqual(childStore.state.value, 5)
        XCTAssertEqual(logger.messages, ["opening child", "child add 5"])
    }
}
