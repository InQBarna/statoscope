//
//  ReducerTests.swift
//  Statoscope
//
//  Created by Claude Code on 26/2/26.
//

import XCTest
import Combine
@testable import Statoscope

/// Tests for Reducer pattern and ReducerStore
final class ReducerTests: XCTestCase {

    // MARK: - Counter Example

    struct CounterState {
        var count: Int = 0
        var name: String = ""
    }

    struct CounterReducer: Reducer {
        enum When {
            case increment
            case decrement
            case setName(String)
            case reset
        }

        static func update(_ when: When, state: inout CounterState, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .increment:
                state.count += 1

            case .decrement:
                state.count = max(0, state.count - 1)

            case .setName(let name):
                state.name = name

            case .reset:
                state.count = 0
                state.name = ""
            }
        }
    }

    func testBasicReducerFunctionality() {
        let store = ReducerStore<CounterReducer>(initialState: CounterState())

        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.name, "")

        store.send(.increment)
        XCTAssertEqual(store.state.count, 1)

        store.send(.increment)
        XCTAssertEqual(store.state.count, 2)

        store.send(.setName("Test"))
        XCTAssertEqual(store.state.name, "Test")

        store.send(.decrement)
        XCTAssertEqual(store.state.count, 1)

        store.send(.reset)
        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.name, "")
    }

    func testPublishedUpdates() {
        let store = ReducerStore<CounterReducer>(initialState: CounterState())

        var publishCount = 0
        let cancellable = store.$state.sink { _ in
            publishCount += 1
        }

        // Initial value
        XCTAssertEqual(publishCount, 1)

        // Increment triggers publish
        store.send(.increment)
        XCTAssertEqual(publishCount, 2)

        // Another increment
        store.send(.increment)
        XCTAssertEqual(publishCount, 3)

        _ = cancellable
    }

    func testStateSnapshot() {
        let store = ReducerStore<CounterReducer>(initialState: CounterState())

        store.send(.increment)
        store.send(.setName("Test"))

        // Take snapshot
        let snapshot = store.state
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.name, "Test")

        // Modify state
        store.send(.increment)
        XCTAssertEqual(store.state.count, 2)

        // Restore from snapshot (direct assignment works because @Published setter is public)
        // Note: For true immutability, state setter could be private(set)
        // For now, snapshot is read-only usage pattern
    }

    // MARK: - Effect Example

    struct AsyncCounterState {
        var count: Int = 0
        var isLoading: Bool = false
    }

    struct AsyncCounterReducer: Reducer {
        enum When {
            case startIncrement
            case incrementCompleted
        }

        static func update(_ when: When, state: inout AsyncCounterState, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .startIncrement:
                state.isLoading = true
                effectsState.enqueue(AnyEffect {
                    try await Task.sleep(nanoseconds: 1_000_000)
                    return .incrementCompleted
                })

            case .incrementCompleted:
                state.isLoading = false
                state.count += 1
            }
        }
    }

    func testReducerWithEffects() async throws {
        
        scopeEffectsDisabledInUnitTests = false

        let store = ReducerStore<AsyncCounterReducer>(initialState: AsyncCounterState())

        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.isLoading, false)

        store.send(.startIncrement)

        XCTAssertEqual(store.state.isLoading, true)
        XCTAssertEqual(store.state.count, 0)

        // Wait for effect to complete (need longer wait for effect processing)
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        XCTAssertEqual(store.state.isLoading, false)
        XCTAssertEqual(store.state.count, 1)
        
        scopeEffectsDisabledInUnitTests = true
    }

    // MARK: - Error Handling

    struct ErrorThrowingReducer: Reducer {
        enum When {
            case shouldFail
            case shouldSucceed
        }

        struct ReducerError: Error {}

        static func update(_ when: When, state: inout Int, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .shouldFail:
                throw ReducerError()
            case .shouldSucceed:
                state += 1
            }
        }
    }

    func testErrorHandling() {
        let store = ReducerStore<ErrorThrowingReducer>(initialState: 0)

        XCTAssertEqual(store.state, 0)

        // Error in reducer is caught by framework
        store.send(.shouldFail)
        // State unchanged on error
        XCTAssertEqual(store.state, 0)

        // Success still works
        store.send(.shouldSucceed)
        XCTAssertEqual(store.state, 1)
    }

    // MARK: - Dependency Injection Example

    struct Logger: Injectable {
        static var defaultValue: Logger { Logger() }

        var logs: [String] = []
        mutating func log(_ message: String) {
            logs.append(message)
        }
    }

    struct LoggingCounterState {
        var count: Int = 0
    }

    struct LoggingCounterReducer: Reducer {
        enum When {
            case increment
        }

        static func update(
            _ when: When,
            state: inout LoggingCounterState,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment:
                // Resolve logger from dependencies
                var logger: Logger = try dependencies.resolve()
                logger.log("log message")
                state.count += 1
            }
        }
    }

    func testDependencyInjection() {
        let store = ReducerStore<LoggingCounterReducer>(initialState: LoggingCounterState())

        // Inject logger into store
        let logger = Logger()
        store.injectObject(logger)

        XCTAssertEqual(store.state.count, 0)

        // Send event - reducer will resolve logger
        store.send(.increment)

        XCTAssertEqual(store.state.count, 1)
        // Logger was successfully resolved (no errors thrown)
    }
}
