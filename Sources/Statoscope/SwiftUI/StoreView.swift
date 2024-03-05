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

struct StoreView<S: StoreProtocol, V: View>: View where S.StoreState: ObservableObject {
    @ObservedObject var state: S.StoreState
    let scope: S
    let view: V
    init(scope: S, @ViewBuilder view: (S.StoreState, @escaping (S.When) -> Void) -> V) {
        self.scope = scope
        self.state = scope.storeState
        self.view = view(scope.storeState, { scope.send($0) })
    }
    var body: some View {
        view
    }
}

extension StoreImplementation where Self: AnyObject {
    func buildStoreView<V: View>(
        @ViewBuilder view: (Self.StoreState, @escaping (Self.When) -> Void) -> V
    ) -> StoreView<Self, V> {
        StoreView(scope: self, view: view)
    }
    func buildStoreView<V: StoreViewProtocol>(_ type: V.Type) -> StoreView<Self, V>
        where V.State == Self.StoreState, V.When == Self.When {
        StoreView(scope: self, view: { V(model: $0, send: $1) })
    }
}
