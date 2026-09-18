//
//  ReducerDispatchable.swift
//  Statoscope
//

/// Protocol enabling type-erased dispatch of `updateSubstate` across the reducer hierarchy.
///
/// Every `@Reducer`-generated `Store` class conforms to this protocol. It allows any ancestor's
/// `updateSubstate` to be called when any descendant sends an event, regardless of how deep in
/// the hierarchy the event originates.
///
/// ## How it works
/// When a grandchild sends an event:
/// 1. `callParentEnclosedHierarchialUpdate` passes the **grandchild** as `event.child` to ALL ancestors.
/// 2. Each ancestor's generated `updateSubscope` casts `event.child as? any ReducerDispatchable`.
/// 3. The grandchild's `_callUpdateSubstate` is invoked with the ancestor's type.
/// 4. Inside, it calls `Parent.updateSubstate(GrandchildReducer.self, ...)` — fully type-safe.
///
/// This eliminates the need for artificial forwarding events in intermediate reducers.
public protocol ReducerDispatchable: AnyObject {
    /// Calls `Parent.updateSubstate` with this store's reducer type and current state.
    ///
    /// - Parameters:
    ///   - parentType: The `MiddlewareReducer` type to call `updateSubstate` on.
    ///   - when: The event (cast to this store's `When` type internally).
    ///   - parentState: The parent's current state (read-only).
    ///   - dependencies: Reducer dependencies for injection.
    /// - Returns: The `SubstateOutcome` from the parent's `updateSubstate`, or `.pass` if the
    ///   event type doesn't match this store's `When` type.
    func _callUpdateSubstate<Parent: MiddlewareReducer>(
        _ parentType: Parent.Type,
        when: Any,
        parentState: Parent.State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<Parent.When>
}
