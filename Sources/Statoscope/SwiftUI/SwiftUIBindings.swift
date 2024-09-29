//
//  SwiftUIBindings.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import SwiftUI

public func bind<VS: Sendable, T, When>(
    viewShows: VS,
    _ keyPath: KeyPath<VS, T>,
    _ when: @escaping (T) -> When
) -> Binding<T> {
    Binding(
        get: { viewShows[keyPath: keyPath] },
        set: { _ = when($0) }
    )
}

public func bind<VS: Sendable, When>(
    viewShows: VS,
    _ when: @escaping (VS) -> When
) -> Binding<VS> {
    Binding(
        get: { viewShows },
        set: { _ = when($0) }
    )
}

extension StoreProtocol where Self: AnyObject {
    public func bindNotNilBool<T>(
        _ keyPath: KeyPath<ScopeImpl, T?>,
        _ when: ((Bool) -> ScopeImpl.When)? = nil
    ) -> Binding<Bool> {
        guard let when = when else {
            return Binding(
                get: { [weak self] in self?._scopeImpl[keyPath: keyPath] != nil },
                set: { _ in return }
            )
        }
        return Binding(
            get: { [weak self] in self?._scopeImpl[keyPath: keyPath] != nil },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
    
    public func bindIsPresented<T>(
        _ keyPath: KeyPath<ScopeImpl, T?>,
        _ when: ((T?) -> ScopeImpl.When)? = nil
    ) -> Binding<Bool> {
        guard let when = when else {
            return Binding(
                get: { [weak self] in self?._scopeImpl[keyPath: keyPath] != nil },
                set: { _ in return }
            )
        }
        return Binding(
            get: { [weak self] in self?._scopeImpl[keyPath: keyPath] != nil },
            set: { [weak self] in self?.send( !$0 ? when(nil) : when(self?._scopeImpl[keyPath: keyPath])) }
        )
    }
}

extension StoreProtocol where Self: AnyObject {
    public func bind<T>(
        constant: T,
        _ when: @escaping (T) -> ScopeImpl.When
    ) -> Binding<T> {
        bind(
            { _ in constant },
            when
        )
    }

    public func bind<T>(
        _ keyPath: KeyPath<ScopeImpl, T>,
        _ when: @escaping (T) -> ScopeImpl.When
    ) -> Binding<T> {
        bind(
            { $0._scopeImpl[keyPath: keyPath] },
            when
        )
    }

    public func weakBind<T>(
        _ keyPath: KeyPath<ScopeImpl, T>,
        _ when: @escaping (T) -> ScopeImpl.When,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { [weak self] in self?._scopeImpl[keyPath: keyPath] ?? defaultValue },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
    
    public func bind<T>(
        _ getter: @escaping (Self) -> T,
        _ when: @escaping (T) -> ScopeImpl.When
    ) -> Binding<T> {
        let currentValue = getter(self)
        return Binding(
            get: { [weak self] in
                guard let self else { return currentValue }
                return getter(self)
            },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
}

public func ?? <T>(lhs: Binding<T?>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}
