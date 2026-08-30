//  Tutorial04b_ReducerInjected.swift
//  Statoscope
//
//  Examples: @ReducerInjected — declarative dependency injection on Reducer.State
//
//  Demonstrates the difference between:
//    - Old: call `try dependencies.resolve()` inside each handler
//    - New: declare `@ReducerInjected var dep: Dep` once on State; access as `state.dep`
//

import Foundation
import StatoscopeTesting
@_spi(Internal) @testable import Statoscope
import XCTest

/// Tutorial: Declarative dependency injection with @ReducerInjected
enum Tutorial04bReducerInjected {

    // MARK: - Shared dependency

    /// A simple audit logger dependency used across the tests.
    /// `defaultValue` is silent so reducers work without any injection in unit tests
    /// that don't care about logging.
    // @extract:begin Injection-Reducer-AuditLogger-01
    struct AuditLogger: Injectable {
        var log: (String) -> Void
        static var defaultValue = AuditLogger(log: { _ in })
    }
    // @extract:end Injection-Reducer-AuditLogger-01

    // MARK: - Single-scope example

    /// Counter that declares its logger dependency on the State struct.
    ///
    /// Compare with Tutorial04_Injection_Reducer, where each handler calls
    /// `try dependencies.resolve()` imperatively.
    // @extract:begin Injection-Reducer-AuditedCounter-01
    @Reducer
    struct AuditedCounter {
        struct State {
            var count: Int = 0
            var lastMessage: String = ""

            /// Dependency declared once on State.
            /// The @Reducer macro generates injection in the Store's state getter.
            @ReducerInjected var logger: AuditLogger
        }

        enum When {
            case increment
            case decrement
            case reset
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment:
                let msg = "increment: \(state.count) → \(state.count + 1)"
                state.logger.log(msg)
                state.lastMessage = msg
                state.count += 1

            case .decrement:
                let msg = "decrement: \(state.count) → \(state.count - 1)"
                state.logger.log(msg)
                state.lastMessage = msg
                state.count -= 1

