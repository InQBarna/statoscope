//
//  MiddlewareReducer.swift
//  Statoscope
//
//  Protocol for Reducers that intercept child scope events
//

/// The result of a `MiddlewareReducer.updateSubstate` call — makes explicit whether the
/// intercepted child event still gets delivered to the child.
///
/// `updateSubstate` runs BEFORE the child's own `update()` and cannot mutate parent state
/// directly — `parentState` is read-only. To react, return a delegated `When`; it is sent to
/// the parent's own `update()`, the only place `State` is ever mutated. Returning `.pass` or
/// `.react` still forwards the event to the child afterward; returning `.intercept` consumes
/// it — the child's `update()` never runs for this event.
///
/// Reach for `.intercept` whenever the reaction makes forwarding unsafe or meaningless — most
/// commonly when it removes or replaces the very child subtree the event originated from.
/// Forwarding into a subtree that was just synchronously torn down is a use-after-free at the
/// state layer: the child object survives (Swift ARC keeps it alive), but it is no longer
/// reachable from the parent's state, so the mutation the forwarded event performs is silently
/// unobservable.
public enum SubstateOutcome<When> {
    /// No reaction. Forward the event to the child as normal.
    case pass
    /// React by sending `when` to the parent's own `update()`, then still forward the event
    /// to the child.
    case react(When)
    /// Consume the event: optionally send `when` to the parent's own `update()`, but do NOT
    /// forward the event to the child.
    case intercept(When?)
}

/// Protocol for Reducers that want to intercept child scope events
///
/// When a Reducer conforms to `MiddlewareReducer`, the generated Store class
/// will implement `HierarchialScopeMiddleWare` and intercept all events from
/// child scopes BEFORE they are processed.
///
/// Whether the event still reaches the child afterward depends on the returned
/// `SubstateOutcome` — see its documentation.
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
///         case resetChild
///     }
///
///     static func updateSubstate<Child: Reducer>(
///         _ childType: Child.Type,
///         childState: Child.State,
///         childWhen: Child.When,
///         parentState: State,
///         dependencies: ReducerDependencies
///     ) throws -> SubstateOutcome<When> {
///         // Child.State and Child.When are tied — both belong to the same Reducer
///         guard let when = childWhen as? ChildReducer.When else { return .pass }
///         switch when {
///         case .taskCompleted(let task):
///             // Reacting doesn't invalidate the child — still forward the original event.
///             return .react(.childDelegated(task))
///         case .tooManyFailures:
///             // Reacting tears the child down — forwarding afterward would be unsafe. Consume it.
///             return .intercept(.resetChild)
///         }
///     }
///
///     static func update(_ when: When, state: inout State, ...) throws {
///         switch when {
///         case .childDelegated(let task):
///             state.delegatedTasks.append(task)
///         case .resetChild:
///             state.child = ChildReducer.State()
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
    /// Whether the child still processes the event afterward is controlled by the
    /// returned `SubstateOutcome` — `.pass`/`.react` forward it, `.intercept` consumes it.
    ///
    /// - Parameters:
    ///   - childState: The child scope's state (type-erased, cast to specific type if needed)
    ///   - childWhen: The child's event (type-erased, cast to specific type if needed)
    ///   - parentState: Parent's current state, read-only — `updateSubstate` decides, it never
    ///     mutates. Any reaction must go through a delegated `When` (see `SubstateOutcome`),
    ///     so it lands in `update()`, the single place `State` changes and the only place a
    ///     reaction can also enqueue effects.
    ///   - dependencies: Access to injected dependencies (same as in update())
    ///
    /// - Returns: A `SubstateOutcome` describing the delegated reaction (if any) and whether
    ///   the event should still be forwarded to the child.
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> SubstateOutcome<When>
}
