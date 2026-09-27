//
//  InjectionKey.swift
//
//
//  Created by Claude Code on 26/9/26.
//

import Foundation

/// A dependency's default value, decoupled from the dependency's own type — ports
/// `statoscope-kotlin`'s `InjectionKey<T>` (`src/main/kotlin/statoscope/core/InjectionKey.kt`)
/// directly.
///
/// `Injectable` requires `static var defaultValue: Self { get }` on the injected type itself —
/// which a protocol with `Self` requirements can never satisfy (Swift: "protocol 'X' has Self or
/// associated type requirements; use it only as a generic constraint"). `InjectionKey<T>` moves
/// the default off `T` entirely: the KEY carries it, so `T` can legitimately be a real Swift
/// protocol with multiple conformances, not just an `Injectable`-conforming struct.
///
/// ```swift
/// protocol NetworkService {
///     func fetch() async throws -> Data
/// }
/// let NetworkServiceKey = InjectionKey<NetworkService>(defaultValue: RealNetworkService())
///
/// final class MyScope: Statostore {
///     @Injected(NetworkServiceKey) var service: NetworkService
/// }
/// ```
///
/// Used with `@Injected` (classic `Statostore`) — see that type's own doc. Resolving a
/// dependency injected under this key still goes through the same tree walk as `Injectable`
/// (`InjectionTreeNode._resolveUnsafe`) — `defaultValue` is only ever the fallback when nothing
/// was actually injected, not a cache or a replacement for real injection.
public struct InjectionKey<T> {
    public let defaultValue: T
    public let name: String?

    public init(defaultValue: T, name: String? = nil) {
        self.defaultValue = defaultValue
        self.name = name
    }
}
