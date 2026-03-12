//
//  ReducerTests.swift
//  Statoscope
//
//  Created by Claude Code on 26/2/26.
//

import XCTest
import Combine
@_spi(Internal) @testable import Statoscope

// MARK: - Test Reducers (File Scope)

enum Counter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
            var name: String = ""
        }
        
        enum When {
            case increment
            case decrement
            case setName(String)
            case reset
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
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
}

enum AsyncCounter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
            var isLoading: Bool = false
        }
        
        enum When {
            case startIncrement
            case incrementCompleted
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
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
}

enum ErrorThrowing {
    @Reducer
    struct Reducer {
        struct State {
            var counter: Int = 0
        }
        
        struct ReducerError: Error {}
        
        enum When {
            case shouldFail
            case shouldSucceed
        }
        
        static func update(_ when: When, state: inout State, effectsState: inout EffectsState<When>, dependencies: ReducerDependencies) throws {
            switch when {
            case .shouldFail:
                throw ReducerError()
            case .shouldSucceed:
                state.counter += 1
            }
        }
    }
}

struct Logger: Injectable {
    static var defaultValue: Logger { Logger() }

    var logs: [String] = []
    mutating func log(_ message: String) {
        logs.append(message)
    }
}

enum LoggingCounter {
    @Reducer
    struct Reducer {
        struct State {
            var count: Int = 0
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
                // Resolve logger from dependencies
                var logger: Logger = try dependencies.resolve()
                logger.log("log message")
                state.count += 1
            }
        }
    }
}

enum ParentChild {
    // Parent-Child examples now use @Reducer macro with automatic child Store creation!
    @Reducer
    struct ParentReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            var count: Int = 0
            @SubState var child: ChildReducer.State?
        }
        
        enum When {
            case increment
            case createChild
            case updateChild
        }
        
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .increment:
                state.count += 1
                
            case .createChild:
                // ✅ Clean! No manual parent binding
                var childState = ChildReducer.State()
                childState.value = 0
                state.child = childState
                
            case .updateChild:
                state.child?.value = 42
            }
        }
    }
    
    @Reducer
    struct ChildReducer {
        struct State: Injectable {
            static var defaultValue: State { State() }
            @SuperState var parent: ParentReducer.State
            var value: Int = 0
        }
        
        enum When {
            case syncWithParent
        }
        
        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
            switch when {
            case .syncWithParent:
                // ✅ Parent automatically wired!
                state.value = state.parent.count * 2
            }
        }
    }
}

// MARK: - Test Cases

/// Tests for Reducer pattern with @Reducer macro
final class ReducerTests: XCTestCase {

    // MARK: - Basic Reducer Tests

    func testBasicReducerFunctionality() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

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
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        var publishCount = 0
        let cancellable = store.objectWillChange.sink { _ in
            publishCount += 1
        }

