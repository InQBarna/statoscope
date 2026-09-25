//
//  MiddlewareReducer.swift
//  Statoscope
//
//  Protocol for Reducers that react to child scope events
//

/// Protocol for Reducers that want to react to child scope events
///
/// When a Reducer conforms to `MiddlewareReducer`, the generated Store class will implement
/// `HierarchialScopeMiddleWare` and observe events from child scopes.
///
/// `updateSubstate` runs **after** the child's own `update()` has already processed the event —
/// `childState` is the child's state once that update finished, not a preview of what's about
/// to happen. This mirrors `statoscope-zustand`'s `onChildAction(action, childState)`, which
/// documents the same thing: "called with the action and the child's already-updated state."
/// The event is always forwarded to the child; there is no way to intercept or veto it, and
/// none is needed — by the time a parent's ancestors get a look, the child has already safely
/// applied the event to itself, so a parent reaction that goes on to destroy or replace that
/// child subtree can never race with a stale event still being delivered into it. That race
/// (and the `SubstateOutcome.intercept` case that existed solely to guard against it) doesn't
/// exist in this ordering.
///
/// `parentState` is read-only — `updateSubstate` decides, it never mutates. To react, return a
/// delegated `When`; it is sent to the parent's own `update()`, the only place `State` is ever
/// mutated and the only place a reaction can also enqueue effects. Return `nil` for no reaction.
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
///         parentState: State,
///         dependencies: ReducerDependencies
///     ) throws -> When? {
///         // Child.State and Child.When are tied — both belong to the same Reducer
///         guard let when = childWhen as? ChildReducer.When else { return nil }
///         switch when {
///         case .taskCompleted(let task):
///             return .childDelegated(task)
///         }
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

    /// Called AFTER a child scope's own `update()` has processed an event.
    ///
    /// This method is invoked once a child scope has finished handling an event, letting an
    /// ancestor react to what happened — including, safely, by destroying or replacing the
    /// child subtree the event came from, since the event has already been fully applied.
    ///
    /// - Parameters:
    ///   - childState: The child scope's state (type-erased, cast to specific type if needed),
    ///     already updated for `childWhen`.
    ///   - childWhen: The child's event (type-erased, cast to specific type if needed)
    ///   - parentState: Parent's current state, read-only — `updateSubstate` decides, it never
    ///     mutates. Any reaction must go through a delegated `When`, so it lands in `update()`,
    ///     the single place `State` changes and the only place a reaction can also enqueue
    ///     effects.
    ///   - dependencies: Access to injected dependencies (same as in update())
    ///
    /// - Returns: An optional delegated `When` to send to the parent's own `update()`, or `nil`
    ///   for no reaction.
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> When?
}
