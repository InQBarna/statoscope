//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 29/1/24.
//

import Foundation
import XCTest
import Statoscope

struct WeakScopeBox {
    weak var scope: (any Scope)?
}

extension StoreProtocol {
    func allChildScopesChecker() -> [WeakScopeBox] {
        allChildScopes().map { WeakScopeBox(scope: $0.state) }
    }
}

extension Sequence where Element == WeakScopeBox {
    func assertAllReleased(file: StaticString = #file, line: UInt = #line) {
        // Some UIHostingController need runloop steps to be released...
        RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        RunLoop.current.run(until: Date().addingTimeInterval(0.001))
        let unreleased = compactMap { $0.scope }
        if unreleased.count > 0 {
            XCTFail("Some scopes have not been released: \(unreleased)", file: file, line: line)
        }
    }
}

func assertChildScopesReleased(
    file: StaticString = #file,
    line: UInt = #line,
    _ rootScope: () throws -> any StoreProtocol
) rethrows {
    try autoreleasepool {
        try rootScope()
            .allChildScopesChecker()
    }
    .assertAllReleased(file: file, line: line)
}
