//
//  EffectsState.swift
//  
//
//  Created by Sergi Hernanz on 9/2/24.
//

import Foundation

/// Responsible of controlling a group of effects, all they having a common return object type When.
/// This struct is meant for communication between an update of your app's state and the trigger of
/// the appropriate effects. Simply defines the current ongoing effects providing an snapshot,
/// and provides functions to enqueue new effects or cancel existing ones.
public struct EffectsState<When: Sendable>: Sendable {

    internal let snapshotEffects: [(UInt, AnyEffect<When>)]
    internal var currentRequestedEffects: [(UInt, AnyEffect<When>)]
    internal var enquedEffects: [(UInt, AnyEffect<When>)] = []
    internal var cancelledEffects: [(UInt, AnyEffect<When>)] = []

    init(snapshotEffects: [(UInt, AnyEffect<When>)]) {
        self.snapshotEffects = snapshotEffects
        self.currentRequestedEffects = snapshotEffects
    }

    /// List of effects expected to be ongoing. They may be already triggered or pending.
    public var effects: [any Effect] {
        currentRequestedEffects.map { $0.1.pristine }
    }

    /// Enqueues an effect to be triggered. The provided effect must return a new When case
    ///
    ///  - Parameter effect: a container of an async operation to be executed.
    ///   It must complete with an appropriate When case
    ///
    /// Please note enqueueing an effect is just adding it to a list of pending effects. Does not
    /// immediately trigger it. However EffectsState is provided in the update method and right
    /// after method is completed, the enqueued effects will be triggered
    ///  ### Usage
    ///  Use it with an anonymous Effect
    ///  ```swift
    ///  effectsController.enqueue(
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
    ///  effectsController.enqueue(
    ///    let url = URL(string: "http://statoscope.com")!
    ///    var request = URLRequest(url: url)
    ///    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    ///    request.httpMethod = "POST"
    ///    request.httpBody = try JSONEncoder().encode(dto)
    ///    return NetworkEffect(request)
    ///       .map(When.networkPostCompleted)
    ///  )
    ///  ```
    public mutating func enqueue<E: Effect>(_ effect: E) where E.ResultType == When {
        guard _updating else {
            assertionFailure("Effects can only be enqueued from within an update")
            return
        }
        let currentMax = currentRequestedEffects.map(\.0).max() ?? 0
        let uuid = currentMax + 1
        enquedEffects.append((uuid, AnyEffect(effect: effect)))
        currentRequestedEffects.append((uuid, AnyEffect(effect: effect)))
    }

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
    ///  effectsController.cancelEffect { ongoingEffect in
    ///    networkEffect is NetworkEffect<DTO>
    ///  )
    ///  ```
    public mutating func cancelEffect(where whereBlock: (any Effect) -> Bool) {
        let cancelledFromCurrent = currentRequestedEffects
            .filter { whereBlock($0.1.pristine) }
        cancelledEffects.append(contentsOf: cancelledFromCurrent)
        currentRequestedEffects = currentRequestedEffects.filter {
            !whereBlock($0.1.pristine)
        }
        enquedEffects = enquedEffects.filter {
            !whereBlock($0.1.pristine)
        }
    }

    /// Cancells all ongoing effects
    public mutating func cancelAllEffects() {
        cancelledEffects.append(contentsOf: currentRequestedEffects)
        enquedEffects.removeAll()
        currentRequestedEffects.removeAll()
    }

    /// Resets effects state to the original status previous to the update method
    ///
    /// This method is mostly meant for unit testing
    public mutating func reset(
        clearing: (any Effect, any ScopeImplementation) -> Bool = { _, _ in true },
        scope: any ScopeImplementation
    ) {
        currentRequestedEffects = currentRequestedEffects.filter { _, anyEffect in
            !clearing(anyEffect.pristine, scope)
        }
        // TODO: revisar este removeAll?
        enquedEffects.removeAll()
        cancelledEffects.removeAll()
    }

    /// Erased list of effects expected to be ongoing. They may be already triggered or pending.
    /// Their type information erased (for testing purposes).
    ///
    /// - Note: This property is marked with a leading underscore to indicate that it is intended for private use
    /// within the StatoscopeTesting library and should not be used in production code.
    @_spi(SCT) public var _erasedEffects: [AnyEffect<When>] {
        currentRequestedEffects.map { $0.1 }
    }

    /// List of effects expected to be ongoing. With their uuids (for testing purposes)
    ///
    /// - Note: This property is marked with a leading underscore to indicate that it is intended for private use
    /// within the StatoscopeTesting library and should not be used in production code.
    @_spi(SCT) public mutating func _cancelOlderEffect() throws -> AnyEffect<When> {
        // TODO: renombrar ó replantear métodos reset y este
        guard let olderEffect = currentRequestedEffects.min(by: { lhs, rhs in lhs.0 < rhs.0 }) else {
            throw StatoscopeErrors.effectNotFound
        }
        let olderUUID = olderEffect.0
        currentRequestedEffects = currentRequestedEffects.filter { uuid, _ in
            uuid != olderUUID
        }
        enquedEffects = currentRequestedEffects.filter { uuid, _ in
            uuid != olderUUID
        }
        // TODO: revisar este removeAll?
        cancelledEffects.removeAll()
        return olderEffect.1
    }

    var _updating: Bool = false
}
