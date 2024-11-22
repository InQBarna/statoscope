//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 17/10/24.
//

import Foundation
@_spi(SCT) import Statoscope
import XCTest

struct EffectTestError<T: Effect, S: ScopeImplementation>: Error {
    enum EffectTestErrorType {
        case notFound
        case tooMany
    }
    let existingEffects: [any Effect]
    let sut: S
    let type: EffectTestErrorType
}

struct FoundEffect<E: Effect> {
    let erased: any Effect
    let typed: E
}

private func findEffects<EffectType: Effect, T: ScopeImplementation>(
    _ expectedEffect: EffectType.Type,
    sut: T
) -> [FoundEffect<EffectType>]? {
    return sut.effectsState._erasedEffects.compactMap {
        if let typedEffect = $0.pristine as? EffectType {
            return FoundEffect(erased: $0, typed: typedEffect)
        } else {
            return nil
        }
    }
}

func grabEffects<EffectType: Effect, T: ScopeImplementation>(
    _ expectedEffect: EffectType.Type,
    sut: T,
    clearingFound: Bool = true
) -> Result<[FoundEffect<EffectType>], EffectTestError<EffectType, T>> {
    guard let foundEffects = findEffects(expectedEffect, sut: sut),
          foundEffects.count > 0 else {
        return .failure(
            EffectTestError(existingEffects: sut.effects, sut: sut, type: .notFound)
        )
    }
    if clearingFound {
        sut.effectsState.clear(.some { $0 is EffectType })
    }
    return .success(foundEffects)
}

func grabSingleEffect<EffectType: Effect, T: ScopeImplementation>(
    _ expectedEffect: EffectType.Type,
    sut: T,
    clearingFound: Bool
) -> Result<FoundEffect<EffectType>, EffectTestError<EffectType, T>> {
    guard let foundEffects = findEffects(expectedEffect, sut: sut),
          let foundEffect = foundEffects.first else {
        return .failure(
            EffectTestError(existingEffects: sut.effects, sut: sut, type: .notFound)
        )
    }
    guard foundEffects.count < 2 else {
        return .failure(
            EffectTestError(existingEffects: foundEffects.map { $0.erased }, sut: sut, type: .tooMany)
        )
    }
    if clearingFound {
        sut.effectsState.clear(.some { $0 is EffectType })
    }
    return .success(foundEffect)
}

func getSingleEffect<EffectType: Effect & Equatable, T: ScopeImplementation>(
    _ expectedEffect: EffectType,
    sut: T
) -> Result<FoundEffect<EffectType>, EffectTestError<EffectType, T>> {
    switch grabEffects(EffectType.self, sut: sut, clearingFound: false) {
    case .failure(let error):
        return .failure(error)
    case .success(let foundEffects):
        for effect in foundEffects {
            if effect.typed == expectedEffect {
                return .success(effect)
            }
        }
        return .failure(
            EffectTestError(existingEffects: sut.effects, sut: sut, type: .notFound)
        )
    }
}
