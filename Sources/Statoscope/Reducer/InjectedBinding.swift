//
//  InjectedBinding.swift
//  Statoscope
//

import Foundation

/// A binding that lazily resolves an Injectable dependency from the injection tree
///
/// Used with `@ReducerInjected` to declare dependencies directly on a Reducer's
/// State struct. The `@Reducer` macro generates injection code in the Store's
/// state getter so the binding resolves from the live injection tree at access time.
///
/// ## Example:
/// ```swift
/// @Reducer
/// struct MyReducer {
///     struct State {
///         var count: Int = 0
///         @ReducerInjected var logger: Logger
///     }
///
///     static func update(
///         _ when: When,
///         state: inout State,
///         effectsState: inout EffectsState<When>,
///         dependencies: ReducerDependencies
///     ) throws {
///         state.logger.log("Processing \(when)")  // resolved from injection tree
///         state.count += 1
///     }
/// }
/// ```
///
/// The `logger` property returns `Logger.defaultValue` until the Store is wired
/// into an injection tree (e.g., during init or in tests).
@dynamicMemberLookup
public struct InjectedBinding<T: Injectable> {
    private let getter: () -> T

    /// Creates a binding with a custom resolution closure
    public init(get: @escaping () -> T) {
        self.getter = get
    }

    /// The resolved dependency value
    public var wrappedValue: T {
        getter()
    }

    /// Default binding that always returns `T.defaultValue`
    ///
    /// Used as initial value before the Store wires the live injection tree.
    public static var defaultValue: InjectedBinding<T> {
        InjectedBinding { T.defaultValue }
    }

    /// Access the resolved value's properties directly
    ///
    /// Allows `state.logger.someProperty` instead of `state.logger.wrappedValue.someProperty`
    public subscript<U>(dynamicMember keyPath: KeyPath<T, U>) -> U {
        wrappedValue[keyPath: keyPath]
    }
}

// MARK: - InjectionTreeNode helper

extension InjectionTreeNode {
    /// Resolves a dependency for use in `@ReducerInjected` bindings.
    ///
    /// This is the public counterpart to `_resolve()` for use by macro-generated
    /// `InjectedBinding` closures, which live in the user's module and cannot
    /// access `@_spi(SCT)` APIs directly.
    ///
    /// Returns `T.defaultValue` if the dependency cannot be found in the tree.
    public func resolveForBinding<T: Injectable>() -> T {
        _resolve()
    }
}

// MARK: - Equatable

extension InjectedBinding: Equatable where T: Equatable {
    public static func == (lhs: InjectedBinding<T>, rhs: InjectedBinding<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// MARK: - Hashable

extension InjectedBinding: Hashable where T: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(wrappedValue)
    }
}
