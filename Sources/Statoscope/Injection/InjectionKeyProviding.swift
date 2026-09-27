//
//  InjectionKeyProviding.swift
//
//

/// Lets a concrete conforming type carry its own `InjectionKey`, so a `@InjectedByKey`-style
/// declaration can reach for the type itself instead of a separately-named global constant.
///
/// The plain `InjectionKey<T>` value (see that type's own doc) has a discoverability gap: nothing
/// about `@InjectedByKey(networkServiceKey)` tells you `networkServiceKey` exists, or where to
/// find it, unless you already know to look. `InjectionKeyProviding` closes that gap by attaching
/// the key to the type you'd need to know about anyway — the concrete default implementation:
///
/// ```swift
/// protocol NetworkService {
///     func fetch() async throws -> Data
/// }
///
/// struct RealNetworkService: NetworkService, InjectionKeyProviding {
///     static var injectionKey: InjectionKey<NetworkService> { .init(defaultValue: RealNetworkService()) }
/// }
///
/// final class MyScope: Statostore {
///     @InjectedByKey(RealNetworkService.self) var service: NetworkService
/// }
/// ```
///
/// Purely additive: the plain `InjectionKey<T>` initializers on `@InjectedByKey`,
/// `@ReducerInjectedByKey`, `@InjectedParamByKey` are untouched — this just adds a second,
/// more discoverable way to reach the same key. A type used to swap in a value for testing (a
/// mock, a fake) has no reason to conform to this — it's only for the type that owns the default.
public protocol InjectionKeyProviding {
    associatedtype InjectedValue
    static var injectionKey: InjectionKey<InjectedValue> { get }
}
