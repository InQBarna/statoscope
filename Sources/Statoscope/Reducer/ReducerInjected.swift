//
//  ReducerInjected.swift
//  Statoscope
//

/// Declares an ambient dependency on a Reducer's State struct, resolved from the injection tree.
/// `Value` can be any `Injectable`-conforming type (gets its key for free, see `Injectable`'s own
/// doc) or any real Swift protocol whose default implementation conforms to
/// `InjectionKeyProviding`.
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

    /// Default initializer — uses `key.defaultValue` until the framework injects the real value.
    public init(_ key: InjectionKey<Value>) {
        _value = key.defaultValue
    }

    /// Reaches for the key through its `InjectionKeyProviding` conforming type instead of a
    /// separately-named global — see that protocol's own doc. Also covers any `Injectable` type,
    /// which conforms to `InjectionKeyProviding` automatically.
    public init<P: InjectionKeyProviding>(_ providerType: P.Type) where P.InjectedValue == Value {
        _value = providerType.injectionKey.defaultValue
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
    public func resolveForBinding<T>(_ key: InjectionKey<T>) -> T {
        _resolve(key)
    }

    /// `resolveForBinding(_:)`'s `InjectionKeyProviding` counterpart — the `@Reducer` macro emits
    /// whichever overload matches the raw expression inside `@ReducerInjected(...)`, so this
    /// needs no macro-side branching: `SomeType.self` resolves here, a plain key value above.
    public func resolveForBinding<P: InjectionKeyProviding>(_ providerType: P.Type) -> P.InjectedValue {
        _resolve(providerType.injectionKey)
    }
}
