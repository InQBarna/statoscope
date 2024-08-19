//
//  StoreTestPlan.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope

extension StoreTestPlan {

    @discardableResult
    public func FORK(
        file: StaticString = #file, line: UInt = #line,
        _ elseWhen: T.When,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN(elseWhen, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }

    @discardableResult
    public func FORK<Subscope: ScopeImplementation>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, Subscope>,
        _ elseWhen: Subscope.When,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN(keyPath, elseWhen, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }

    @discardableResult
    public func FORK<Subscope: ScopeImplementation>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, Subscope?>,
        _ elseWhen: Subscope.When,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN(keyPath, elseWhen, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }
}
