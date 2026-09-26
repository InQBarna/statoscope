//
//  ReducerInjectedByKey.swift
//  Statoscope
//

/// `ReducerInjected`'s counterpart for a protocol-typed dependency — see `InjectionKey`'s own doc
/// for why `Injectable` alone can't do this. Additive: existing `@ReducerInjected` code is
/// untouched, this is a second way to declare `State`-ambient injection, not a replacement.
///
/// The value is injected **by snapshot** in the Store's state getter — once per `state` access,
/// same as `@ReducerInjected` — via the `@Reducer` macro's generated `_superSlots`.
///
/// ## Usage:
/// ```swift
/// let NetworkServiceKey = InjectionKey<NetworkService>(defaultValue: RealNetworkService())
///
/// @Reducer
/// struct MyReducer {
///     struct State {
///         var count: Int = 0
///         @ReducerInjectedByKey(NetworkServiceKey) var service: NetworkService
///     }
/// }
/// ```
///
/// The `service` property returns `NetworkServiceKey.defaultValue` until the Store is wired into
/// an injection tree.
@propertyWrapper
public struct ReducerInjectedByKey<Value> {

    private var _value: Value

    /// Default initializer — uses `key.defaultValue` until the framework injects the real value.
    public init(_ key: InjectionKey<Value>) {
        _value = key.defaultValue
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
    /// via `state.$service = ReducerInjectedByKey(injectedValue:)`.
    public var projectedValue: ReducerInjectedByKey<Value> {
        get { self }
        set { self = newValue }
    }
}

extension ReducerInjectedByKey: Equatable where Value: Equatable {
    public static func == (lhs: ReducerInjectedByKey<Value>, rhs: ReducerInjectedByKey<Value>) -> Bool {
        lhs._value == rhs._value
    }
}

extension ReducerInjectedByKey: Hashable where Value: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(_value)
    }
}

// MARK: - InjectionTreeNode helper

extension InjectionTreeNode {
    /// Resolves a dependency for use in `@ReducerInjectedByKey` injection.
    ///
    /// Returns `key.defaultValue` if the dependency cannot be found in the tree.
    public func resolveForBinding<T>(_ key: InjectionKey<T>) -> T {
        _resolve(key)
    }
}
