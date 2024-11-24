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

final class Example0101 {
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
        
        func update(_ when: When) throws {}
    }
    
    final class CloudCounterTest: XCTestCase {
        
        func testUserFlow() throws {
            XCTExpectFailure()
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
            // Invalid decrement
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .runTest()
        }
        
    }
}

enum Example0104 {
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
            effectsState.enqueue(
                AnyEffect {
                    let request = try Network.buildURLRequestPosting(dto: DTO(count: self.viewDisplaysTotalCount))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        }
    }
}
