//
//  Effect.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

public protocol Effect: Equatable {
    associatedtype ResType
    func runEffect() async throws -> ResType
}

fileprivate struct EffectBox<ResType>: Effect, CustomDebugStringConvertible {
    let runner: () async throws -> ResType
    func runEffect() async throws -> ResType {
        try await runner()
    }
    static func == (lhs: EffectBox<ResType>, rhs: EffectBox<ResType>) -> Bool {
        return false
    }
    public var debugDescription: String {
        "AnonymousEffect(closure: \(String(describing: runner)))"
    }
}

private extension Effect {
    var resTypeDescription: String {
        "\(type(of: ResType.self))"
            .replacingOccurrences(of: ".Type", with: "")
    }
}

public struct AnyEffect<ResType>: Effect, Equatable, CustomDebugStringConvertible, Sendable {
    
    let effectType: any Effect & Sendable
    let runner: @Sendable () async throws -> ResType
    
    // Init with block
    init(_ runner: @escaping () async throws -> ResType) {
        self.init(effect: EffectBox(runner: runner))
    }
    
    // Init when effect returns When
    init<E: Effect>(effect: E) where E.ResType == ResType {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            effectType = anyEffect.effectType
        } else {
            effectType = effect
        }
        runner = {
            try await effect.runEffect()
        }
    }
    
    // Init with mapper for effect -> When
    fileprivate init<E: Effect>(
        _ effect: E,
        mapper: @escaping (E.ResType) -> ResType
    ) {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            effectType = anyEffect.effectType
        } else {
            effectType = effect
        }
        runner = {
            mapper(try await effect.runEffect())
        }
    }
    
    fileprivate init<E: Effect, ErrorType: Error>(
        _ effect: E,
        errorMapper: @escaping (Error) -> ErrorType
    ) where ResType == Result<E.ResType, ErrorType> {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            effectType = anyEffect.effectType
        } else {
            effectType = effect
        }
        runner = {
            do {
                return .success(try await effect.runEffect())
            } catch {
                return .failure(errorMapper(error))
            }
        }
    }

    public func runEffect() async throws -> ResType {
        try await runner()
    }
    
    public static func == (lhs: AnyEffect<ResType>, rhs: AnyEffect<ResType>) -> Bool {
        return "\(lhs.effectType)" == "\(rhs.effectType)"
    }
    
    public var debugDescription: String {
        return "\(effectType): \(effectType.resTypeDescription)"
    }
}

extension Effect {

    func eraseToAnyEffect() -> AnyEffect<ResType> {
        AnyEffect(effect: self)
    }

    public func map<MapResType>(
        _ mapper: @escaping (Self.ResType) -> MapResType
    ) -> AnyEffect<MapResType> {
        return AnyEffect<MapResType>(self, mapper: mapper)
    }
    
    public func mapToResult<ErrorType: Error>(
        error: @escaping (Error) -> ErrorType
    ) -> AnyEffect<Result<Self.ResType, ErrorType>> {
        return AnyEffect<Result<Self.ResType, ErrorType>>(self, errorMapper: error)
    }
    
    public func mapToResult<ErrorType: Error & EffectError>(
        error: ErrorType.Type
    ) -> AnyEffect<Result<Self.ResType, ErrorType>> {
        return AnyEffect<Result<Self.ResType, ErrorType>>(self) {
            $0 as? ErrorType ?? error.unknownError
        }
    }
}
