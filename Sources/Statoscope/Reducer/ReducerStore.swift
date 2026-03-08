//
//  ReducerStore.swift
//  Statoscope
//
//  Created by Claude Code on 26/2/26.
//

import Foundation
import Combine

/// A generic Statostore that wraps a Reducer for single-state management
///
/// ReducerStore bridges the Reducer pattern with the existing Statostore infrastructure,
/// providing a simpler API while maintaining compatibility with effects, injection, and subscopes.
///
/// ## Example:
/// ```swift
/// struct CounterState {
///     var count: Int = 0
/// }
///
/// struct CounterReducer: Reducer {
///     enum When {
///         case increment
///     }
///
///     func update(_ when: When, state: inout CounterState, effectsState: EffectsState<When>) throws {
///         state.count += 1
///     }
/// }
///
/// // Create store
/// let store = ReducerStore<CounterReducer>(initialState: CounterState())
///
/// // Use in SwiftUI
/// struct CounterView: View {
///     @ObservedObject var store: ReducerStore<CounterReducer>
///
///     var body: some View {
///         VStack {
///             Text("Count: \(store.state.count)")
///             Button("Increment") {
///                 store.send(.increment)
///             }
///         }
///     }
/// }
/// ```
///
/// ## Benefits:
/// - **Centralized State**: Single @Published state property
/// - **Simple API**: No scattered @Published properties
/// - **Easy Snapshots**: `let snapshot = store.state`
/// - **Compatible**: Works with existing effects, injection, and testing infrastructure
/// - **Type-Safe**: Compiler-enforced reducer conformance
public final class ReducerStore<R: Reducer>: Statostore, ObservableObject {

    /// The single published state managed by this store
    ///
    /// Note: Setter is internal to allow SubStateBinding to update child state
    @Published public internal(set) var state: R.State

    /// Expose When type from reducer
    public typealias When = R.When

    /// Strong references to child Stores created by wireChildren.
    /// Keyed by @SubState property name (e.g. "child" for `@SubState var child: ChildState?`).
    private var _childStores: [String: any ObservableObject] = [:]

    /// Initialize a reducer store with initial state
    ///
    /// The reducer type is inferred from the generic parameter.
    /// Since reducers are stateless (static methods only), no reducer instance is needed.
    ///
    /// - Parameter initialState: The initial state value
    public init(initialState: R.State) {
        self.state = initialState
    }

    /// Update implementation that delegates to the reducer's static method
    ///
    /// After calling the reducer's `update`, invokes `R.wireChildren` to create child Stores
    /// for any pending SubStateBinding properties (set via `state.child = ChildState()`).
    ///
    /// - Parameter when: The event to process
    @_spi(Internal)
    public func update(_ when: When) throws {
        var mutableState = state
        let dependencies = ReducerDependenciesImpl(node: self, parentStore: self)
        try R.update(
            when,
            state: &mutableState,
            effectsState: &effectsState,
            dependencies: dependencies
        )
        R.wireChildren(state: &mutableState, childStores: &_childStores)
        state = mutableState
    }

}
