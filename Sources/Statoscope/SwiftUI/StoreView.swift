//
//  StoreView.swift
//  
//
//  Created by Sergi Hernanz on 4/2/24.
//

import Foundation
import SwiftUI

public protocol StoreViewProtocol: View {
    associatedtype State
    associatedtype When
    var model: State { get }
    var send: (When) -> Void { get }
    init(model: State, send: @escaping (When) -> Void)
}

struct StoreView<S: StoreProtocol, V: View>: View where S.ScopeImpl: ObservableObject {
    @ObservedObject var state: S.ScopeImpl
    let scope: S
    let view: V
    init(scope: S, @ViewBuilder view: (S.ScopeImpl, @escaping (S.ScopeImpl.When) -> Void) -> V) {
        self.scope = scope
        self.state = scope._scopeImpl
        self.view = view(scope._scopeImpl, { scope.send($0) })
    }
    var body: some View {
        view
    }
}

// MARK: - Binding helpers for StoreViewProtocol

public extension StoreViewProtocol {

    func bind<T>(
        constant: T,
        _ when: @escaping (T) -> When
    ) -> Binding<T> {
        bind({ _ in constant }, when)
    }

    func bind<T>(
        _ keyPath: KeyPath<State, T>,
        _ when: @escaping (T) -> When
    ) -> Binding<T> {
        bind({ $0.model[keyPath: keyPath] }, when)
    }

    func weakBind<T>(
        _ keyPath: KeyPath<State, T>,
        _ when: @escaping (T) -> When
    ) -> Binding<T> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { send(when($0)) }
        )
    }

    func bind<T>(
        _ getter: @escaping (Self) -> T,
        _ when: @escaping (T) -> When
    ) -> Binding<T> {
        Binding(
            get: { getter(self) },
            set: { send(when($0)) }
        )
    }

    func bindIsPresented<T>(
        _ keyPath: KeyPath<State, T?>
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] != nil },
            set: { _ in }
        )
    }

    func bindIsPresented<T>(
        _ keyPath: KeyPath<State, T?>,
        _ when: @escaping (Bool) -> When
    ) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] != nil },
            set: { send(when($0)) }
        )
    }
}

extension StoreProtocol where Self: AnyObject {
    func buildStoreView<V: View>(
        @ViewBuilder view: (Self.ScopeImpl, @escaping (Self.ScopeImpl.When) -> Void) -> V
    ) -> StoreView<Self, V> {
        StoreView(scope: self, view: view)
    }
    func buildStoreView<V: StoreViewProtocol>(_ type: V.Type) -> StoreView<Self, V>
        where V.State == Self.ScopeImpl, V.When == Self.ScopeImpl.When {
        StoreView(scope: self, view: { V(model: $0, send: $1) })
    }
}
