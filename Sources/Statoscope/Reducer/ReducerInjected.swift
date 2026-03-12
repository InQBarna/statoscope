//
//  ReducerInjected.swift
//  Statoscope
//

/// Property wrapper for declaring Injectable dependencies on a Reducer's State struct.
///
/// The value is injected **by snapshot** in the Store's state getter — once per `state`
/// access, not once per property access. This makes it useful for:
/// - SwiftUI view rendering: `store.state.logger.level` reads the current injected value
/// - Passing read-only services into the State for view display logic
///
/// For `update()` logic, prefer `dependencies.resolve()` — it's the explicit,
/// recommended approach for reducer dependencies.
///
/// ## Usage:
/// ```swift
/// @Reducer
/// struct MyReducer {
///     struct State {
///         var count: Int = 0
///         @ReducerInjected var featureFlags: FeatureFlags
///     }
/// }
/// ```
///
/// The `featureFlags` property returns `FeatureFlags.defaultValue` until the Store
/// is wired into an injection tree.
@propertyWrapper
public struct ReducerInjected<Value: Injectable> {

    private var _value: Value

    /// Default initializer — uses `Value.defaultValue` until the framework injects the real value.
    public init() {
        _value = Value.defaultValue
    }

    /// Framework injection initializer — called by the generated Store state getter.
    public init(injectedValue: Value) {
        _value = injectedValue
    }

    /// Read-only access to the injected value snapshot.
    public var wrappedValue: Value {
        get { _value }
    }

    /// Projected value allows the framework to replace the wrapper
    /// via `state.$featureFlags = ReducerInjected(injectedValue:)`.
    public var projectedValue: ReducerInjected<Value> {
        get { self }
        set { self = newValue }
    }
}

extension ReducerInjected: Equatable where Value: Equatable {
    public static func == (lhs: ReducerInjected<Value>, rhs: ReducerInjected<Value>) -> Bool {
        lhs._value == rhs._value
    }
}

extension ReducerInjected: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_value)
    }
}

// MARK: - InjectionTreeNode helper

extension InjectionTreeNode {
    /// Resolves a dependency for use in `@ReducerInjected` injection.
    ///
    /// Returns `T.defaultValue` if the dependency cannot be found in the tree.
    public func resolveForBinding<T: Injectable>() -> T {
        _resolve()
    }
}
