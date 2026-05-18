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
@attached(member, names: named(Store), named(ChildStores), arbitrary)
@attached(extension, conformances: Reducer, names: arbitrary)
public macro Reducer() = #externalMacro(module: "StatoscopeMacros", type: "ReducerMacro")
