//
//  SwiftUIBindings.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import SwiftUI

extension StoreProtocol where Self: AnyObject {
    public func bindNotNilBool<T>(
        _ keyPath: KeyPath<Self, T?>,
        _ when: ((Bool) -> State.When)? = nil
    ) -> Binding<Bool> {
        guard let when = when else {
            return Binding(
                get: { [weak self] in self?[keyPath: keyPath] != nil },
                set: { _ in return }
            )
        }
        return Binding(
            get: { [weak self] in self?[keyPath: keyPath] != nil },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
    public func bindBool(_ keyPath: KeyPath<Self, Bool>) -> Binding<Bool> {
        return Binding(
            get: { [weak self] in self?[keyPath: keyPath] ?? false },
            set: { _ in }
        )
    }
}

extension StoreProtocol where Self: AnyObject {
    public func bind<T>(
        _ keyPath: KeyPath<Self, T>,
        _ when: @escaping (T) -> State.When
    ) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { [weak self] in self?.send(when($0)) }
        )
    }

    public func weakBind<T>(
        _ keyPath: KeyPath<Self, T>,
        _ when: @escaping (T) -> State.When,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { [weak self] in self?[keyPath: keyPath] ?? defaultValue },
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
