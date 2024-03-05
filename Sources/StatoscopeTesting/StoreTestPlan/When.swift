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
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: T.When...
    ) throws -> Self {
        try privateWHEN(clearEffects: clearEffects, file: file, line: line, whens)
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: Subscope.When...
    ) throws -> Self {
        try privateWHEN(keyPath, clearEffects: clearEffects, file: file, line: line, whens)
    }

    @discardableResult
    public func WHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope?>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: Subscope.When...
    ) throws -> Self {
        try privateWHEN(keyPath, clearEffects: clearEffects, file: file, line: line, whens)
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
            XCTAssertThrowsError(try sut.sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addStep { sut in
            sut.effectsState.clear(clearEffects)
            XCTAssertThrowsError(try sut.storeState[keyPath: keyPath].sendUnsafe(when), file: file, line: line)
        }
    }

    @discardableResult
    public func throwsWHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope?>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ when: Subscope.When
    ) throws -> Self {
        addStep { sut in
            guard let childScope = sut.storeState[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffects)
            XCTAssertThrowsError(try childScope.sendUnsafe(when), file: file, line: line)
        }
    }
}

extension StoreTestPlan {

    @discardableResult
    public func AND(
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: T.When...
    ) throws -> Self {
        try privateWHEN(clearEffects: .none, file: file, line: line, whens)
    }

    @discardableResult
    public func AND<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope>,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: Subscope.When...
    ) throws -> Self {
        try privateWHEN(keyPath, clearEffects: .none, file: file, line: line, whens)
    }

    @discardableResult
    public func AND<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope?>,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: Subscope.When...
    ) throws -> Self {
        try privateWHEN(keyPath, clearEffects: .none, file: file, line: line, whens)
    }
}

private extension StoreTestPlan {

    func privateWHEN(
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: [T.When]
    ) throws -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            try whens.forEach {
                sut.effectsState.clear(clearEffects)
                try sut.sendUnsafe($0)
            }
        }
    }

    @discardableResult
    func privateWHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: [Subscope.When]
    ) throws -> Self {
        addStep { sut in
            let child = sut.storeState[keyPath: keyPath]
            child.effectsState.clear(clearEffects)
            try sut.when(childScope: child, file: file, line: line, whens)
        }
    }

    @discardableResult
    func privateWHEN<Subscope: StoreProtocol>(
        _ keyPath: KeyPath<T.StoreState, Subscope?>,
        clearEffects: ClearEffects = .all,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: [Subscope.When]
    ) throws -> Self {
        addStep { sut in
            guard let childScope = sut.storeState[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            childScope.effectsState.clear(clearEffects)
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }

}
