//
//  StoreTestPlan+EffectsFork.swift
//  Statoscope
//
//  Created by Sergi Hernanz on 22/11/24.
//

import Foundation
@_spi(SCT) import Statoscope
import XCTest

// Effect + Fork
extension StoreTestPlan {

    @discardableResult
    public func FORK_EffectCompletes<EffectType: Effect>(
        _ expectedEffect: EffectType.Type,
        with effectResult: EffectType.ResultType,
        file: StaticString = #file,
        line: UInt = #line,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN_EffectCompletes(expectedEffect, with: effectResult, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }
    
    @discardableResult
    public func FORK_EffectFails<EffectType: Effect>(
        _ expectedEffect: EffectType.Type,
        with effectResult: Error,
        file: StaticString = #file,
        line: UInt = #line,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN_EffectFails(expectedEffect, with: effectResult, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }
    
    @discardableResult
    public func FORK_OlderEffectCompletes(
        with effectResult: T.When,
        file: StaticString = #file,
        line: UInt = #line,
        _ elseFlow: (StoreTestPlan<T>) throws -> StoreTestPlan<T>
    ) throws -> Self {
        let elseTestPlan = buildLinkedFork(file: file, line: line)
        try elseTestPlan.WHEN_OlderEffectCompletes(with: effectResult, file: file, line: line)
        _ = try elseFlow(elseTestPlan)
        return self
    }
}
