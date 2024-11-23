//
//  StoreTestPlan.swift
//  
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

enum TestPlanErrors: Error {
    case unwrappingNonOptionalSubscope
}

public class StoreTestPlan<T: ScopeImplementation> {
    
    let given: () throws -> T
    internal var steps: [(T) throws -> Void] = []
    internal var forks: [StoreTestPlan<T>] = []
    internal var clearEffectsOnWhen: ClearEffects = .none
    
    public init(given: @escaping () throws -> T) {
        self.given = given
    }

    func addStep(_ step: @escaping (T) throws -> Void) -> Self {
        steps.append(step)
        return self
    }
    
    func buildLinkedFork(file: StaticString = #file, line: UInt = #line) -> StoreTestPlan<T> {
        let forkedPlan = StoreTestPlan(forkingParent: self)
        forks.append(forkedPlan)
        return forkedPlan
    }
    private init<F: StoreTestPlan<T>>(forkingParent parent: F) {
        self.given = parent.given
        self.steps = parent.steps
    }

    var snapshot: ((T) -> Void)?

    // Possible parameters
    //  1.- Taking screenshots
    //   1.1.- Record screenshots
    //  2.- Memory release check
    //  3.- Force check effects after every WHEN? WHEN is the "clear" trigger!
    //  4.- ? TODO:
    // TODO: put some test failure in place in case someone forgets to write runTest
    public func runTest(
        file: StaticString = #file, line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        try runAllSteps(file: file, line: line, assertRelease: assertRelease)
        try forks.forEach { childFlow in
            childFlow.snapshot = snapshot
            try childFlow.runTest(file: file, line: line, assertRelease: assertRelease)
        }
    }
    
    public func configure(clearEffectsOnEveryWhenOrEnd: ClearEffects) -> Self {
        self.clearEffectsOnWhen = clearEffectsOnEveryWhenOrEnd
        return self
    }

    private func runAllSteps(
        file: StaticString,
        line: UInt,
        assertRelease: Bool
    ) throws {
        func runner(
            file: StaticString,
            line: UInt
        ) throws -> T {
            let sut: T = try given()
            snapshot?(sut)
            for step in steps {
                try step(sut)
                snapshot?(sut)
            }
            sut.clear(clearEffectsOnWhen, scope: sut)
            sut.assertNoDeepEffects(file: file, line: line)
            return sut
        }
        if assertRelease {
            try assertChildScopesReleased(file: file, line: line) {
                try runner(file: file, line: line)
            }
        } else {
            _ = try runner(file: file, line: line)
        }
    }
}

internal extension ScopeImplementation {
    @discardableResult
    func when<Subscope: ScopeImplementation>(
        childScope: Subscope,
        file: StaticString = #file,
        line: UInt = #line,
        _ whens: [Subscope.When]
    ) throws -> Self {
        // assertNoDeepEffects(file: file, line: line)
        try whens.forEach {
            childScope.effectsState.reset(scope: self)
            try childScope._unsafeSendImplementation($0)
        }
        return self
    }
}

public class WithStoreTestPlan<W: ScopeImplementation, S: ScopeImplementation>: StoreTestPlan<W> {
    public let parentPlan: StoreTestPlan<S>
    public let keyPath: KeyPath<S, W>
    public let file: StaticString
    public let line: UInt

    internal init(
        parent: StoreTestPlan<S>,
        keyPath: KeyPath<S, W>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        self.parentPlan = parent
        self.keyPath = keyPath
        self.file = file
        self.line = line
        super.init {
            fatalError("This is never called")
        }
    }
    
    override func addStep(_ step: @escaping (W) throws -> Void) -> Self {
        _ = parentPlan.addStep { [keyPath] sut in
            try step(sut[keyPath: keyPath])
        }
        return self
    }
    
    override func buildLinkedFork(file: StaticString = #file, line: UInt = #line) -> WithStoreTestPlan<W, S> {
        let forkedPlan = self.parentPlan.buildLinkedFork(file: file, line: line)
        return forkedPlan.WITH(self.keyPath)
    }
    
    func POP() -> StoreTestPlan<S> {
        return parentPlan
    }
    
    override public func runTest(
        file: StaticString = #file, line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        try POP()
            .runTest(file: file, line: line, assertRelease: assertRelease)
    }
}

public class WithOptStoreTestPlan<W: ScopeImplementation, S: ScopeImplementation>: StoreTestPlan<W> {
    public let parentPlan: StoreTestPlan<S>
    public let keyPath: KeyPath<S, W?>
    public let file: StaticString
    public let line: UInt

    internal init(
        parent: StoreTestPlan<S>,
        keyPath: KeyPath<S, W?>,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        self.keyPath = keyPath
        self.parentPlan = parent
        self.file = file
        self.line = line
        super.init {
            fatalError("This is never called")
        }
    }
    
    override func addStep(_ step: @escaping (W) throws -> Void) -> Self {
        _ = parentPlan.addStep { [keyPath, file, line] sut in
            guard let childScope: W = sut[keyPath: keyPath] else {
                XCTFail("WITH: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: W.self)) : \(type(of: W.self))",
                        file: file, line: line)
                throw TestPlanErrors.unwrappingNonOptionalSubscope
            }
            try step(childScope)
        }
        return self
    }
        
    override func buildLinkedFork(file: StaticString = #file, line: UInt = #line) -> WithOptStoreTestPlan<W, S> {
        let forkedPlan = self.parentPlan.buildLinkedFork(file: file, line: line)
        return forkedPlan.WITH(self.keyPath)
    }

    public func POP() -> StoreTestPlan<S> {
        return parentPlan
    }
    
    override public func runTest(file: StaticString = #file, line: UInt = #line, assertRelease: Bool = false) throws {
        try parentPlan.runTest(file: file, line: line, assertRelease: assertRelease)
    }
}
