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

    /// Create a SuperStateBinding to access parent state
    ///
    /// Returns a binding that resolves the parent's state from the injection tree.
    ///
    /// ## Example:
    /// ```swift
    /// state.child = dependencies.createChild(
    ///     ChildReducer.self,
    ///     initialState: ChildState(
    ///         parent: dependencies.superBinding(of: ParentReducer.self),
    ///         value: 0
    ///     )
    /// )
    /// ```
    ///
    /// - Parameter reducerType: The parent reducer type
    /// - Returns: A SuperStateBinding to the parent's state
    func superBinding<ParentReducer: Reducer>(
        of reducerType: ParentReducer.Type
    ) -> SuperStateBinding<ParentReducer.State> where ParentReducer.State: Injectable

    /// Create a child reducer with SubStateBinding
    ///
    /// Creates a new child ReducerStore and returns it wrapped in a SubStateBinding.
    /// This binding can be stored in the parent's State struct.
    ///
    /// ## Example:
    /// ```swift
    /// struct ParentState {
    ///     var count: Int = 0
    ///     var child: SubStateBinding<ChildState>? = nil
    /// }
    ///
    /// static func update(
    ///     _ when: When,
    ///     state: inout ParentState,
    ///     effectsState: inout EffectsState<When>,
    ///     dependencies: ReducerDependencies
    /// ) throws {
    ///     switch when {
    ///     case .createChild:
    ///         // Create child - binding stored in parent state!
    ///         state.child = dependencies.createChild(
    ///             ChildReducer.self,
    ///             initialState: ChildState(value: 10)
    ///         )
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - reducerType: The child reducer type
    ///   - initialState: The initial state for the child
    /// - Returns: A SubStateBinding managing the child store
    func createChild<ChildReducer: Reducer>(
        _ reducerType: ChildReducer.Type,
        initialState: ChildReducer.State
    ) -> SubStateBinding<ChildReducer.State>
}

/// Internal implementation of ReducerDependencies that wraps an InjectionTreeNode
@_spi(Internal)
public struct ReducerDependenciesImpl: ReducerDependencies {
    private let node: InjectionTreeNode?
    private weak var parentStore: (any ObservableObject)?

    init(node: InjectionTreeNode?, parentStore: (any ObservableObject)? = nil) {
        self.node = node
        self.parentStore = parentStore
    }

    public func resolve<T: Injectable>() throws -> T {
        guard let node = node else {
            throw InjectionError.noInjectionTree
        }
        return try node._resolveUnsafe()
    }

    public func inject<T>(_ object: T) {
        node?.injectObject(object)
    }

    public func superBinding<ParentReducer: Reducer>(
        of reducerType: ParentReducer.Type
    ) -> SuperStateBinding<ParentReducer.State> where ParentReducer.State: Injectable {
        SuperStateBinding._fromParentStore(parentStore, reducerType: reducerType)
    }

    public func createChild<ChildReducer: Reducer>(
        _ reducerType: ChildReducer.Type,
        initialState: ChildReducer.State
    ) -> SubStateBinding<ChildReducer.State> {
        // Create child store
        let child = ReducerStore<ChildReducer>(initialState: initialState)

        // Set up injection tree relationship
        if let parentNode = node {
            (child as InjectionTreeNode)._parentNode = parentNode
        }

        // Return wrapped in SubStateBinding
        return SubStateBinding(store: child)
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
