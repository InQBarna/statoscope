//
//  Given.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

public func GIVEN<Store: ScopeImplementation>(
    _ builder: @escaping () throws -> Store
) rethrows -> StoreTestPlan<Store> {
    StoreTestPlan(given: builder)
}

extension ScopeImplementation {
    public static func GIVEN(
        file: StaticString = #file,
        line: UInt = #line,
        _ builder: @escaping () throws -> Self
    ) rethrows -> StoreTestPlan<Self> {
        StoreTestPlan(file: file, line: line, given: builder)
    }
}
