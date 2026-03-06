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
///     static func updateSubstate<Child: Reducer>(
///         _ childType: Child.Type,
///         childState: Child.State,
///         childWhen: Child.When,
///         parentState: inout State
///     ) throws -> When? {
///         // Child.State and Child.When are tied — both belong to the same Reducer
///         guard let when = childWhen as? ChildReducer.When else { return nil }
///         if case .taskCompleted(let task) = when {
///             return .childDelegated(task)
///         }
///         return nil
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
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: inout State
    ) throws -> When?
}
