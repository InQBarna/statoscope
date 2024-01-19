//
//  StatoscopeExample3.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

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
    @Published var viewDisplaysError: String?
    @Published var viewShowsLoadingAndDisablesButtons: Bool = false
    
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(Result<DTO, Error>)
    }
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
            try triggerNetworkUpdate()
        case .userTappedDecrementButton:
            guard viewDisplaysTotalCount > 0 else {
                return
            }
            viewDisplaysTotalCount = viewDisplaysTotalCount - 1
            try triggerNetworkUpdate()
        case .networkPostCompleted(let remoteCounter):
            viewShowsLoadingAndDisablesButtons = false
            switch remoteCounter {
            case .success(let remoteCounterSuccess):
                viewDisplaysTotalCount = remoteCounterSuccess.count
            case .failure(let error):
                viewDisplaysError = error.localizedDescription
            }
        }
    }
    
    private func triggerNetworkUpdate() throws {
        viewShowsLoadingAndDisablesButtons = true
        guard let url = URL(string: "http://statoscope.com") else {
            fatalError()
        }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(DTO(count: viewDisplaysTotalCount))
        enqueue(
            NetworkEffect<DTO>(request: request)
                .mapToResult(error: { $0 })
                .map(When.networkPostCompleted)
        )
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
                if let errorMessage = model.viewDisplaysError {
                    Text(errorMessage)
                        .foregroundColor(.red)
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

final class StatoscopeExample3: XCTestCase {
    
    func testCounterExample3UserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: true)
        .FORK(.networkPostCompleted(.failure(CancellationError()))) { sut in
            try sut
                .THEN(\.viewDisplaysTotalCount, equals: 1)
                .THEN(\.viewDisplaysError, equals: "The operation couldn’t be completed. (Swift.CancellationError error 1.)")
                .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        }
        .WHEN(.networkPostCompleted(.success(DTO(count: 1))))
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .THEN(\.viewShowsLoadingAndDisablesButtons, equals: false)
        .configureViewSnapshot(self, { sut in
            CounterView(model: sut)
        })
        .runTest()
    }
}