            case .reset:
                let msg = "reset"
                state.logger.log(msg)
                state.lastMessage = msg
                state.count = 0
            }
        }
    }
    // @extract:end Injection-Reducer-AuditedCounter-01

    // MARK: - Parent-child injection inheritance example

    // @extract:begin Injection-Reducer-ChildParent-01
    @Reducer
    struct ChildCounter {
        struct State {
            var value: Int = 0
            // Child also declares the same dependency — resolved from parent's tree
            @ReducerInjected var logger: AuditLogger
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
            var label: String = ""
            @ReducerInjected var logger: AuditLogger
            @SubState var child: ChildCounter.State?
        }

        enum When {
            case labelChanged(String)
            case openChild
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .labelChanged(let text):
                state.logger.log("label: \(text)")
                state.label = text

            case .openChild:
                state.logger.log("opening child")
                state.child = ChildCounter.State()
            }
        }
    }
    // @extract:end Injection-Reducer-ChildParent-01

    // MARK: - Tests

    final class InjectedTests: XCTestCase {

        // MARK: Default value — no injection required

        // @extract:begin Injection-Reducer-DefaultTest-01
        func testDefaultValueUsedWhenNoInjection() throws {
            // The defaultValue logger is silent; no crash, no side effect
            try AuditedCounter.Store.GIVEN {
                AuditedCounter.Store(initialState: .init())
                // No .injectObject() — uses AuditLogger.defaultValue
            }
            .THEN(\.state.count, equals: 0)
            .WHEN(.increment)
            .THEN(\.state.count, equals: 1)
            .WHEN(.increment)
            .THEN(\.state.count, equals: 2)
            .WHEN(.reset)
            .THEN(\.state.count, equals: 0)
            .runTest()
        }
        // @extract:end Injection-Reducer-DefaultTest-01

        // MARK: Injected value is used during update

        // @extract:begin Injection-Reducer-InjectedTest-01
        func testInjectedLoggerIsCalledOnIncrement() throws {
            var capturedMessages: [String] = []

            try AuditedCounter.Store.GIVEN {
                AuditedCounter.Store(initialState: .init())
                    .injectObject(AuditLogger { capturedMessages.append($0) })
            }
            .WHEN(.increment)
            .THEN(\.state.count, equals: 1)
            .THEN(\.state.lastMessage, equals: "increment: 0 → 1")
            .runTest()

            XCTAssertEqual(capturedMessages, ["increment: 0 → 1"])
        }
        // @extract:end Injection-Reducer-InjectedTest-01

        func testInjectedLoggerCapturesAllEvents() throws {
            var capturedMessages: [String] = []

            try AuditedCounter.Store.GIVEN {
                AuditedCounter.Store(initialState: .init())
                    .injectObject(AuditLogger { capturedMessages.append($0) })
            }
            .WHEN(.increment)
            .WHEN(.increment)
            .WHEN(.decrement)
            .WHEN(.reset)
            .THEN(\.state.count, equals: 0)
            .runTest()

            XCTAssertEqual(capturedMessages, [
                "increment: 0 → 1",
                "increment: 1 → 2",
                "decrement: 2 → 1",
                "reset"
            ])
        }

        // MARK: Injection tree — child inherits dependency from parent

        // @extract:begin Injection-Reducer-ChildInheritTest-01
        func testChildInheritsInjectedLoggerFromParent() throws {
            var capturedMessages: [String] = []

            let parentStore = ParentWithChild.Store(initialState: .init())
                .injectObject(AuditLogger { capturedMessages.append($0) })

            parentStore.send(.labelChanged("hello"))
            parentStore.send(.openChild)

            // Retrieve child store through the injection tree
            guard let childStore = parentStore.children.child else {
                XCTFail("Child store was not created")
                return
            }

            childStore.send(.add(5))
            childStore.send(.add(3))

            XCTAssertEqual(parentStore.state.label, "hello")
            XCTAssertEqual(childStore.state.value, 8)

            // Both parent and child log through the same injected logger
            XCTAssertEqual(capturedMessages, [
                "label: hello",
                "opening child",
                "child add 5",
                "child add 3"
            ])
        }
        // @extract:end Injection-Reducer-ChildInheritTest-01

        // MARK: Injection replacement for tests

        func testInjectionCanBeReplacedBetweenTestScenarios() throws {
            // Scenario A — first logger
            var logA: [String] = []
            let storeA = AuditedCounter.Store(initialState: .init())
                .injectObject(AuditLogger { logA.append($0) })
            storeA.send(.increment)
            XCTAssertEqual(logA, ["increment: 0 → 1"])

            // Scenario B — independent store, different logger
            var logB: [String] = []
            let storeB = AuditedCounter.Store(initialState: .init())
                .injectObject(AuditLogger { logB.append($0) })
            storeB.send(.increment)
            storeB.send(.increment)
            XCTAssertEqual(logB, ["increment: 0 → 1", "increment: 1 → 2"])

            // Neither logger bled into the other store
            XCTAssertEqual(logA.count, 1)
        }

        // MARK: GIVEN/WHEN/THEN with @ReducerInjected

        func testFluentAPIWorksWithReducerInjected() throws {
            var capturedMessages: [String] = []

            try AuditedCounter.Store.GIVEN {
                AuditedCounter.Store(initialState: .init())
                    .injectObject(AuditLogger { capturedMessages.append($0) })
            }
            .THEN(\.state.count, equals: 0)
            .WHEN(.increment)
            .THEN(\.state.count, equals: 1)
            .THEN(\.state.lastMessage, equals: "increment: 0 → 1")
            .WHEN(.decrement)
            .THEN(\.state.count, equals: 0)
            .THEN(\.state.lastMessage, equals: "decrement: 1 → 0")
            .WHEN(.reset)
            .THEN(\.state.count, equals: 0)
            .THEN(\.state.lastMessage, equals: "reset")
            .runTest()

            XCTAssertEqual(capturedMessages, [
                "increment: 0 → 1",
                "decrement: 1 → 0",
                "reset"
            ])
        }
    }
}
