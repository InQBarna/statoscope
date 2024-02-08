//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 8/2/24.
//

import Foundation

/// Type erased box for an Effect
///
/// Use this container to have a type erased / anonymous version of the effect.
/// Use ``AnyEffect/init(_:)`` to create an anonymous Effect.
///
/// See ``Effect``
public struct AnyEffect<ResultType: Sendable>:
    Effect,
    CustomDebugStringConvertible,
    Sendable
{

    /// Originally typed effect. You can use this property and cast to your pristine Effect type
    public let pristine: any Effect & Sendable

    /// Creates an anonymous effect
    public init(_ runner: @escaping () async throws -> ResultType) {
        self.init(effect: EffectBox(runner: runner))
    }

    /// Debug description provides info about the pristine Effect
    public var debugDescription: String {
        return "\(pristine): \(pristine.resultTypeDescription)"
    }
    
    private struct EffectBox<BoxResultType>: Effect, CustomDebugStringConvertible {
        let runner: () async throws -> BoxResultType
        func runEffect() async throws -> BoxResultType {
            try await runner()
        }
        static func == (lhs: EffectBox<BoxResultType>, rhs: EffectBox<BoxResultType>) -> Bool {
            return false
        }
        public var debugDescription: String {
            "AnonymousEffect(closure: \(String(describing: runner)))"
        }
    }

    private let runner: @Sendable () async throws -> ResultType
    internal init<E: Effect>(effect: E) where E.ResultType == ResultType {
        if let anyEffect = effect as? AnyEffect<E.ResultType> {
            pristine = anyEffect.pristine
        } else {
            pristine = effect
        }
        runner = {
            try await effect.runEffect()
        }
    }

    init<E: Effect>(
        _ effect: E,
        mapper: @escaping (E.ResultType) -> ResultType
    ) {
        if let anyEffect = effect as? AnyEffect<E.ResultType> {
            pristine = anyEffect.pristine
        } else {
            pristine = effect
        }
        runner = {
            mapper(try await effect.runEffect())
        }
    }

    init<E: Effect, ErrorType: Error>(
        _ effect: E,
        errorMapper: @escaping (Error) -> ErrorType
    ) where ResultType == Result<E.ResultType, ErrorType> {
        if let anyEffect = effect as? AnyEffect<E.ResultType> {
            pristine = anyEffect.pristine
        } else {
            pristine = effect
        }
        runner = {
            do {
                return .success(try await effect.runEffect())
            } catch {
                return .failure(errorMapper(error))
            }
        }
    }

    public func runEffect() async throws -> ResultType {
        try await runner()
    }
}

