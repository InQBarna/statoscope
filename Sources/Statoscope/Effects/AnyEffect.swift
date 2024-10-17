//
//  AnyEffect.swift
//  
//
//  Created by Sergi Hernanz on 8/2/24.
//

import Foundation

public struct InvalidPristineResult: Error {
    public init() { }
}

/// Type erased box for an Effect
///
/// Use this container to have a type erased / anonymous version of the effect.
/// Use ``AnyEffect/init(_:)`` to create an anonymous Effect.
///
/// See ``Effect``
public struct AnyEffect<ResultType: Sendable>:
    Effect,
    CustomDebugStringConvertible,
    Sendable {

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
        public var debugDescription: String {
            "AnonymousEffect(closure: \(String(describing: runner)))"
        }
    }

    private let runner: @Sendable () async throws -> ResultType
    internal let transformPristineResult: @Sendable (() throws -> Any) throws -> ResultType
    internal init<E: Effect>(effect: E) where E.ResultType == ResultType {
        if let anyEffect = effect as? AnyEffect<E.ResultType> {
            pristine = anyEffect.pristine
            transformPristineResult = {
                try anyEffect.transformPristineResult($0)
            }
        } else {
            pristine = effect
            transformPristineResult = {
                guard let result = try $0() as? E.ResultType else {
                    throw InvalidPristineResult()
                }
                return result
            }
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
            transformPristineResult = {
                return mapper(try anyEffect.transformPristineResult($0))
            }
        } else {
            pristine = effect
            transformPristineResult = {
                guard let result = try $0() as? E.ResultType else {
                    throw InvalidPristineResult()
                }
                return mapper(result)
            }
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
            transformPristineResult = {
                do {
                    return .success(try anyEffect.transformPristineResult($0))
                } catch {
                    return .failure(errorMapper(error))
                }
            }
        } else {
            pristine = effect
            transformPristineResult = { method in
                do {
                    if let typedResult = try method() as? E.ResultType {
                        return .success(typedResult)
                    }
                } catch {
                    return .failure(errorMapper(error))
                }
                throw InvalidPristineResult()
            }
        }
        runner = {
            do {
                return .success(try await effect.runEffect())
            } catch {
                return .failure(errorMapper(error))
            }
        }
    }

    /// Executes the effect asynchronously and returns a result.
    ///
    /// This method runs an asynchronous operation that may throw an error or produce a result.
    /// You usually don't call this method directly, instead enqueue the effect to your
    ///  statostore effectsState and it will run in its scope
    ///
    /// - Returns: A `ResultType` value representing the outcome of the effect.
    ///
    /// - Throws: An error if the effect fails to execute.
    ///
    /// - Note: This method encapsulates the asynchronous execution provided by this effect
    public func runEffect() async throws -> ResultType {
        try await runner()
    }
}

internal protocol IsAnyEffectToMirror {
    var objectToBeDescribed: Any { get }
}

extension AnyEffect: IsAnyEffectToMirror {
    var objectToBeDescribed: Any {
        pristine
    }
}
