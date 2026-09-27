//
//  InjectionKeyProviding.swift
//
//

/// Lets a concrete conforming type carry its own `InjectionKey`, so an `@Injected`-style
/// declaration can reach for the type itself instead of a separately-named global constant.
///
/// The plain `InjectionKey<T>` value (see that type's own doc) has a discoverability gap: nothing
/// about `@Injected(networkServiceKey)` tells you `networkServiceKey` exists, or where to
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
///     @Injected(RealNetworkService.self) var service: NetworkService
/// }
/// ```
///
/// `Injectable`-conforming types (`Injected`/`ReducerInjected`/`InjectedParam`'s original,
/// value-only case) conform to this automatically — see `Injectable`'s own doc — so the same
/// `SomeType.self` argument works whether `SomeType` is a concrete `Injectable` value type or,
/// as here, a protocol's chosen default implementation. A type used only to swap in a value for
/// testing (a mock, a fake) has no reason to conform to this — it's only for the type that owns
/// the default.
public protocol InjectionKeyProviding {
    associatedtype InjectedValue
    static var injectionKey: InjectionKey<InjectedValue> { get }
}
