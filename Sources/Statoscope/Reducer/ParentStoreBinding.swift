//
//  ParentStoreBinding.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 09/03/26.
//

import Foundation
import Combine

/// A binding to a parent Statostore (for incremental migration)
///
/// Provides read access to the parent Statostore instance resolved from the injection tree.
/// Used by `@SuperScope` in Reducer.State to reference an unmigrated parent Statostore.
///
/// The parent store must conform to `Injectable & ObservableObject`.
///
/// ## Example:
/// ```swift
/// // Parent: not yet migrated to Reducer
/// final class ParentStore: Statostore, ObservableObject, Injectable {
///     static var defaultValue: ParentStore { ParentStore() }
///     @Published var count: Int = 0
/// }
///
/// // Child: migrated to Reducer, references legacy parent
/// struct ChildReducer {
///     struct State {
///         @SuperScope(observed: true) var parent: ParentStore
///         var doubled: Int = 0
///     }
///     enum When { case sync }
///     static func update(
///         _ when: When,
///         state: inout State,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies,
///         scopeLinks: inout NoScopeLinks
///     ) throws {
///         switch when {
///         case .sync:
///             state.doubled = state.parent.count * 2
///         }
///     }
/// }
/// ```
@dynamicMemberLookup
public struct ParentStoreBinding<Store: Injectable & ObservableObject> {
    private let getter: () -> Store

    /// Creates a binding with a getter closure
    public init(get: @escaping () -> Store) {
        self.getter = get
    }

    /// The current parent store instance
    public var wrappedValue: Store {
        getter()
    }

    /// Default value that returns `Injectable.defaultValue`
    ///
    /// Used as the initial value for the generated storage property:
    /// ```swift
    /// var _$parent: ParentStoreBinding<ParentStore> = .defaultValue
    /// ```
    public static var defaultValue: ParentStoreBinding<Store> {
        ParentStoreBinding { Store.defaultValue }
    }

    /// Access the parent store's properties directly
    public subscript<T>(dynamicMember keyPath: KeyPath<Store, T>) -> T {
        wrappedValue[keyPath: keyPath]
    }
}

// MARK: - Equatable

extension ParentStoreBinding: Equatable where Store: Equatable {
    public static func == (lhs: ParentStoreBinding<Store>, rhs: ParentStoreBinding<Store>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// MARK: - Hashable

extension ParentStoreBinding: Hashable where Store: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
