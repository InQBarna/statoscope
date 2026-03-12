//
//  SuperState.swift
//  Statoscope
//
//  Created by Claude Code on 12/3/26.
//

/// Property wrapper for parent state access in a Reducer's State struct.
///
/// Holds a **value snapshot** of the parent state, injected by the framework before each
/// `update()` call. The snapshot is a copy taken at injection time — no live reference
/// to the parent store is retained.
///
/// A closure is used internally to break the recursive value-type cycle that would occur
/// if `ParentState` were stored directly (since `ChildState` ← `ParentState` ← `ChildState`
/// forms a cycle when both use plain stored value types). The closure captures a copy of
/// the parent state by value — not a reference — so `update()` remains a pure function.
///
/// The property is **read-only**: assigning `state.parent = ...` is a compile-time error,
/// enforcing the pattern that only the parent reducer mutates parent state.
///
/// ## Usage:
/// ```swift
/// @Reducer
/// struct ChildReducer {
///     struct State {
///         @SuperState var parent: ParentReducer.State
///         var value: Int = 0
///     }
///
///     static func update(_ when: When, state: inout State, ...) throws {
///         state.value = state.parent.count * 2  // read-only snapshot access
///     }
/// }
/// ```
///
/// `Value` must conform to `Injectable` so the framework can produce a default when
/// the child store is not yet wired to a parent.
@propertyWrapper
public struct SuperState<Value: Injectable> {

    // Closure breaks the recursive value-type cycle (Parent → Child → Parent).
    // Captures the parent state snapshot BY VALUE at injection time — no live reference retained.
    private let _getter: () -> Value

    /// Default initializer — returns `Value.defaultValue` until the framework injects the real parent.
    public init() {
        _getter = { Value.defaultValue }
    }

    /// Initializer accepting the `observed` parameter from `@SuperState(observed: true)`.
    ///
    /// `observed` is consumed by the `@Reducer` macro to generate
    /// `@Superscope(observed: true)` on the Store class — it is not used at runtime here.
    public init(observed: Bool) {
        _getter = { Value.defaultValue }
    }

    /// Framework injection initializer. Captures `injectedValue` by value (a snapshot).
    public init(injectedValue: Value) {
        _getter = { injectedValue }
    }

    /// Read-only access to the parent state snapshot.
    ///
    /// Has no setter — assigning `state.parent = ...` is a compile-time error,
    /// enforcing the pattern that only the parent reducer mutates parent state.
    public var wrappedValue: Value {
        get { _getter() }
    }

    /// Projected value allows the framework to replace the entire wrapper
    /// via `state.$parent = SuperState(injectedValue:)`.
    public var projectedValue: SuperState<Value> {
        get { self }
        set { self = newValue }
    }
}

extension SuperState: Equatable where Value: Equatable {
    public static func == (lhs: SuperState<Value>, rhs: SuperState<Value>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

extension SuperState: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
