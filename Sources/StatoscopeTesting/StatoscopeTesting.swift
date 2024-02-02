//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation
import XCTest
import Statoscope

// Sugar a tope
public final class StatoscopeTestPlan<T: Scope> {
    // let sut: T
    let given: () throws -> T
    private var steps: [(T) throws -> Void] = []
    private var forks: [StatoscopeTestPlan<T>] = []
    func addStep(_ step: @escaping (T) throws -> Void) -> Self {
        steps.append(step)
        return self
    }
    
    public init(given: @escaping () throws -> T) {
        self.given = given
    }
    private init(parent: StatoscopeTestPlan<T>) {
        self.given = parent.given
        self.steps = parent.steps
    }
    
    var snapshot: ((T) -> Void)?
    
    // WHEN
    @discardableResult
    public func WHEN(file: StaticString = #file, line: UInt = #line, _ whens: T.When...) throws -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            try whens.forEach {
                sut.clearPending()
                try sut.sendUnsafe($0)
            }
        }
    }
    @discardableResult
    public func WHEN<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope>,
                                      file: StaticString = #file, line: UInt = #line,
                                      _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut[keyPath: keyPath], file: file, line: line, whens)
        }
    }
    @discardableResult
    public func WHEN<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope?>,
                                    file: StaticString = #file, line: UInt = #line,
                                    _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }
    
    // AND: kind of WHEN alias, except for clearing effect (which needs to be re-defined)
    @discardableResult
    public func AND(file: StaticString = #file, line: UInt = #line, _ whens: T.When...) throws -> Self {
        addStep { sut in
            try whens.forEach {
                try sut.sendUnsafe($0)
            }
        }
    }
    @discardableResult
    public func AND<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope>,
                                   file: StaticString = #file, line: UInt = #line,
                                   _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            try sut.when(childScope: sut[keyPath: keyPath], file: file, line: line, whens)
        }
    }
    @discardableResult
    public func AND<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope?>,
                                   file: StaticString = #file, line: UInt = #line,
                                   _ whens: Subscope.When...) throws -> Self {
        addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try sut.when(childScope: childScope, file: file, line: line, whens)
        }
    }
    
    // THEN
    @discardableResult
    public func THEN(
        file: StaticString = #file, line: UInt = #line,
        _ checker: @escaping (_ sut: T) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            try checker(sut)
            // assertNoDeepEffects(file: file, line: line)
            // sut.clearPending()
        }
    }
    
    @discardableResult
    public func THEN<Subscope: Scope>(
        _ keyPath: KeyPath<T, Subscope>,
        file: StaticString = #file, line: UInt = #line,
        checker: @escaping (_ sut: Subscope) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            let childScope = sut[keyPath: keyPath]
            try checker(childScope)
            // childScope.assertNoDeepEffects(file: file, line: line)
            // childScope.clearPending() // only cleared on next WHEN
        }
    }
    @discardableResult
    public func THEN<Subscope: Scope>(
        _ keyPath: KeyPath<T, Subscope?>,
        file: StaticString = #file, line: UInt = #line,
        checker: @escaping (_ sut: Subscope) throws -> Void
    ) rethrows -> Self {
        addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("THEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            try checker(childScope)
            // childScope.assertNoDeepEffects(file: file, line: line)
            // childScope.clearPending() // only cleared on next WHEN
        }
    }
    
    // Possible parameters
    //  1.- Taking screenshots
    //   1.1.- Record screenshots
    //  2.- Memory release check
    //  3.- Force check effects after every WHEN? WHEN is the "clear" trigger!
    //  4.- ?
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
    
    private func runAllSteps(
        file: StaticString,
        line: UInt,
        assertRelease: Bool
    ) throws {
        if assertRelease {
            try assertChildScopesReleased(file: file, line: line) {
                try runAllSteps()
            }
        } else {
            _ = try runAllSteps()
        }
    }
    
    private func runAllSteps() throws -> T {
        let sut: T = try given()
        snapshot?(sut)
        for step in steps {
            try step(sut)
            snapshot?(sut)
        }
        return sut
    }
}

extension Scope {
    public static func GIVEN(_ builder: @escaping () throws -> Self) rethrows -> StatoscopeTestPlan<Self> {
        StatoscopeTestPlan(given: builder)
    }
}

extension StatoscopeTestPlan {
    
    @discardableResult
    public func FORK(
        file: StaticString = #file, line: UInt = #line,
        _ elseWhen: T.When,
        _ elseFlow: (StatoscopeTestPlan<T>) throws -> StatoscopeTestPlan<T>
    ) throws -> StatoscopeTestPlan<T> {
        let elseTestPlan = StatoscopeTestPlan(parent: self)
        forks.append(elseTestPlan)
        try elseTestPlan.WHEN(file: file, line: line, elseWhen)
        _ = try elseFlow(elseTestPlan)
        return self
    }
}

