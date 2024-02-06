//
//  EffectsContainer.swift
//  
//
//  Created by Sergi Hernanz on 28/1/24.
//

import Foundation

public protocol EffectsState {
    /// Returns currently pending or ongoing effects
    var effects: [any Effect] { get }
}

// TODO: Rename to effectsState ?
// TODO: Make implementation like a struct defining the future tasks to be enqued or cancelled

/// Helper to be conformed by objects capable of handling effects
/// Responsible of managing a group of effects having a common return object type ``When``
public protocol EffectsContainer: EffectsState {

    /// Shared type to be returned by all effects interacting with the current EffectsContainer
    associatedtype When: Sendable

    /// Clears the effects that have not yet been triggered. Useful for testing purposes
    func clearPending()

    /// Enqueues an effect. The provided effect must return a new When case
    ///
    ///  - Parameter effect: a container of an async operation to be executed.
    ///   It must complete with an appropriate When case
    ///
    /// Please note enqueueing an effect is just adding it to a list of pending effects..
    /// Later calling ``EffectsContainer.runEnqueuedEffectAndGetWhenResults`` 
    /// will actually trigger all enqueued effects.
    ///
    /// However, Statoscope handles calling runEnqueuedEffectAndGetWhenResults right after 
    /// an update of the state, so user may usually not need to worry about this.
    ///  ### Usage
    ///  Use it with an anonymous Effect
    ///  ```swift
    ///  .enqueue(
    ///    AnyEffect {
    ///      let resultDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
    ///      return When.networkPostCompleted(resultDTO)
    ///    }
    ///  )
    ///  ```
    ///  Or created a typed Effect
    ///  ```swift
    ///  struct NetworkEffect<Response: Decodable>: Effect {
    ///    let request: URLRequest
    ///    func runEffect() async throws -> Response {
    ///      try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    ///    }
    ///  }
    ///  ```
    ///  And use it mapping the result to your When case
    ///  ```swift
    ///  .enqueue(
    ///    let url = URL(string: "http://statoscope.com")!
    ///    var request = URLRequest(url: url)
    ///    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    ///    request.httpMethod = "POST"
    ///    request.httpBody = try JSONEncoder().encode(dto)
    ///    return NetworkEffect(request)
    ///       .map(When.networkPostCompleted)
    ///  )
    ///  ```
    func enqueue<E: Effect>(_ effect: E) where E.ResType == When

    /// Cancels the effects that conform to the provided block.
    ///
    ///  - Parameter whereBlock: A closure that takes an ongoing effect as its argument and returns a
    ///   Boolean value indicating whether the effect should be cancelle
    ///
    ///  You should have previously enqueued a typed effect like this one
    ///  ```swift
    ///  struct NetworkEffect<Response: Decodable>: Effect {
    ///    let request: URLRequest
    ///    func runEffect() async throws -> Response {
    ///      try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    ///    }
    ///  }
    ///  ```
    ///  and layer you can cancel it by:
    ///  ```swift
    ///  .cancelEffect { ongoingEffect in
    ///    networkEffect is NetworkEffect<DTO>
    ///  )
    ///  ```
    func cancelEffect(where whereBlock: (any Effect) -> Bool)

    /// Cancells all ongoing effects
    func cancelAllEffects()
}

// TODO: Remove EffectsHandlerImplementation, only Store implements this,
//  so we should change extension on EffectsHandlerImplementation to Store

/// When conformed, the object has a default implementation of runEnqueuedEffectAndGetWhenResults
/// and conformance to EffectsContainer
public protocol EffectsHandlerImplementation {

    /// Shared type to be returned by all effects interacting with the current EffectsHandlerImplementation
    ///
    associatedtype When: Sendable

    /// Handler to manage effects
    var effectsHandler: EffectsHandler<When> { get }
}

/*
 Reducer: No longer provide store as EffectsContainer, force usage of effectsHandler ??
 */
public extension EffectsHandlerImplementation where Self: AnyObject {

    func enqueue<E: Effect>(_ effect: E) where E.ResType == When {
        effectsHandler.enqueue(effect)
    }

    var effects: [any Effect] {
        return effectsHandler.effects
    }

    // Needed as public for clearAllDeepPendingEffects for now
    func clearPending() {
        effectsHandler.clearPending()
    }

    func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        effectsHandler.cancelEffect(where: whereBlock)
    }

    func cancelAllEffects() {
        effectsHandler.cancelAllEffects()
    }

}
