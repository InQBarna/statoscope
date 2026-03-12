//
//  Macros.swift
//  
//
//  Created by Sergi Hernanz on 16/3/24.
//

import Foundation

@attached(peer, names: arbitrary)
public macro EffectStruct(
    equatable: Bool = false
) = #externalMacro(module: "StatoscopeMacros", type: "EffectStructMacro")

@attached(member, names: arbitrary)
public macro CaseAssociatedGet() = #externalMacro(module: "StatoscopeMacros", type: "CaseAssociatedGetMacro")

@attached(member, names: arbitrary)
public macro Copy() = #externalMacro(module: "StatoscopeMacros", type: "CopyMacro")

/// Macro that expands a property to use SuperStateBinding for parent state access
///
/// Usage:
/// ```swift
/// @SuperState var parent: ParentState
/// ```
///
/// Generates storage and computed property accessor for parent state binding.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro SuperState(observed: Bool = false) = #externalMacro(module: "StatoscopeMacros", type: "SuperStateMacro")

/// Macro for incremental migration: references a parent Statostore (not yet migrated to Reducer)
///
/// Usage in `Reducer.State`:
/// ```swift
/// struct State {
///     @SuperScope(observed: true) var parent: ParentStore  // ParentStore is a Statostore
/// }
/// ```
///
/// The `@Reducer` macro detects `@SuperScope` and generates
/// `@Superscope(observed: true) var _parent: ParentStore` on the Store class,
/// injecting a `ParentStoreBinding` so `state.parent` resolves the live store
/// from the injection tree.
///
/// For use directly on a Store class (StoreImpl), use `@Superscope` instead.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro SuperScope(observed: Bool = false) = #externalMacro(module: "StatoscopeMacros", type: "SuperScopeMacro")


/// Macro that declares an Injectable dependency on a Reducer's State struct
///
/// Use this inside a `Reducer.State` struct to declare dependencies that will be
/// resolved from the injection tree when the reducer runs. The `@Reducer` macro
/// detects these declarations and generates binding injection in the Store's
/// state getter.
///
/// ## Usage:
/// ```swift
/// @Reducer
/// struct MyReducer {
///     struct State {
///         var count: Int = 0
///         @ReducerInjected var logger: Logger     // resolved from injection tree
///         @ReducerInjected var analytics: Analytics
///     }
///
///     static func update(
///         _ when: When,
///         state: inout State,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         state.logger.log("Event: \(when)")
///         state.count += 1
///     }
/// }
/// ```
///
/// The dependency type must conform to `Injectable`. It returns `T.defaultValue`
/// until the Store is part of an injection tree.
///
/// **Note:** The same name as `@Injected` cannot be reused here because `@Injected`
/// requires an `InjectionTreeNode` class as the enclosing instance, but `State`
/// is a plain struct.
@attached(accessor)
@attached(peer, names: arbitrary)
public macro ReducerInjected() = #externalMacro(module: "StatoscopeMacros", type: "ReducerInjectedMacro")

/// Macro that generates a Store class for a Reducer
///
/// Usage:
/// ```swift
/// @Reducer
/// struct MyReducer {
///     struct State { ... }
///     enum When { ... }
///     static func update(...) { ... }
/// }
/// ```
///
/// Generates:
/// - Nested `Store` class conforming to Statostore, ObservableObject, and Injectable
/// - @Superscope/@Subscope properties matching @SuperState/@SubState in State
/// - Smart state getter/setter that injects bindings and wires children
/// - Bridge to static update() method
/// - Allows Reducer to be nested in namespaces (e.g., inside enums)
@attached(member, names: named(Store))
@attached(extension, conformances: Reducer)
public macro Reducer() = #externalMacro(module: "StatoscopeMacros", type: "ReducerMacro")
