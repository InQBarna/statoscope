//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 15/4/24.
//

import Foundation
import StatoscopeTesting
import Statoscope
import XCTest

final class Example0201 {
    
    struct DTO: Codable {
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
            
            // Solution 1: cancel any previous network effect
            effectsState.cancelEffect { $0 is CloudCounterEffect<DTO> }
            
            // Solution 2: do nothing if an effect is already running
            guard nil == effects.first(where: { $0 is CloudCounterEffect<DTO> }) else {
                throw InvalidStateError()
            }
            
            effectsState.enqueue(
                CloudCounterEffect<DTO>(request: try Network.buildURLRequestPosting(dto: DTO(count: newValue)))
                    .map(When.networkPostCompleted)
            )
        }
    }
    
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
    }
    
    struct CloudCounterEffect<Response: Decodable>: Effect, Equatable {
        let request: URLRequest
        func runEffect() async throws -> Response {
            try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
        }
    }
}

private typealias CloudCounterEffect = Example0201.CloudCounterEffect
private typealias CloudCounter = Example0201.CloudCounter
private typealias DTO = Example0201.DTO

final class TypedEffectCloudCounterTest: XCTestCase {

    func testUserFlow() throws {
        
        var expectedNetworkRequest = URLRequest(url: try XCTUnwrap(URL(string: "http://statoscope.com")))
        expectedNetworkRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        expectedNetworkRequest.httpMethod = "POST"
        expectedNetworkRequest.httpBody = try JSONEncoder().encode(DTO(count: 0))
        
        try CloudCounter.GIVEN {
            CloudCounter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Increment
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .THEN_EnquedEffect(CloudCounterEffect<DTO>(request: expectedNetworkRequest))
        .WHEN(.networkPostCompleted(DTO(count: 1)))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .THEN { XCTAssertEqual($0.effects.count, 0) }
        // Decrement
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .WHEN(.networkPostCompleted(DTO(count: 0)))
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        // Invalid decrement
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .runTest()
    }

}

