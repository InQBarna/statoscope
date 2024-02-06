//
//  File.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
import Statoscope

// OTher methods to be moved to the right files

extension StoreProtocol {
    @discardableResult
    func assertNoDeepEffects(_ message: String? = nil, file: StaticString = #file, line: UInt = #line) -> Self {
        let deepEffects = allDeepPendingEffects().filter({ $0.value.count > 0 })
        if deepEffects.values.flatMap({ $0 }).count > 0 {
            XCTFail(message ?? "Should have 0 deep effects, found \(deepEffects)", file: file, line: line)
        }
        return self
    }
}

extension StoreTestPlan {
    @discardableResult
    public func WITH<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.State, Subscope>,
        file: StaticString = #file, line: UInt = #line,
        _ with: @escaping (_ sut: Subscope) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            try with(sut.state[keyPath: keyPath])
        }
    }
}
