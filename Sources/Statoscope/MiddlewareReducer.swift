//
//  MiddlewareReducer.swift
//  Statoscope
//
//  Protocol for Reducers that intercept child scope events
//

/// Protocol for Reducers that want to intercept child scope events
///
/// When a Reducer conforms to `MiddlewareReducer`, the generated Store class
/// will implement `HierarchialScopeMiddleWare` and intercept all events from
/// child scopes BEFORE they are processed.
///
/// The framework automatically forwards events to the child after interception.
///
/// Example:
/// ```swift
/// @Reducer
/// struct ParentReducer: MiddlewareReducer {
///     struct State: Injectable {
///         @SubState var child: ChildReducer.State?
///         var delegatedTasks: [String] = []
///     }
///
///     enum When {
///         case childDelegated(String)
///     }
///
///     static func updateSubscope<ChildState, ChildWhen>(
///         childState: ChildState,
///         childWhen: ChildWhen,
///         parentState: inout State
///     ) throws -> When? {
///         // Type-cast to specific child
///         if let childWhen = childWhen as? ChildReducer.When {
///             if case .taskCompleted(let task) = childWhen {
///                 // React BEFORE child processes event
///                 return .childDelegated(task)  // Delegate to parent
///             }
///         }
///         return nil  // No delegation
///         // Framework automatically forwards to child
///     }
///
///     static func update(_ when: When, state: inout State, ...) throws {
///         switch when {
///         case .childDelegated(let task):
///             state.delegatedTasks.append(task)
///         }
///     }
/// }
/// ```
public protocol MiddlewareReducer {
    associatedtype State
    associatedtype When

    /// Called BEFORE child's update() executes
    ///
    /// This method is invoked when a child scope sends an event, allowing the parent
    /// to intercept and react BEFORE the child processes it.
    ///
    /// **The framework automatically forwards the event to the child after this method returns.**
    ///
    /// - Parameters:
    ///   - childState: The child scope's state (type-erased, cast to specific type if needed)
    ///   - childWhen: The child's event (type-erased, cast to specific type if needed)
    ///   - parentState: Parent's mutable state for modifications
    ///
    /// - Returns: Optional parent When to send for delegation (executed BEFORE child's update)
    ///
    /// - Note: If you return a When value, it will be sent to the parent's update() method
    ///         BEFORE the child's event is forwarded to the child.
    static func updateSubscope<ChildState, ChildWhen>(
        childState: ChildState,
        childWhen: ChildWhen,
        parentState: inout State
    ) throws -> When?
}
