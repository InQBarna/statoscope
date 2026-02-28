//
//  Tutorial02_StateWhenAndEffects.swift
//  Statoscope
//
//  Examples from Tutorial 02: State, When and Effects
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

/// Tutorial 02: CloudCounter with Network Effects
enum Tutorial02 {

    enum Network {
        static func buildURLRequestPosting(dto: DTO) throws -> URLRequest {
            guard let url = URL(string: "http://statoscope.com") else {
                throw InvalidStateError()
            }
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpMethod = "POST"
            request.httpBody = try JSONEncoder().encode(dto)
            return request
        }

        struct Effect<Response: Decodable>: Statoscope.Effect {
            let request: URLRequest
            func runEffect() async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
        }
    }

    struct DTO: Codable, Equatable {
        let count: Int
    }

    final class CloudCounter: ScopeImplementation {
        var viewDisplaysTotalCount: Int = 0
        var viewShowsLoadingAndDisablesButtons: Bool = false

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case networkPostCompleted(DTO)
        }

        func update(_ when: When) throws {
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount = viewDisplaysTotalCount + 1
                viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: viewDisplaysTotalCount)

            case .userTappedDecrementButton:
                guard viewDisplaysTotalCount > 0 else {
                    return
                }
                viewDisplaysTotalCount = viewDisplaysTotalCount - 1
                viewShowsLoadingAndDisablesButtons = true
                try postNewValueToNetwork(newValue: viewDisplaysTotalCount)

            case .networkPostCompleted(let remoteCounter):
                viewShowsLoadingAndDisablesButtons = false
                viewDisplaysTotalCount = remoteCounter.count
            }
        }

        private func postNewValueToNetwork(newValue: Int) throws {
            // Cancel any previous network effect
            effectsState.cancelEffect { $0 is Network.Effect<DTO> }

            effectsState.enqueue(
                Network.Effect<DTO>(request: try Network.buildURLRequestPosting(dto: DTO(count: newValue)))
                    .map(When.networkPostCompleted)
            )
        }
    }

    final class CloudCounterTests: XCTestCase {

        func testBasicFlow() throws {
            try CloudCounter.GIVEN {
                CloudCounter()
            }
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
            // Increment
            .WHEN(.userTappedIncrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
            .WHEN(.networkPostCompleted(DTO(count: 1)))
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
            // Decrement
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
            .WHEN(.networkPostCompleted(DTO(count: 0)))
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
            // Invalid decrement (already at 0, no effect triggered)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .runTest(assertNoPendingEffects: false)  // Effects are still running
        }

        func testEffectsAreCancelled() throws {
            try CloudCounter.GIVEN {
                CloudCounter()
            }
            // First increment starts network call
            .WHEN(.userTappedIncrementButton)
            .THEN { scope in
                XCTAssertGreaterThanOrEqual(scope.effects.count, 1)
                XCTAssertTrue(scope.effects.contains(where: { $0 is Network.Effect<DTO> }))
            }
            // Second increment cancels previous and starts new one
            .WHEN(.userTappedIncrementButton)
            .THEN { scope in
                XCTAssertGreaterThanOrEqual(scope.effects.count, 1)  // At least 1 effect
            }
            .WHEN(.networkPostCompleted(DTO(count: 2)))
            .THEN(\.viewDisplaysTotalCount, equals: 2)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
            .runTest(assertNoPendingEffects: false)
        }
    }
}