        // Increment triggers objectWillChange
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, 0)

        let currentCount = publishCount
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, currentCount)

        _ = cancellable
    }

    func testStateSnapshot() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        store.send(.increment)
        store.send(.setName("Test"))

        // Take snapshot
        let snapshot = store.state
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.name, "Test")

        // Modify state
        store.send(.increment)
        XCTAssertEqual(store.state.count, 2)

        // Snapshot remains unchanged
        XCTAssertEqual(snapshot.count, 1)
        XCTAssertEqual(snapshot.name, "Test")
    }

    // MARK: - Effect Tests

    func testReducerWithEffects() async throws {
        scopeEffectsDisabledInUnitTests = false

        let store = AsyncCounter.Reducer.Store(initialState: AsyncCounter.Reducer.State())

        XCTAssertEqual(store.state.count, 0)
        XCTAssertEqual(store.state.isLoading, false)

        store.send(.startIncrement)

        XCTAssertEqual(store.state.isLoading, true)
        XCTAssertEqual(store.state.count, 0)

        // Wait for effect to complete
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

        XCTAssertEqual(store.state.isLoading, false)
        XCTAssertEqual(store.state.count, 1)

        scopeEffectsDisabledInUnitTests = true
    }

    // MARK: - Error Handling

    func testErrorHandling() {
        let store = ErrorThrowing.Reducer.Store(initialState: ErrorThrowing.Reducer.State())

        XCTAssertEqual(store.state.counter, 0)

        // Error in reducer is caught by framework
        store.send(.shouldFail)
        // State unchanged on error
        XCTAssertEqual(store.state.counter, 0)

        // Success still works
        store.send(.shouldSucceed)
        XCTAssertEqual(store.state.counter, 1)
    }

    // MARK: - Dependency Injection

    func testDependencyInjection() {
        let store = LoggingCounter.Reducer.Store(initialState: LoggingCounter.Reducer.State())

        // Inject logger into store
        let logger = Logger()
        store.injectObject(logger)

        XCTAssertEqual(store.state.count, 0)

        // Send event - reducer will resolve logger
        store.send(.increment)

        XCTAssertEqual(store.state.count, 1)
        // Logger was successfully resolved (no errors thrown)
    }

    // MARK: - Parent-Child with SuperState/SubState

    func testSuperAndSubState() {
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        XCTAssertEqual(parent.state.count, 0)
        XCTAssertNil(parent.state.child)

        // Create child
        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        XCTAssertEqual(parent.state.child?.value, 0)

        // Get child store from @Subscope property
        guard let childStore = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Child can sync with parent state via @SuperState
        childStore.send(.syncWithParent)
        XCTAssertEqual(childStore.state.value, 0)  // parent.count = 0, so value = 0 * 2

        // Parent increments
        parent.send(.increment)
        XCTAssertEqual(parent.state.count, 1)

        // Child syncs with parent - SuperStateBinding reflects new parent state!
        childStore.send(.syncWithParent)
        XCTAssertEqual(childStore.state.value, 2)  // parent.count = 1, so value = 1 * 2

        // Parent can update child via state
        parent.send(.updateChild)
        XCTAssertEqual(parent.state.child?.value, 42)
    }

    func testSuperStateReadOnly() {
        // This test demonstrates that SuperStateBinding only exposes state, not send()
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        guard let childStore = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // The following code would NOT compile if uncommented in the reducer:
        //
        // state.parent.send(.increment)  // ❌ Error: SuperStateBinding has no member 'send'
        //
        // This is a compile-time safety feature!

        // Child can only READ parent state
        XCTAssertEqual(childStore.state.parent.count, 0)
    }

    func testSubStateAccess() {
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        XCTAssertNotNil(parent.state.child)
        XCTAssertEqual(parent.state.child?.value, 0)

        // Parent can modify child state via state mutation in update()
        parent.send(.updateChild)
        XCTAssertEqual(parent.state.child?.value, 42)
    }

    func testChildStateReflectsCurrentState() {
        // Demonstrate that parent state always reflects live child store state
        let parent = ParentChild.ParentReducer.Store(initialState: ParentChild.ParentReducer.State())

        parent.send(.createChild)

        guard let childStore = parent._child else {
            XCTFail("Child store not found")
            return
        }

        // Initial state
        XCTAssertEqual(childStore.state.parent.count, 0)

        // Parent state changes
        parent.send(.increment)

        // Child's SuperStateBinding immediately reflects the change
        XCTAssertEqual(childStore.state.parent.count, 1)
    }

    // MARK: - Injectable Conformance

    func testInjectableConformance() {
        // Verify that State types have Injectable conformance
        let defaultCounter = Counter.Reducer.State()
        XCTAssertEqual(defaultCounter.count, 0)
        XCTAssertEqual(defaultCounter.name, "")

        let defaultParent = ParentChild.ParentReducer.State()
        XCTAssertEqual(defaultParent.count, 0)
        XCTAssertNil(defaultParent.child)
    }

    // MARK: - ObservableObject Conformance

    func testObservableObjectConformance() {
        let store = Counter.Reducer.Store(initialState: Counter.Reducer.State())

        var publishCount = 0
        let cancellable = store.objectWillChange.sink { _ in
            publishCount += 1
        }

        // Increment triggers objectWillChange
        store.send(.increment)
        XCTAssertGreaterThan(publishCount, 0)

        _ = cancellable
    }
}
