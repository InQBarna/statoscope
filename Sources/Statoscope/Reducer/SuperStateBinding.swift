//
//  SuperStateBinding.swift
//  Statoscope
//
//  Created by Claude Code on 27/2/26.
//

import Foundation

/// A binding to parent reducer's state (similar to @Superscope)
///
/// Provides read-only access to the parent reducer's state, resolved from the injection tree.
/// The parent state must conform to Injectable to be resolvable.
///
/// ## Example:
/// ```swift
/// struct ParentState: Injectable {
///     static var defaultValue: ParentState { ParentState() }
///     var count: Int = 0
/// }
///
/// struct ChildState {
///     var parent: SuperStateBinding<ParentState> = .defaultValue  // ✅ Parent binding
///     var value: Int = 0
/// }
///
/// struct ChildReducer: Reducer {
///     static func update(
///         _ when: When,
///         state: inout ChildState,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         // Access parent state directly from State!
///         state.value = state.parent.count * 2
///     }
/// }
/// ```
@dynamicMemberLookup
public struct SuperStateBinding<ParentState: Injectable> {
    private let getter: () -> ParentState

    /// Creates a super state binding with a getter closure
    ///
    /// - Parameter get: Closure that returns the current parent state
    public init(get: @escaping () -> ParentState) {
        self.getter = get
    }

    /// The current value of the parent state
    ///
    /// This is read-only. To modify parent state, send events to the parent.
    public var wrappedValue: ParentState {
        getter()
    }

    /// Default value that returns Injectable.defaultValue
    ///
    /// Use this for initialization:
    /// ```swift
    /// var parent: SuperStateBinding<ParentState> = .defaultValue
    /// ```
    public static var defaultValue: SuperStateBinding<ParentState> {
        SuperStateBinding { ParentState.defaultValue }
    }

    /// Access the wrapped value's properties directly
    ///
    /// Allows using `state.parent.count` instead of `state.parent.wrappedValue.count`
    public subscript<T>(dynamicMember keyPath: KeyPath<ParentState, T>) -> T {
        wrappedValue[keyPath: keyPath]
    }

    /// Internal method to create binding from parent store
    @_spi(Internal)
    public static func _fromParentStore<R: Reducer>(_ parentStore: (any ObservableObject)?, reducerType: R.Type) -> SuperStateBinding<ParentState> where R.State == ParentState {
        SuperStateBinding {
            // Try ReducerStore<R> first (manual approach)
            if let store = parentStore as? ReducerStore<R> {
                return store.state
            }
            // Try to access state property via reflection (macro-generated Store)
            if let parentStore = parentStore {
                // Use Mirror to find the state property
                var mirror: Mirror? = Mirror(reflecting: parentStore)
                while let currentMirror = mirror {
                    // Check for public "state" property
                    if let stateValue = currentMirror.children.first(where: { $0.label == "state" })?.value as? ParentState {
                        return stateValue
                    }
                    // Check for private "_rawState" property (fallback)
                    if let rawStateValue = currentMirror.children.first(where: { $0.label == "_rawState" })?.value as? ParentState {
                        return rawStateValue
                    }
                    mirror = currentMirror.superclassMirror
                }
            }
            return ParentState.defaultValue
        }
    }
}

// MARK: - Equatable

extension SuperStateBinding: Equatable where ParentState: Equatable {
    public static func == (lhs: SuperStateBinding<ParentState>, rhs: SuperStateBinding<ParentState>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// MARK: - Hashable

extension SuperStateBinding: Hashable where ParentState: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
