//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

public func GIVEN<Store: StoreProtocol>(
    _ builder: @escaping () throws -> Store
) rethrows -> StoreTestPlan<Store> {
    StoreTestPlan(given: builder)
}

public func GIVEN_spec<ScopeType: Scope>(
    _ builder: @escaping () throws -> ScopeType
) rethrows -> StoreTestPlan<DummyStore<ScopeType>> {
    StoreTestPlan() {
        DummyStore(state: try builder())
    }
}

extension StoreProtocol {
    public static func GIVEN(_ builder: @escaping () throws -> Self) rethrows -> StoreTestPlan<Self> {
        StoreTestPlan(given: builder)
    }
}

extension Scope {
    public static func GIVEN_spec(_ builder: @escaping () throws -> Self) rethrows -> StoreTestPlan<DummyStore<Self>> {
        StoreTestPlan() {
            DummyStore(state: try builder())
        }
    }
}

final public class DummyStore<State: Scope>: StoreProtocol {
    public var state: State
    public typealias When = State.When
    
    init(state: State) {
        self.state = state
    }
    
    public func update(_ when: State.When) throws {
        XCTFail("not implemented")
    }
    
}
