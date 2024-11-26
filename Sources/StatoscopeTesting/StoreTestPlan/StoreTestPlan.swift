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

internal enum StepType {
    case when(String?)
    case then
    case snapshot
}

internal struct Step<S: ScopeImplementation> {
    let type: StepType
    let run: (S) throws -> Void
}

public class StoreTestPlan<T: ScopeImplementation> {
    
    let given: () throws -> T
    internal var steps: [Step<T>] = []
    internal var forks: [StoreTestPlan<T>] = []
    internal var clearEffectsOnWhen: ClearEffects = .none
    
    private let initLine: UInt
    private let initFile: StaticString
    private let isAFork: Bool
    public init(file: StaticString = #file, line: UInt = #line, given: @escaping () throws -> T) {
        self.given = given
        self.initLine = line
        self.initFile = file
        self.isAFork = false
    }

    func addStep(_ step: Step<T>) -> Self {
        steps.append(step)
        return self
    }
    
    func buildLinkedFork(file: StaticString = #file, line: UInt = #line) -> StoreTestPlan<T> {
        let forkedPlan = StoreTestPlan(file: file, line: line, forkingParent: self)
        forks.append(forkedPlan)
        return forkedPlan
    }
    private init<F: StoreTestPlan<T>>(file: StaticString = #file, line: UInt = #line, forkingParent parent: F) {
        self.given = parent.given
        self.steps = parent.steps
        self.initFile = file
        self.initLine = line
        self.isAFork = true
    }

    var snapshot: ((T, String?) -> Void)?
    private var takingSnapshot = false
    private var takingSnapshotSafeScopes: [WeakScopeBox] = []

    // Possible parameters
    //  1.- Taking screenshots
    //   1.1.- Record screenshots
    //  2.- Memory release check
    //  3.- Force check effects after every WHEN? WHEN is the "clear" trigger!
    //  4.- ? TODO:
    private var ransExecuted = 0
    public func runTest(
        file: StaticString = #file, line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        guard ransExecuted == 0 else {
            return XCTFail("‼️ Don't call runTest() more than once ‼️", file: file, line: line)
        }
        guard !isAFork else {
            return XCTFail("‼️ Don't call runTest() on a forked StoreTestPlan ‼️", file: file, line: line)
        }
        try uncheckedRunTest(file: file, line: line, assertRelease: assertRelease)
    }

    private func uncheckedRunTest(
        file: StaticString = #file, line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        ransExecuted = ransExecuted + 1
        try runAllSteps(file: file, line: line, assertRelease: assertRelease)
        try forks.forEach { childFlow in
            childFlow.snapshot = snapshot
            try childFlow.uncheckedRunTest(file: file, line: line, assertRelease: assertRelease)
        }
    }
    
    deinit {
        guard ransExecuted == 0,
              type(of: self) == StoreTestPlan<T>.self else {
            return
        }
        XCTFail("‼️ Don't forget to call runTest() at the end of the test plan ‼️", file: initFile, line: initLine)
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
            safeSnapshot(sut: sut, name: "GIVEN")
            for step in steps {
                try step.run(sut)
                switch step.type {
                case .when(let whenName):
                    safeSnapshot(sut: sut, name: nil)
                default:
                    break
                }
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

private extension ScopeImplementation {
    @discardableResult
    func addErasedMiddleWare(_ update: @escaping (Self, Any, (Any) throws -> Void) throws -> Void) -> Self {
        addMiddleWare { scope, when, forward in
            try update(scope, when) { receivedWhen in
                guard let typedWhen = receivedWhen as? When else {
                    fatalError()
                }
                try forward(typedWhen)
            }
        }
    }
}

internal extension StoreTestPlan {
    func safeSnapshot(sut: T, name: String?) {
        // Block any message such as the ones received onAppear
        defer {
            takingSnapshot = false
            takingSnapshotSafeScopes = takingSnapshotSafeScopes.filter { $0.scope == nil }
        }
        let allScopes: [any ScopeImplementation] = [sut] + sut._allChildScopes()
        allScopes.forEach { scope in
            if nil == takingSnapshotSafeScopes.first(where: { $0.scope === scope }) {
                scope.addErasedMiddleWare { [weak self] scope, when, forward in
                    guard let self else { return }
                    if !self.takingSnapshot {
                        try forward(when)
                    }
                }
                takingSnapshotSafeScopes.append(WeakScopeBox(scope: scope))
            }
        }
        takingSnapshot = true
        // Take snapshot
        snapshot?(sut, name)
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
    
    override func addStep(_ step: Step<W>) -> Self {
        _ = parentPlan.addStep(
            Step(type: step.type) { [keyPath] sut in
                try step.run(sut[keyPath: keyPath])
            }
        )
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
    
    override func addStep(_ step: Step<W>) -> Self {
        _ = parentPlan.addStep(
            Step(type: step.type) { [keyPath, file, line] sut in
                guard let childScope: W = sut[keyPath: keyPath] else {
                    XCTFail("WITH: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                            " \(type(of: W.self)) : \(type(of: W.self))",
                            file: file, line: line)
                    throw TestPlanErrors.unwrappingNonOptionalSubscope
                }
                try step.run(childScope)
            }
        )
        return self
    }
        
    override func buildLinkedFork(file: StaticString = #file, line: UInt = #line) -> WithOptStoreTestPlan<W, S> {
        let forkedPlan = self.parentPlan.buildLinkedFork(file: file, line: line)
        return forkedPlan.WITH(self.keyPath)
    }

    public func POP() -> StoreTestPlan<S> {
        return parentPlan
    }
    
    override public func runTest(
        file: StaticString = #file,
        line: UInt = #line,
        assertRelease: Bool = false
    ) throws {
        try parentPlan.runTest(file: file, line: line, assertRelease: assertRelease)
    }
}
