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

private extension Effect {
    var resultTypeDescription: String {
        "\(type(of: ResType.self))"
            .replacingOccurrences(of: ".Type", with: "")
    }
}

public struct AnyEffect<ResType>: Effect, Equatable, CustomDebugStringConvertible, Sendable {
    
    // Helper struct EffectBox
    private struct EffectBox<EBResType>: Effect, CustomDebugStringConvertible {
        let runner: () async throws -> EBResType
        func runEffect() async throws -> EBResType {
            try await runner()
        }
        static func == (lhs: EffectBox<EBResType>, rhs: EffectBox<EBResType>) -> Bool {
            return false
        }
        public var debugDescription: String {
            "AnonymousEffect(closure: \(String(describing: runner)))"
        }
    }
    
    let wrappedEffect: any Effect & Sendable
    let runner: @Sendable () async throws -> ResType
    
    // Init with block
    public init(_ runner: @escaping () async throws -> ResType) {
        self.init(effect: EffectBox(runner: runner))
    }
    
    // Init when effect returns When
    public init<E: Effect>(effect: E) where E.ResType == ResType {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            wrappedEffect = anyEffect.wrappedEffect
        } else {
            wrappedEffect = effect
        }
        runner = {
            try await effect.runEffect()
        }
    }
    
    // Init with mapper for effect -> When
    init<E: Effect>(
        _ effect: E,
        mapper: @escaping (E.ResType) -> ResType
    ) {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            wrappedEffect = anyEffect.wrappedEffect
        } else {
            wrappedEffect = effect
        }
        runner = {
            mapper(try await effect.runEffect())
        }
    }
    
    // Init with error mapper for throwing effect
    init<E: Effect, ErrorType: Error>(
        _ effect: E,
        errorMapper: @escaping (Error) -> ErrorType
    ) where ResType == Result<E.ResType, ErrorType> {
        if let anyEffect = effect as? AnyEffect<E.ResType> {
            wrappedEffect = anyEffect.wrappedEffect
        } else {
            wrappedEffect = effect
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
        assertionFailure("We can assume effect description is unique, but better don't rely on this equatable implementation")
        return "\(lhs.wrappedEffect)" == "\(rhs.wrappedEffect)"
    }
    
    public var debugDescription: String {
        return "\(wrappedEffect): \(wrappedEffect.resultTypeDescription)"
    }
}

extension Effect {

    public func eraseToAnyEffect() -> AnyEffect<ResType> {
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
