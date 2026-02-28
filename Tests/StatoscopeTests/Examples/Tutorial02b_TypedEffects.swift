//
//  Tutorial02b_TypedEffects.swift
//  Statoscope
//
//  Examples from Tutorial 02: State, When and Effects (Typed Effects)
//

import Foundation
// @extract:begin 01-02-02-code-0001
// @extract:begin 01-02-02-code-0002
// @extract:begin 01-02-02-code-0003
import Statoscope

enum Tutorial02b {

    enum Network {
        // @extract:end 01-02-02-code-0001
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
        // @extract:end 01-02-02-code-0002

        // @extract:begin 01-02-02-code-0001
        struct Effect<Response: Decodable>: Statoscope.Effect, Equatable {
            let request: URLRequest
            func runEffect() async throws -> Response {
                try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
            }
        }
        // @extract:begin 01-02-02-code-0002
    }
    // @extract:end 01-02-02-code-0001

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
            // @extract:end 01-02-02-code-0002
            // Solution 1: Cancel any previous
            effectsState.cancelEffect { $0 is Network.Effect<DTO> }
            // Solution 2: do nothing if an effect is already running
            guard nil == effects.first(where: { $0 is Network.Effect<DTO> }) else {
                throw InvalidStateError()
            }

            // @extract:begin 01-02-02-code-0002
            effectsState.enqueue(
                Network.Effect<DTO>(request: try Network.buildURLRequestPosting(dto: DTO(count: newValue)))
                    .map(When.networkPostCompleted)
            )
        }
        // @extract:begin 01-02-02-code-0002
        // @extract:begin 01-02-02-code-0003
    }
    // @extract:begin 01-02-02-code-0001
}
// @extract:end 01-02-02-code-0001
// @extract:end 01-02-02-code-0002
// @extract:end 01-02-02-code-0003

// @extract:begin 01-02-02-code-0004
// @extract:begin 01-02-02-code-0005

import StatoscopeTesting
import XCTest

extension Tutorial02b {
    final class CloudCounterTests: XCTestCase {

        func testBasicFlow() throws {
            
            // @extract:end 01-02-02-code-0004
            var expectedNetworkRequest = URLRequest(url: try XCTUnwrap(URL(string: "http://statoscope.com")))
            expectedNetworkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            expectedNetworkRequest.httpMethod = "POST"
            expectedNetworkRequest.httpBody = try JSONEncoder().encode(DTO(count: 0))

            // @extract:begin 01-02-02-code-0004
            try CloudCounter.GIVEN {
                CloudCounter()
            }
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
            // Increment
            .WHEN(.userTappedIncrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
            // @extract:end 01-02-02-code-0004
            .THEN_EnquedEffect(Network.Effect<DTO>(request: expectedNetworkRequest))
            // @extract:begin 01-02-02-code-0004
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
    }
}
// @extract:end 01-02-02-code-0005
// @extract:end 01-02-02-code-0004
