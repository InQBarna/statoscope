//
//  ReducerInjected.swift
//  Statoscope
//

/// Declares an ambient dependency on a Reducer's State struct, resolved from the injection tree.
/// `Value` can be any `Injectable`-conforming type — see that protocol's own doc for the two
/// shapes it supports, a concrete type's own default or a protocol's via a named real
/// implementation.
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
///         @ReducerInjected(FeatureFlags.self) var featureFlags: FeatureFlags   // Injectable
///         @ReducerInjected(RealLogger.self) var logger: Logger                  // protocol
///     }
/// }
/// ```
///
/// The `featureFlags` property returns the key's default value until the Store
/// is wired into an injection tree.
@propertyWrapper
public struct ReducerInjected<Value> {

    private var _value: Value

    /// Default initializer — uses the type's own declared default until the framework injects
    /// the real value. See `Injectable`'s own doc.
    public init<P: Injectable>(_ providerType: P.Type) where P.InjectedValue == Value {
        _value = providerType.defaultValue
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
    /// Returns `key.defaultValue` if the dependency cannot be found in the tree.
    public func resolveForBinding<P: Injectable>(_ providerType: P.Type) -> P.InjectedValue {
        _resolve(providerType.defaultValue)
    }
}
