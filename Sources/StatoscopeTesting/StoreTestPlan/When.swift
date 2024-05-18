//
//  When.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

public enum ClearEffects {
    case all
    case none
    case some((any Effect) -> Bool)
}

extension EffectsState {
    mutating func clear(_ clearEffects: ClearEffects) {
        switch clearEffects {
        case .none:
            return
        case .all:
            reset()
        case .some(let filter):
            reset(clearing: filter)
        }
    }
}

extension StoreTestPlan {

    @discardableResult
    public func WHEN(
        _ when: T.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(when, file: file, line: line)
    }

    @discardableResult
    public func WHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func WHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func throwsWHEN(
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: T.When
    ) -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            sut.effectsState.clear(clearEffects)
            XCTAssertThrowsError(try sut._unsafeSendImplementation(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addStep { sut in
            sut.effectsState.clear(clearEffects)
            XCTAssertThrowsError(try sut[keyPath: keyPath]._unsafeSendImplementation(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffects)
            XCTAssertThrowsError(try childScope._unsafeSendImplementation(when), file: file, line: line)
        }
    }
}

extension StoreTestPlan {

    @discardableResult
    public func AND(
        _ when: T.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(when, file: file, line: line)
    }

    @discardableResult
    public func AND<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }

    @discardableResult
    public func AND<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        try privateWHEN(keyPath, when, file: file, line: line)
    }
}

private extension StoreTestPlan {

    func privateWHEN(
        _ when: T.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        let clearEffectsOnWhen = self.clearEffectsOnWhen
        return addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            sut.effectsState.clear(clearEffectsOnWhen)
            try sut._unsafeSendImplementation(when)
        }
    }

    @discardableResult
    func privateWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        let clearEffectsOnWhen = self.clearEffectsOnWhen
        return addStep { sut in
            let child = sut[keyPath: keyPath]
            child.effectsState.clear(clearEffectsOnWhen)
            try sut.when(childScope: child, file: file, line: line, [when])
        }
    }

    @discardableResult
    func privateWHEN<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ when: Subscope.When,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        let clearEffectsOnWhen = self.clearEffectsOnWhen
        return addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffectsOnWhen)
            try sut.when(childScope: childScope, file: file, line: line, [when])
        }
    }

}
