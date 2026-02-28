//
//  SubStateBinding.swift
//  Statoscope
//
//  Created by Claude Code on 27/2/26.
//

import Foundation

/// A binding to child reducer's state (similar to @Subscope)
///
/// Manages the lifecycle of a child ReducerStore and provides access to its state.
/// The child store is automatically created when you assign state to this binding.
///
/// ## Example:
/// ```swift
/// struct ParentState {
///     var count: Int = 0
///     var child: SubStateBinding<ChildState>? = nil  // ✅ Child binding (optional)
/// }
///
/// struct ChildState {
///     var value: Int = 0
/// }
///
/// struct ParentReducer: Reducer {
///     static func update(
///         _ when: When,
///         state: inout ParentState,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         switch when {
///         case .createChild:
///             // Create child by assigning state!
///             state.child = dependencies.createChild(
///                 ChildReducer.self,
///                 initialState: ChildState(value: 10)
///             )
///
///         case .updateChild:
///             // Access child state
///             state.child?.value += 1
///         }
///     }
/// }
/// ```
@dynamicMemberLookup
public struct SubStateBinding<ChildState> {
    private var store: (any ObservableObject)?
    private let stateGetter: () -> ChildState?
    private let stateSetter: (ChildState) -> Void

    /// Temporary storage for child state awaiting Store creation
    private var pendingState: ChildState?

    /// Creates a sub state binding from a child store
    ///
    /// - Parameter store: The child reducer store
    @_spi(Internal)
    public init<R: Reducer>(store: ReducerStore<R>) where R.State == ChildState {
        self.store = store
        self.stateGetter = { store.state }
        self.stateSetter = { [weak store] newState in
            // Directly update the child store's state
            store?.state = newState
        }
        self.pendingState = nil
    }

    /// Creates a sub state binding from macro-generated Store using reflection
    ///
    /// - Parameter macroStore: The child macro-generated Store (e.g., ChildReducer.Store)
    @_spi(Internal)
    public init<S>(macroStore: S) where S: ObservableObject & AnyObject {
        self.store = macroStore
        self.pendingState = nil

        // Use KVC to access state property dynamically
        self.stateGetter = { [weak macroStore] in
            guard let store = macroStore else { return nil }
            // Use KVC to get the state value
            guard let stateValue = (store as? NSObject)?.value(forKey: "state") as? ChildState else {
                return nil
            }
            return stateValue
        }

        self.stateSetter = { [weak macroStore] newState in
            // Use KVC to update state
            guard let store = macroStore as? NSObject else { return }
            store.setValue(newState, forKey: "state")
        }
    }

    /// Creates a pending sub state binding (Store will be created by parent)
    ///
    /// - Parameter wrappedValue: The initial child state
    @_spi(Internal)
    public init(wrappedValue: ChildState) {
        self.store = nil
        self.pendingState = wrappedValue
        self.stateGetter = { [wrappedValue] in wrappedValue }
        self.stateSetter = { _ in }
    }

    /// Creates a sub state binding with direct closure access (for macro-generated Stores)
    ///
    /// - Parameters:
    ///   - storeGetter: Closure that returns the current state
    ///   - storeSetter: Closure that updates the state
    ///   - underlyingStore: The underlying Store object
    @_spi(Internal)
    public init(
        storeGetter: @escaping () -> ChildState?,
        storeSetter: @escaping (ChildState) -> Void,
        underlyingStore: any ObservableObject
    ) {
        self.store = underlyingStore
        self.pendingState = nil
        self.stateGetter = storeGetter
        self.stateSetter = storeSetter
    }

    /// The current state of the child
    ///
    /// Reading returns the child's current state.
    /// Writing updates the child's state (if the framework supports it).
    public var wrappedValue: ChildState? {
        get { stateGetter() }
        nonmutating set {
            if let newValue = newValue {
                stateSetter(newValue)
            }
        }
    }

    /// Access the wrapped value's properties directly
    ///
    /// Allows using `state.child?.value` to access child state properties.
    public subscript<T>(dynamicMember keyPath: WritableKeyPath<ChildState, T>) -> T? {
        get {
            wrappedValue?[keyPath: keyPath]
        }
        nonmutating set {
            if var current = wrappedValue, let newValue = newValue {
                current[keyPath: keyPath] = newValue
                stateSetter(current)
            }
        }
    }

    /// Access to underlying store (for framework use)
    @_spi(Internal)
    public var _underlyingStore: (any ObservableObject)? {
        store
    }

    /// Check if this binding is pending Store creation
    @_spi(Internal)
    public var _isPending: Bool {
        store == nil && pendingState != nil
    }

    /// Get the pending state (for Store creation)
    @_spi(Internal)
    public var _pendingState: ChildState? {
        pendingState
    }
}

// MARK: - Equatable

extension SubStateBinding: Equatable where ChildState: Equatable {
    public static func == (lhs: SubStateBinding<ChildState>, rhs: SubStateBinding<ChildState>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// MARK: - Hashable

extension SubStateBinding: Hashable where ChildState: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
