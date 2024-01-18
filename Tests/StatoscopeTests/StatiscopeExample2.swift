//
//  StatiscopeExample2.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 28/12/23.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

fileprivate func buildURLRequestPosting(dto: DTO) throws -> URLRequest {
    guard let url = URL(string: "http://statoscope.com") else {
        fatalError()
    }
    var request = URLRequest(url: url)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(dto)
    return request
}

fileprivate struct DTO: Codable {
    let count: Int
}

fileprivate struct NetworkEffect<Response: Decodable>: Effect {
    let request: URLRequest
    func runEffect() async throws -> Response {
        try JSONDecoder().decode(Response.self, from: try await URLSession.shared.data(for: request).0)
    }
}

fileprivate final class Counter: Scope, ObservableObject {
    
    @Published var viewDisplaysTotalCount: Int = 0
    @Published var viewShowsLoadingAndDisablesButtons: Bool = false
    
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
            enqueue(
                AnyEffect {
                    let request = try buildURLRequestPosting(dto: DTO(count: self.viewDisplaysTotalCount))
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        case .userTappedDecrementButton:
            guard viewDisplaysTotalCount > 0 else {
                return
            }
            viewDisplaysTotalCount = viewDisplaysTotalCount - 1
            viewShowsLoadingAndDisablesButtons = true
            /** Same enqueue pattern as in userTappedIncrementButton*/
            enqueue(
                NetworkEffect<DTO>(request: try buildURLRequestPosting(dto: DTO(count: viewDisplaysTotalCount)))
                    .map(When.networkPostCompleted)
            )
        case .networkPostCompleted(let remoteCounter):
            viewShowsLoadingAndDisablesButtons = false
            viewDisplaysTotalCount = remoteCounter.count
        }
    }
}

fileprivate struct CounterView: View {
    @ObservedObject var model = Counter()
    var body: some View {
        VStack {
            HStack {
                Text("\(model.viewDisplaysTotalCount)")
                if model.viewShowsLoadingAndDisablesButtons {
                    ProgressView()
                }
            }
            HStack {
                Button("+") {
                    model.send(.userTappedIncrementButton)
                }
                Button("-") {
                    model.send(.userTappedDecrementButton)
                }
            }
            .disabled(model.viewShowsLoadingAndDisablesButtons)
        }
    }
}

final class StatoscopeExample2: XCTestCase {
    
    func testCounterExample2UserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        
        // Increment: no effects check
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .WHEN(.networkPostCompleted(DTO(count: 1)))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        
        // Decrement: checking effects
        .WHEN(.userTappedDecrementButton)
        .THEN(\.effects.count, equals: 1)
        // Test enqued effect
        .THEN_EnquedEffect(NetworkEffect<DTO>(request: try buildURLRequestPosting(dto: DTO(count: 0))))
        // Test simgle keypaths in the enqued effects
        .THEN_EnquedEffect(\NetworkEffect<DTO>.request.url?.absoluteString, equals: "http://statoscope.com")
        .THEN_EnquedEffect(\NetworkEffect<DTO>.request.httpBody, equals: "{\"count\":0}".data(using: .utf8))
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        
        // Completion:
        .WHEN(.networkPostCompleted(DTO(count: 0)))
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .THEN(\.effects.count, equals: 0)
        .runTest()
    }
}
