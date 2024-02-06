//
//  File.swift
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
    ) throws -> StoreTestPlan<T> {
        let elseTestPlan = StoreTestPlan(parent: self)
        forks.append(elseTestPlan)
        try elseTestPlan.WHEN(file: file, line: line, elseWhen)
        _ = try elseFlow(elseTestPlan)
        return self
    }

}

