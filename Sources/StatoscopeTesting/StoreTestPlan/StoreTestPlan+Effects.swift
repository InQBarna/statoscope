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
    public func WHEN_EffectCompletes<EffectType: Effect>(
        _ expectedEffect: EffectType.Type,
        with effectResult: EffectType.ResultType,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        return addStep { sut in
            switch grabSingleEffect(expectedEffect, sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                guard let effectResult = try foundEffect.erased._pristineCompletes(effectResult) as? T.When else {
                    throw InvalidPristineResult()
                }
                try sut._unsafeSendImplementation(effectResult)
            }
        }
    }
    
    @discardableResult
    public func WHEN_EffectFails<EffectType: Effect>(
        _ expectedEffect: EffectType.Type,
        with effectResult: Error,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> Self {
        return addStep { sut in
            switch grabSingleEffect(expectedEffect, sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                guard let effectResult = try foundEffect.erased._pristineFails(effectResult) as? T.When else {
                    throw InvalidPristineResult()
                }
                try sut._unsafeSendImplementation(effectResult)
            }
        }
    }
    
    @discardableResult
    public func THEN_NoEnquedEffect<EffectType: Effect>(
        _ expectedEffect: EffectType.Type,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { sut in
            switch grabEffects(expectedEffect, sut: sut) {
            case .failure:
                return
            case .success(let foundEffects):
                XCTFailForEffectSearchSuccess(foundEffects: foundEffects, sut: sut, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_NoEnquedEffect<EffectType: Effect, Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        _ expectedEffect: EffectType.Type,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            guard let sut = supersut[keyPath: keyPath] else {
                XCTFailForMissingSubscope(keyPath: keyPath, file: file, line: line)
                return
            }
            switch grabEffects(expectedEffect, sut: sut) {
            case .failure:
                return
            case .success(let foundEffects):
                XCTFailForEffectSearchSuccess(foundEffects: foundEffects, sut: sut, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_NoEffects(
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { sut in
            let effects = sut.effectsState.effects
            if effects.count > 0 {
                XCTFailForEffectSearchSuccess(erasedFoundEffects: effects, sut: sut, file: file, line: line)
            }
        }
    }
    
    @discardableResult
    public func THEN_NoEffects<Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            guard let sut = supersut[keyPath: keyPath] else {
                XCTFailForMissingSubscope(keyPath: keyPath, file: file, line: line)
                return
            }
            let effs = sut.effectsState.effects
            if effs.count > 0 {
                XCTFailForEffectSearchSuccess(erasedFoundEffects: effs, sut: sut, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_Enqued<EffectType: Effect & Equatable, Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope?>,
        effect expectedEffect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            guard let sut = supersut[keyPath: keyPath] else {
                XCTFailForMissingSubscope(keyPath: keyPath, file: file, line: line)
                return
            }
            switch grabSingleEffect(EffectType.self, sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                try XCTAssertEqualDiff(foundEffect.typed, expectedEffect, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_Enqued<EffectType: Effect & Equatable, Subscope: ScopeImplementation>(
        _ keyPath: KeyPath<T, Subscope>,
        effect expectedEffect: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { supersut in
            let sut = supersut[keyPath: keyPath]
            switch grabSingleEffect(EffectType.self, sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                try XCTAssertEqualDiff(foundEffect.typed, expectedEffect, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_EnquedEffect<EffectType: Effect & Equatable>(
        _ expectedValue: EffectType,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { sut in
            switch grabSingleEffect(type(of: expectedValue), sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                try XCTAssertEqualDiff(foundEffect.typed, expectedValue, file: file, line: line)
            }
        }
    }

    @discardableResult
    public func THEN_EnquedEffect<EffectType: Effect, Value: Equatable>(
        parameter: KeyPath<EffectType, Value>,
        equals expectedValue: Value,
        file: StaticString = #file, line: UInt = #line
    ) throws -> Self {
        addStep { sut in
            switch grabSingleEffect(EffectType.self, sut: sut) {
            case .failure(let error):
                XCTFailForEffectSearchError(error, file: file, line: line)
            case .success(let foundEffect):
                try XCTAssertEqualDiff(foundEffect.typed[keyPath: parameter], expectedValue, file: file, line: line)
            }
        }
    }
}
