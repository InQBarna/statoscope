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
    @Published public private(set) var state: R.State

    /// Expose When type from reducer
    public typealias When = R.When

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
    /// This method is called by the framework when events are sent via `send(_:)`.
    /// It creates a mutable copy of state, wraps the injection tree in a dependencies object,
    /// passes everything to the reducer's static update method, and assigns the updated state
    /// back to trigger @Published.
    ///
    /// - Parameter when: The event to process
    @_spi(Internal)
    public func update(_ when: When) throws {
        var mutableState = state
        let dependencies = ReducerDependenciesImpl(node: self as? InjectionTreeNode)
        try R.update(when, state: &mutableState, effectsState: &effectsState, dependencies: dependencies)
        state = mutableState
    }
}
