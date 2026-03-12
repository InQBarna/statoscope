//
//  SubState.swift
//  Statoscope
//
//  Created by Claude Code on 12/3/26.
//

/// Property wrapper for child state properties in a Reducer's State struct.
///
/// Tracks whether the property has been assigned (dirty) vs injected by the framework.
/// The `@Reducer` macro reads `@SubState` annotations to generate child store lifecycle
/// management: copy child state in before `update()`, write it back after, and create/destroy
/// child stores based on the dirty flag.
///
/// ## Usage:
/// ```swift
/// @Reducer
/// struct ParentReducer {
///     struct State {
///         var count: Int = 0
///         @SubState var child: ChildReducer.State?
///     }
///     ...
/// }
/// ```
///
/// ## Dirty Flag Semantics:
/// - `isDirty = true`: the reducer assigned a new value (create/update/destroy child store)
/// - `isDirty = false`: value was injected by the framework (no lifecycle changes)
///
/// Assignment via `wrappedValue` setter sets `isDirty = true`.
/// Framework injection via `$child = SubState(injectedValue:)` sets `isDirty = false`.
@propertyWrapper
public struct SubState<Value> {
    private var _value: Value?
    public private(set) var isDirty: Bool = false

    /// Default initializer — clean, nil state.
    public init() {
        _value = nil
        isDirty = false
    }

    /// Framework injection initializer — sets value without marking dirty.
    public init(injectedValue: Value?) {
        _value = injectedValue
        isDirty = false
    }

    /// Standard property wrapper initializer — used when a default value is provided in the struct.
    /// Does not mark dirty; this is initialization, not a user assignment.
    public init(wrappedValue: Value?) {
        _value = wrappedValue
        isDirty = false
    }

    /// The wrapped value. Setting marks the property as dirty.
    public var wrappedValue: Value? {
        get { _value }
        set {
            _value = newValue
            isDirty = true
        }
    }

    /// Projected value enables `$child = SubState(injectedValue:)` from outside the struct,
    /// which replaces the entire wrapper (including dirty flag) without going through the setter.
    public var projectedValue: SubState<Value> {
        get { self }
        set { self = newValue }
    }
}

extension SubState: Equatable where Value: Equatable {
    public static func == (lhs: SubState<Value>, rhs: SubState<Value>) -> Bool {
        lhs._value == rhs._value && lhs.isDirty == rhs.isDirty
    }
}

extension SubState: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_value)
        hasher.combine(isDirty)
    }
}
