//
//  StatoscopeTesting.swift
//
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
import Statoscope

// OTher methods to be moved to the right files

extension ScopeImplementation {
    @discardableResult
    func assertNoDeepEffects(_ message: String? = nil, file: StaticString = #file, line: UInt = #line) -> Self {
        let deepEffects = allDeepOngoingEffects().filter({ $0.value.count > 0 })
        if deepEffects.values.flatMap({ $0 }).count > 0 {
            XCTFail(message ?? "Should have 0 deep effects, found \(deepEffects)", file: file, line: line)
        }
        return self
    }
}

extension StoreTestPlan {
    
    /*
    @discardableResult
    public func WITH_v0<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        file: StaticString = #file, line: UInt = #line,
        _ with: @escaping (_ sut: StoreTestPlan<Subscope>) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            // TODO: WITH is not compatible with snapshot for now and other features of StoreTestPlan
            let withTestPlan: StoreTestPlan<Subscope> = StoreTestPlan<Subscope>(parent: self, sut: sut, keyPath: keyPath)
            try with(withTestPlan)
            try withTestPlan.runTest()
        }
    }

    @discardableResult
    public func WITH_v0<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        file: StaticString = #file, line: UInt = #line,
        _ with: @escaping (_ sut: StoreTestPlan<Subscope>) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            // TODO: WITH is not compatible with snapshot for now and other features of StoreTestPlan
            let withTestPlan: StoreTestPlan<Subscope> = StoreTestPlan<Subscope>(parent: self, sut: sut, keyPath: keyPath)
            try with(withTestPlan)
            try withTestPlan.runTest()
        }
    }
    */
    
    @discardableResult
    public func WITH<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        file: StaticString = #file, line: UInt = #line
    ) -> WithStoreTestPlan<Subscope, T> {
        WithStoreTestPlan<Subscope, T>(
            parent: self,
            keyPath: keyPath
        )
    }

    @discardableResult
    public func WITH<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        file: StaticString = #file, line: UInt = #line
    ) -> WithOptStoreTestPlan<Subscope, T> {
        WithOptStoreTestPlan<Subscope, T>(
            parent: self,
            keyPath: keyPath
        )
    }
}
