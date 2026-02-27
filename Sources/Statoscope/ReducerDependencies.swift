//
//  ReducerDependencies.swift
//  Statoscope
//
//  Created by Claude Code on 27/2/26.
//

import Foundation

/// Protocol providing dependency injection access for reducers
///
/// This protocol provides a minimal, clean API for reducers to access injected dependencies
/// from the scope's injection tree. It wraps the underlying InjectionTreeNode functionality
/// with a simpler interface.
///
/// ## Example:
/// ```swift
/// struct MyReducer: Reducer {
///     static func update(
///         _ when: When,
///         state: inout MyState,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         // Resolve dependencies
///         let logger: Logger = try dependencies.resolve()
///         logger.log("Processing event: \(when)")
///
///         // Update state
///         state.count += 1
///     }
/// }
/// ```
public protocol ReducerDependencies {
    /// Resolve an injected dependency from the injection tree
    ///
    /// Searches up the injection tree to find an instance of the requested type.
    ///
    /// - Returns: The resolved instance
    /// - Throws: If the dependency cannot be found in the injection tree
    func resolve<T: Injectable>() throws -> T

    /// Inject an object into the injection tree
    ///
    /// **Note:** Use with caution in reducers. Injecting objects in reducers can make
    /// them less pure and harder to test. Prefer injecting dependencies at scope
    /// initialization time rather than during update.
    ///
    /// - Parameter object: The object to inject
    func inject<T>(_ object: T)
}

/// Internal implementation of ReducerDependencies that wraps an InjectionTreeNode
@_spi(Internal)
public struct ReducerDependenciesImpl: ReducerDependencies {
    private let node: InjectionTreeNode?

    init(node: InjectionTreeNode?) {
        self.node = node
    }

    public func resolve<T: Injectable>() throws -> T {
        guard let node = node else {
            throw InjectionError.noInjectionTree
        }
        return try node._resolve()
    }

    public func inject<T>(_ object: T) {
        node?.injectObject(object)
    }
}

/// Error thrown when injection operations fail
public enum InjectionError: Error, CustomStringConvertible {
    case noInjectionTree

    public var description: String {
        switch self {
        case .noInjectionTree:
            return "No injection tree available"
        }
    }
}
