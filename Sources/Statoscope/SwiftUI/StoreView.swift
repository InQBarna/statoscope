//
//  StoreView.swift
//  
//
//  Created by Sergi Hernanz on 4/2/24.
//

import Foundation
import SwiftUI

public protocol StoreViewProtocol {
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
        self.state = scope.scopeImpl
        self.view = view(scope.scopeImpl, { scope.send($0) })
    }
    var body: some View {
        view
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
