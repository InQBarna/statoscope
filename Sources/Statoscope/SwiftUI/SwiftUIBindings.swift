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
        _ kp: KeyPath<Self, Optional<T>>,
        _ when: ((Bool) -> ScopeType.When)? = nil
    ) -> Binding<Bool> {
        guard let when = when else {
            return Binding(
                get: { [weak self] in self?[keyPath: kp] != nil },
                set: { _ in return }
            )
        }
        return Binding(
            get: { [weak self] in self?[keyPath: kp] != nil },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
    public func bindBool(_ kp: KeyPath<Self, Bool>) -> Binding<Bool> {
        return Binding(
            get: { [weak self] in self?[keyPath: kp] ?? false },
            set: { _ in }
        )
    }
}

extension StoreProtocol where Self: AnyObject {
    public func bind<T>(
        _ kp: KeyPath<Self, T>,
        _ when: @escaping (T) -> ScopeType.When
    ) -> Binding<T> {
        Binding(
            get: { self[keyPath: kp] },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
    
    public func weakBind<T>(
        _ kp: KeyPath<Self, T>,
        _ when: @escaping (T) -> ScopeType.When,
        defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: { [weak self] in self?[keyPath: kp] ?? defaultValue },
            set: { [weak self] in self?.send(when($0)) }
        )
    }
}

public func ??<T>(lhs: Binding<Optional<T>>, rhs: T) -> Binding<T> {
    Binding(
        get: { lhs.wrappedValue ?? rhs },
        set: { lhs.wrappedValue = $0 }
    )
}
