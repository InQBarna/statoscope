//
//  StoreTestPlan+Effects.swift
//
//
//  Created by Sergi Hernanz on 6/2/24.
//

import Foundation
import Statoscope
import XCTest

extension StoreTestPlan {

    @discardableResult
    public func THEN_EnquedEffect<EffectType: Effect & Equatable>(
        file: StaticString = #file, line: UInt = #line,
        _ enquedEffect: EffectType
    ) throws -> Self {
        addStep { sut in
            let correctYypeEffects = sut.effectsState.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): " +
                        "\(correctYypeEffects)", file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): " +
                        "\(correctYypeEffects)", file: file, line: line)
                return
            }
            XCTAssertEqual(enquedEffect, foundEffect, file: file, line: line)
        }
    }

    @discardableResult
    public func THEN_NoEffects(
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { sut in
            let effs = sut.effectsState.effects
            if effs.count > 0 {
                XCTFail("Unexpected effects found on sut \(type(of: sut)): " +
                        "\(effs)", file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_Enqued<EffectType: Effect & Equatable, Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        effect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            guard let sut = supersut[keyPath: keyPath] else {
                XCTFail("No subscope found on \(type(of: supersut)) of type \(Subscope.self): " +
                        "when looking for effects", file: file, line: line)
                return
            }
            let correctYypeEffects = sut.effectsState.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)",
                        file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)",
                        file: file, line: line)
                return
            }
            XCTAssertEqual(effect, foundEffect, file: file, line: line)
        }
    }

    @discardableResult
    public func THEN_Enqued<EffectType: Effect & Equatable, Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        effect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            let sut = supersut[keyPath: keyPath]
            let correctYypeEffects = sut.effectsState.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)",
                        file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)",
                        file: file, line: line)
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
            let correctYypeEffects = sut.effectsState.effects.filter { $0 is EffectType }
            guard correctYypeEffects.count > 0 else {
                XCTFail("No effect of type \(EffectType.self) on sut \(type(of: sut)): \(correctYypeEffects)",
                        file: file, line: line)
                return
            }
            guard let foundEffect = correctYypeEffects.first as? EffectType else {
                XCTFail("More than one effect of type \(EffectType.self) on sut \(type(of: sut)): " +
                        "\(correctYypeEffects)",
                        file: file, line: line)
                return
            }
            XCTAssertEqual(foundEffect[keyPath: oneEffect], expectedValue, file: file, line: line)
        }
    }
}

public func XCTAssertEffectsInclude<S, T2>(
    _ expression1: @autoclosure () throws -> S?,
    _ expression2: @autoclosure () throws -> T2,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) where S: ScopeImplementation, T2: Effect & Equatable {
    do {
        let sut = try expression1()
        let expected = try expression2()
        guard let effs = sut?.effectsState.effects else {
            XCTFail("Effects on NIL sut \(type(of: sut)) does not contain \(expected)", file: file, line: line)
            return
        }
        let matchingTypes = effs.compactMap({ $0 as? T2})
        guard nil != matchingTypes.first(where: { $0 == expected }) else {
            XCTFail("Effects on sut \(type(of: sut)): \(effs) does not contain \(expected)", file: file, line: line)
            return
        }
        // sut?.cancelAllEffects()
    } catch {
        XCTFail("Thrown \(error)", file: file, line: line)
    }
}
