//
//  ReducerInjectedByKeyTests.swift
//  Statoscope
//
//  @ReducerInjectedByKey — the protocol-typed sibling of @ReducerInjected. Mirrors
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

final class SilentAuditLogger: AuditLoggerProtocol, InjectionKeyProviding {
    func log(_ message: String) { }
    static var injectionKey: InjectionKey<AuditLoggerProtocol> { .init(defaultValue: SilentAuditLogger()) }
}

let auditLoggerKey = InjectionKey<AuditLoggerProtocol>(defaultValue: SilentAuditLogger())

@Reducer
struct AuditedCounterByKey {
    struct State {
        var count: Int = 0
        @ReducerInjectedByKey(auditLoggerKey) var logger: AuditLoggerProtocol
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
struct ChildCounterByKey {
    struct State {
        var value: Int = 0
        @ReducerInjectedByKey(auditLoggerKey) var logger: AuditLoggerProtocol
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
struct ParentWithChildByKey {
    struct State {
        @ReducerInjectedByKey(auditLoggerKey) var logger: AuditLoggerProtocol
        @SubState var child: ChildCounterByKey.State?
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
            state.child = ChildCounterByKey.State()
        }
    }
}

// `InjectionKeyProviding` — the key reached through SilentAuditLogger.self instead of a
// separately-named global. See InjectionKeyProviding.swift's own doc.
@Reducer
struct AuditedCounterViaProvider {
    struct State {
        var count: Int = 0
        @ReducerInjectedByKey(SilentAuditLogger.self) var logger: AuditLoggerProtocol
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

final class ReducerInjectedByKeyTests: XCTestCase {

    func testDefaultValueUsedWhenNoInjection() throws {
        // SilentAuditLogger (the key's default) is used — no crash, no visible side effect.
        try AuditedCounterByKey.Store.GIVEN {
            AuditedCounterByKey.Store(initialState: .init())
        }
        .THEN(\.state.count, equals: 0)
        .WHEN(.increment)
        .THEN(\.state.count, equals: 1)
        .runTest()
    }

    func testInjectedProtocolConformanceIsUsedDuringUpdate() throws {
        let logger = CapturingAuditLogger()

        try AuditedCounterByKey.Store.GIVEN {
            AuditedCounterByKey.Store(initialState: .init())
                .injectObject(logger, for: auditLoggerKey)
        }
        .WHEN(.increment)
        .THEN(\.state.count, equals: 1)
        .runTest()

        XCTAssertEqual(logger.messages, ["increment: 0 → 1"])
    }

    func testChildInheritsInjectedLoggerFromParent() throws {
        let logger = CapturingAuditLogger()

        let parentStore = ParentWithChildByKey.Store(initialState: .init())
            .injectObject(logger, for: auditLoggerKey)

        parentStore.send(.openChild)

        guard let childStore = parentStore.children.child else {
            XCTFail("Child store was not created")
            return
        }
        childStore.send(.add(5))

        XCTAssertEqual(childStore.state.value, 5)
        XCTAssertEqual(logger.messages, ["opening child", "child add 5"])
    }

    func testInjectedProtocolConformanceViaInjectionKeyProviding() throws {
        let logger = CapturingAuditLogger()

        try AuditedCounterViaProvider.Store.GIVEN {
            AuditedCounterViaProvider.Store(initialState: .init())
                .injectObject(logger, for: SilentAuditLogger.injectionKey)
        }
        .WHEN(.increment)
        .THEN(\.state.count, equals: 1)
        .runTest()

        XCTAssertEqual(logger.messages, ["increment: 0 → 1"])
    }
}