extension StatoscopeTestPlan {
    @discardableResult
    public func THEN<AcceptableKP: Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP>,
        equals expectedValue: AcceptableKP
    ) throws -> Self {
        addStep { sut in
            XCTAssertEqual(sut[keyPath: keyPath], expectedValue, file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.clearPending() // only cleared on next WHEN
        }
    }
    
    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNotNil(sut[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.clearPending() // only cleared on next WHEN
        }
    }
    
    @discardableResult
    public func THEN_NotNil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNotNil(sut[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.clearPending() // only cleared on next WHEN
        }
    }
    
    @discardableResult
    public func THEN_Nil<AcceptableKP>(
        file: StaticString = #file, line: UInt = #line,
        _ keyPath: KeyPath<T, AcceptableKP?>
    ) throws -> Self {
        addStep { sut in
            XCTAssertNil(sut[keyPath: keyPath], file: file, line: line)
            // assertNoDeepEffects(file: file, line: line)
            // sut.clearPending() // only cleared on next WHEN
        }
    }
    
    @discardableResult
    public func ThrowsWHEN(file: StaticString = #file, line: UInt = #line, _ when: T.When) -> Self {
        addStep { sut in
            // assertNoDeepEffects(file: file, line: line)
            sut.clearPending()
            XCTAssertThrowsError(try sut.sendUnsafe(when), file: file, line: line)
        }
    }
    @discardableResult
    public func ThrowsWHEN<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope>,
                                            file: StaticString = #file, line: UInt = #line,
                                            _ when: Subscope.When) throws -> Self {
        addStep { sut in
            sut.clearPending()
            XCTAssertThrowsError(try sut[keyPath: keyPath].sendUnsafe(when), file: file, line: line)
        }
    }
    @discardableResult
    public func ThrowsWHEN<Subscope: Scope>(_ keyPath: KeyPath<T, Subscope?>,
                                            file: StaticString = #file, line: UInt = #line,
                                            _ when: Subscope.When) throws -> Self {
        addStep { sut in
            guard let childScope = sut[keyPath: keyPath] else {
                XCTFail("WHEN: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                        " \(type(of: T.self)) : \(type(of: Subscope.self))",
                        file: file, line: line)
                return
            }
            XCTAssertThrowsError(try childScope.sendUnsafe(when), file: file, line: line)
        }
    }
}

extension Scope {
    @discardableResult
    fileprivate func when<Subscope: Scope>(childScope: Subscope,
                                           file: StaticString = #file, line: UInt = #line,
                                           _ whens: [Subscope.When]) throws -> Self {
        // assertNoDeepEffects(file: file, line: line)
        try whens.forEach {
            childScope.clearPending()
            try childScope.sendUnsafe($0)
        }
        return self
    }
}

// MARK: THEN
/*

// MARK - assert effects
extension ScopeProtocol {
    @discardableResult
    func assertNoDeepEffects(_ message: String? = nil, file: StaticString = #file, line: UInt = #line) -> Self {
        let deepEffects = allDeepPendingEffects().filter({ $0.value.count > 0 })
        if deepEffects.values.flatMap({ $0 }).count > 0 {
            XCTFail(message ?? "Should have 0 deep effects, found \(deepEffects)", file: file, line: line)
        }
        return self
    }
}

extension Scope {
    @discardableResult
    func WITH<Subscope: Scope>(_ keyPath: KeyPath<Self, Subscope?>,
                               file: StaticString = #file, line: UInt = #line,
                               with: (Subscope) throws -> Void) rethrows -> Self {
        guard let childScope = self[keyPath: keyPath] else {
            XCTFail("WITH: Non existing model in first parameter: error unwrapping expecte non-nil subscope" +
                    " \(type(of: Self.self)) : \(type(of: Subscope.self))",
                    file: file, line: line)
            return self
        }
        try with(childScope)
        return self
    }
}
 */

public func XCTAssertEffectsInclude<S, T2>(
    _ expression1: @autoclosure () throws -> S?,
    _ expression2: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) where S: Scope, T2: Effect {
    do {
        let sut = try expression1()
        let expected = try expression2()
        guard let effs = sut?.effects else {
            XCTFail("Effects on NIL sut \(type(of: sut)) do not include \(expected)", file: file, line: line)
            return
        }
        let matchingTypes = effs.compactMap({ $0 as? T2})
        guard nil != matchingTypes.first(where: { $0 == expected }) else {
            XCTFail("Effects on sut \(type(of: sut)): \(effs) do not include \(expected)", file: file, line: line)
            return
        }
        // sut?.clearPending()
    } catch {
        XCTFail("Thrown \(error)", file: file, line: line)
    }
}

extension StatoscopeTestPlan {

    @discardableResult
    public func THEN_EnquedEffect<EffectType: Effect>(
        file: StaticString = #file, line: UInt = #line,
        _ enquedEffect: EffectType
    ) throws -> Self {
        addStep { sut in
            let correctYypeEffects = sut.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            XCTAssertEqual(enquedEffect, foundEffect, file: file, line: line)
        }
    }
    
    @discardableResult
    public func THEN_Enqued<EffectType: Effect, Subscope: Scope>(
        _ keyPath: KeyPath<T, Subscope?>,
        effect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            guard let sut = supersut[keyPath: keyPath] else {
                XCTFail("No subscope found on \(type(of: supersut)) of type \(Subscope.self): when looking for effects", file: file, line: line)
                return
            }
            let correctYypeEffects = sut.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            XCTAssertEqual(effect, foundEffect, file: file, line: line)
        }
    }
    
    @discardableResult
    public func THEN_Enqued<EffectType: Effect, Subscope: Scope>(
        _ keyPath: KeyPath<T, Subscope>,
        effect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            let sut = supersut[keyPath: keyPath]
            let correctYypeEffects = sut.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            XCTAssertEqual(effect, foundEffect, file: file, line: line)
        }
    }
    
    @discardableResult
    public func THEN_EnquedEffect<EffectType: Effect, AcceptableKP: Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ oneEffect: KeyPath<EffectType, AcceptableKP>,
        equals expectedValue: AcceptableKP
    ) throws -> Self {
        addStep { sut in
            let correctYypeEffects = sut.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("More than one effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)", file: file, line: line)
                return
            }
            XCTAssertEqual(foundEffect[keyPath: oneEffect], expectedValue, file: file, line: line)
        }
    }
}
