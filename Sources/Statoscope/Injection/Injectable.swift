//
//  Injectable.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Declares a dependency's default value, resolved from the injection tree.
///
/// `InjectedValue` defaults to `Self`, covering the common case — a concrete type with exactly
/// one real shape:
/// ```swift
/// struct DateProvider: Injectable {
///     static var defaultValue: DateProvider { .init(now: Date.init) }
/// }
/// ```
/// For a dependency with more than one plausible conformance (a real implementation, a fake for
/// tests), a concrete type can instead declare a default for a *protocol* it conforms to, by
/// giving `defaultValue` a different return type — `InjectedValue` infers from that return type,
/// no `typealias` needed:
/// ```swift
/// protocol NetworkService { func fetch() async throws -> Data }
/// struct RealNetworkService: Injectable, NetworkService {
///     static var defaultValue: NetworkService { RealNetworkService() }
/// }
/// ```
/// Both forms are read identically — `@Injected(DateProvider.self)`, `@Injected(RealNetworkService.self)`
/// — and both can be swapped for a test double via `injectObject(_:for:)`, since a `Fake`/`Mock`
/// conformance has no reason to declare its own default (it's only for the type that owns the
/// real one).
///
/// Used by the injection property wrappers:
/// * ``Injected``: To use an Injectable instance in your scope.
/// * ``Superscope``: To use a superscope in your scope, automatically retrieved
/// * ``Subscope``: To retain subscopes that may need access to superscopes
public protocol Injectable {
    associatedtype InjectedValue = Self
    static var defaultValue: InjectedValue { get }
}
