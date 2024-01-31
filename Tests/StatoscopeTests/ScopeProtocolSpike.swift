//
//  File.swift
//  
//
//  Created by Sergi Hernanz on 30/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

// <GENERATED>
protocol CounterState {
    var viewDisplaysTotalCount: Int { get }
}
protocol MutableCounterState: CounterState {
    var viewDisplaysTotalCount: Int { get nonmutating set }
}
extension Counter: MutableCounterState {
    func state() -> CounterState { self }
    func mutableState() -> MutableCounterState { self }
}
struct CounterStateMock: CounterState {
    @StateVar var viewDisplaysTotalCount: Int
}
// </GENERATED>

fileprivate final class Counter: Statoscope, ObservableObject {
    
    // Define state member variables
    var viewDisplaysTotalCount: Int = 0
    
    // Define possible When events affecting state:
    //  ('When' naming is much better with a sentence format: subjectVerbPredicate)
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    // Scope conformance forces you to implement the update method:
    static func update(state: MutableCounterState, when: When, effects: EffectsHandler<When>) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount = state.viewDisplaysTotalCount + 1
        case .userTappedDecrementButton:
            state.viewDisplaysTotalCount = max(0, state.viewDisplaysTotalCount - 1)
        }
    }
}

// <LIBRARY>
/*
 */
protocol PresentedViewProtocol: View {
    associatedtype R
    associatedtype D
    var state: R { get }
    var send: (D) -> Void { get }
}
fileprivate struct StatoscopeView<V: View, S: ObservableObject & Statoscope>: View {
    @ObservedObject var model: S
    let presentedView: V
    var body: some View {
        presentedView
    }
}
extension Statoscope where Self: ObservableObject {
    fileprivate func buildPresentedView(
        @ViewBuilder builder: @escaping (State, @escaping (When) -> Void) -> some View
    ) -> some View {
        StatoscopeView(model: self, presentedView: builder(state(), { [weak self] in self?.send($0) }))
    }
}

fileprivate func buildPresentedView<S: ObservableObject & Statoscope>(
    _ statoscope: S,
    @ViewBuilder builder: @escaping (S.State, @escaping (S.When) -> Void) -> some View
) -> some View {
    StatoscopeView(model: statoscope, presentedView: builder(statoscope.state(), { [weak statoscope] in statoscope?.send($0) }))
}


// </LIBRARY>

fileprivate struct CounterPresentedView: PresentedViewProtocol {
    let state: CounterState
    let send: (Counter.When) -> Void
    var body: some View {
        VStack {
            Text("\(state.viewDisplaysTotalCount)")
            HStack {
                Button("+") {
                    send(.userTappedIncrementButton)
                }
                Button("-") {
                    send(.userTappedDecrementButton)
                }
            }
        }
    }
}

fileprivate let counterView1: some View = buildPresentedView(Counter(), builder: CounterPresentedView.init)
fileprivate let counterView2: some View = Counter().buildPresentedView(builder: CounterPresentedView.init)

final class ScopeProtocolSpike: XCTestCase {
    
    func testCounterUserFlow() throws {
        try Counter.GIVEN {
            Counter()
        }
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedIncrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 1)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .WHEN(.userTappedDecrementButton)
        .THEN(\.viewDisplaysTotalCount, equals: 0)
        .runTest()
    }
}


// <GENERATED>
protocol CounterWithEffectsState {
    var viewDisplaysTotalCount: Int { get }
    var viewShowsLoadingAndDisablesButtons: Bool { get }
}
protocol MutableCounterWithEffectsState: CounterWithEffectsState {
    var viewDisplaysTotalCount: Int { get nonmutating set }
    var viewShowsLoadingAndDisablesButtons: Bool { get nonmutating set }
}
extension CounterWithEffects: MutableCounterWithEffectsState {
    func state() -> CounterWithEffectsState { self }
    func mutableState() -> MutableCounterWithEffectsState { self }
}
struct CounterWithEffectsStateMockS: Equatable {
    var viewDisplaysTotalCount: Int
    var viewShowsLoadingAndDisablesButtons: Bool
}
struct CounterWithEffectsStateMock: MutableCounterWithEffectsState {
    @StateVar var viewDisplaysTotalCount: Int
    @StateVar var viewShowsLoadingAndDisablesButtons: Bool
}
// </GENERATED>


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

fileprivate final class CounterWithEffects: Statoscope, ObservableObject {
    
    @Published var viewDisplaysTotalCount: Int = 0
    @Published var viewShowsLoadingAndDisablesButtons: Bool = false
    
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
        case networkPostCompleted(DTO)
    }
    
    static func update(state: MutableCounterWithEffectsState, when: When, effects: EffectsHandler<When>) throws {
        switch when {
        case .userTappedIncrementButton:
            state.viewDisplaysTotalCount = state.viewDisplaysTotalCount + 1
            state.viewShowsLoadingAndDisablesButtons = true
            let request = try buildURLRequestPosting(dto: DTO(count: state.viewDisplaysTotalCount))
            effects.enqueue(
                AnyEffect {
                    let resDTO = try JSONDecoder().decode(DTO.self, from: try await URLSession.shared.data(for: request).0)
                    return When.networkPostCompleted(resDTO)
                }
            )
        case .userTappedDecrementButton:
            guard state.viewDisplaysTotalCount > 0 else {
                return
            }
            state.viewDisplaysTotalCount = state.viewDisplaysTotalCount - 1
            state.viewShowsLoadingAndDisablesButtons = true
            /** Same enqueue pattern as in userTappedIncrementButton*/
            effects.enqueue(
                NetworkEffect<DTO>(request: try buildURLRequestPosting(dto: DTO(count: state.viewDisplaysTotalCount)))
                    .map(When.networkPostCompleted)
            )
        case .networkPostCompleted(let remoteCounter):
            state.viewShowsLoadingAndDisablesButtons = false
            state.viewDisplaysTotalCount = remoteCounter.count
        }
    }
}

extension ScopeProtocolSpike {
    
    func testCounterWithEffectsUsingReducer() throws {
        try CounterWithEffects.GIVEN {
            CounterWithEffects()
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
    
    func testCounterWithEffectsReducer() throws {
        let stateMock: MutableCounterWithEffectsState =
            CounterWithEffectsStateMock(viewDisplaysTotalCount: 4, viewShowsLoadingAndDisablesButtons: true)
        let effectsSpy: EffectsHandlerSpy<CounterWithEffects.When> = EffectsHandlerSpy()
        try CounterWithEffects.update(state: stateMock, when: .userTappedDecrementButton, effects: effectsSpy)
        XCTAssertEqual(effectsSpy.effects.first as? NetworkEffect<DTO>,
                       NetworkEffect<DTO>(request: try buildURLRequestPosting(dto: DTO(count: 0))))
        XCTAssertEqual(stateMock.viewDisplaysTotalCount, 3)
    }
}
