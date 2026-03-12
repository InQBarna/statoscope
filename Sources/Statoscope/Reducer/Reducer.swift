//
//  Reducer.swift
//  Statoscope
//
//  Created by Claude Code on 26/2/26.
//

import Foundation

/// A Reducer defines pure update logic for a single state struct
///
/// Reducers provide a simpler, more constrained alternative to Statostore for cases
/// where you want centralized state management with a single state struct.
///
/// ## Example:
/// ```swift
/// struct CounterState {
///     var count: Int = 0
///     var isLoading: Bool = false
/// }
///
/// struct CounterReducer: Reducer {
///     enum When {
///         case increment
///         case loadData
///         case dataLoaded(Result<Data, Error>)
///     }
///
///     static func update(
///         _ when: When,
///         state: inout CounterState,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         switch when {
///         case .increment:
///             state.count += 1
///
///         case .loadData:
///             state.isLoading = true
///             effectsState.enqueue(
///                 FetchDataEffect()
///                     .mapToResult()
///                     .map(When.dataLoaded)
///             )
///
///         case .dataLoaded(let result):
///             state.isLoading = false
///             // Handle result...
///         }
///     }
/// }
///
/// // Use with ReducerStore:
/// let store = ReducerStore<CounterReducer>(initialState: CounterState())
/// ```
public protocol Reducer {
    /// The event type for this reducer
    associatedtype When

    /// The state type for this reducer
    ///
    /// State can contain:
    /// - `SuperStateBinding<ParentState>` for parent access (like @Superscope)
    /// - `ChildState?` for child management (use `@SubState` annotation)
    associatedtype State

    /// Pure update logic that mutates state based on events
    ///
    /// This static method receives:
    /// - `when`: The event to process
    /// - `state`: Mutable state to update (inout parameter)
    /// - `effectsState`: Mutable effects state for enqueueing/cancelling effects (inout parameter)
    /// - `dependencies`: Access to the injection tree for resolving dependencies
    ///
    /// ## Guidelines:
    /// - Mutate state directly through the inout parameter
    /// - Enqueue effects via `effectsState.enqueue(_:)`
    /// - Cancel effects via `effectsState.cancelEffect(_:)`
    /// - Resolve dependencies via `dependencies.resolve()`
    /// - Access parent via `state.parent` (SuperStateBinding)
    /// - Create children by assigning `state.child = ChildReducer.State()`
    /// - Keep logic pure and deterministic (no side effects except effects enqueueing)
    /// - Being static emphasizes that reducers are stateless, pure functions
    ///
    /// - Parameters:
    ///   - when: The event to process
    ///   - state: The mutable state (inout)
    ///   - effectsState: The mutable effects state for managing async operations (inout)
    ///   - dependencies: Access to injected dependencies
    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws

    /// Event to dispatch immediately after this reducer's Store is wired as a child scope.
    ///
    /// Return a `When` event to automatically trigger it once, right after the child store
    /// is connected to the scope hierarchy (i.e. after `parentNode` is set via `@Subscope`).
    ///
    /// ## Example
    /// ```swift
    /// @Reducer
    /// struct ProfileReducer {
    ///     enum When {
    ///         case onAppear   // triggered automatically on creation
    ///         case dataLoaded([Item])
    ///     }
    ///
    ///     static var defaultTrigger: When { .onAppear }
    ///
    ///     static func update(_ when: When, state: inout State, ...) throws { ... }
    /// }
    /// ```
    /// When a parent creates `state.child = ProfileReducer.State()`, the child store
    /// is wired and `.onAppear` is dispatched automatically.
    ///
    /// Returns `nil` by default (no automatic trigger).
    static var defaultTrigger: When? { get }
}

extension Reducer {
    /// Default: no automatic trigger on wiring
    public static var defaultTrigger: When? { nil }
}
