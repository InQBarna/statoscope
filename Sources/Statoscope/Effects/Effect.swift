//
//  Effect.swift
//  
//
//  Created by Sergi Hernanz on 18/1/24.
//

import Foundation

/// Defines an asynchronous operation which returns specific type of action
///
/// Conform to the Effect protocol to create an asynchronous operation that can be
/// enqueued into an store.
///
/// The ResultType of the effect is strongly typed. And the Effect should allways return an object of t
/// the specified type. In case the operation cannot be completed here are some recommended options
/// - Throw a CancellationError() when the operation should be cancelled
/// - Throw an appropriate exception: the store in statoscope will catch and log the exception
/// - Change the ResultType to Result<PreviousResultType, KnownExceptionType> and map any
///    throwing exception
///
/// # Mapping
/// You can map the throwing exception by using
/// ```swift
/// let effect = MyEffect()
///  .mapToResultWithError { MyErrorType.unknown }
/// ```
///
/// # Pristine effect and pristineEquals
/// The effect protocol does NOT enforce conform to Equatable, but it is recommended.
/// When effects are enqueud into an store, querying them is often needed. To do so, we
/// recommend:
/// 1. Creating your own typed effects.
/// 2. Conform the effect type to equatable.
/// 3. Use ``pristineEquals(_:)-5w9j1`` to search for exact effect instances.
///
public protocol Effect {
    
    /// The type returned by this effect,
    ///
    /// This is usually an enum of When cases to group effects inside a Store
    associatedtype ResultType: Sendable
    
    /// The method to be executed when the Effects handler schedules this Effect
    ///
    ///  * returns: An object with the specified type, or throws an error
    func runEffect() async throws -> ResultType
    
    /// Compares the current effect to another effect
    ///
    /// This comparison is provided for searching an effect inside an array of effect
    /// ```swift
    /// struct MyEffect: Effect, Equatable {
    ///   let param1: String
    ///   func runEffect() async throws -> String {
    ///     return "done"
    ///   }
    /// }
    /// let effects: [MyEffect(param1: "One"), MyEffect(param1: "Two")]
    /// let effectOne = effects.first { $0.equals(MyEffect(param1: "One")) }
    /// ```
    ///  * returns: True if the compared effect
    ///  See ``Statoscope/AnyEffect/pristine``
    func pristineEquals<ComparedEffect: Effect & Equatable>(_: ComparedEffect) -> Bool
}

public extension Effect {
    
    func pristineEquals<ComparedEffect: Effect & Equatable>(_ other: ComparedEffect) -> Bool
    {
        if let anySelf = self as? AnyEffect<ResultType>,
           let typedSelf = anySelf.pristine as? ComparedEffect {
            return typedSelf == typedSelf
        } else if let typedSelf = self as? ComparedEffect {
            return typedSelf == other
        } else {
            return false
        }
    }
    
    /// Type erasure helper
    func eraseToAnyEffect() -> AnyEffect<ResultType> {
        AnyEffect(effect: self)
    }

    /// Maps the result of the effect to another type
    ///
    /// - Parameter mapper: the closure mapping the result to anothre type
    /// - Returns: An Effect with a new ReturnType
    func map<MapResType>(
        _ mapper: @escaping (Self.ResultType) -> MapResType
    ) -> AnyEffect<MapResType> {
        return AnyEffect<MapResType>(self, mapper: mapper)
    }

    /// Maps the result of the effect to a result type with a typed Error
    ///
    /// - Parameter error: the closure mapping the result exceptions to a known error type
    /// - Returns: An Effect with a new ReturnType Result<ReturnType, ErrorType>
    func mapToResultWithError<ErrorType: Error>(
        _ error: @escaping (Error) -> ErrorType
    ) -> AnyEffect<Result<Self.ResultType, ErrorType>> {
        return AnyEffect<Result<Self.ResultType, ErrorType>>(self, errorMapper: error)
    }

    /// Maps the result of the effect to a result type with a typed Error, which conforms to EffectError
    ///
    /// - Parameter error: the closure mapping the result exceptions to a known error type
    /// - Returns: An Effect with a new ReturnType Result<ReturnType, ErrorType>
    func mapToResultWithErrorType<ErrorType: Error & EffectError>(
        _ error: ErrorType.Type
    ) -> AnyEffect<Result<Self.ResultType, ErrorType>> {
        return AnyEffect<Result<Self.ResultType, ErrorType>>(self) {
            $0 as? ErrorType ?? error.unknownError
        }
    }
    
    /// Maps the result of the effect to a result type with an untyped Error
    ///
    /// - Returns: An Effect with a new ReturnType Result<ReturnType, Error>
    func mapToResult() -> AnyEffect<Result<Self.ResultType, Error>> {
        return AnyEffect<Result<Self.ResultType, Error>>(self, errorMapper: { $0 })
    }
}

internal extension Effect {
    var resultTypeDescription: String {
        "\(type(of: ResultType.self))"
            .replacingOccurrences(of: ".Type", with: "")
    }
}

