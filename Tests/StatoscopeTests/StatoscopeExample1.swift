//
//  StatoscopeExample1.swift
//  familymealplanTests
//
//  Created by Sergi Hernanz on 18/1/24.
//

import XCTest
import SwiftUI
@testable import Statoscope
import StatoscopeTesting

fileprivate final class Counter: Scope {
    
    // Define state member variables
    var viewDisplaysTotalCount: Int = 0
    
    // Define possible When events affecting state:
    //  ('When' naming is much better with a sentence format: subjectVerbPredicate)
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    // Scope conformance forces you to implement the update method:
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
        case .userTappedDecrementButton:
            viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
        }
    }
}

fileprivate final class CounterSUI: Scope, ObservableObject {
    
    // Define state member variables
    @Published var viewDisplaysTotalCount: Int = 0
    
    // Define possible When events affecting state:
    //  ('When' naming uses to have a sentence format: subjectVerbPredicate)
    enum When {
        case userTappedIncrementButton
        case userTappedDecrementButton
    }
    
    func update(_ when: When) throws {
        switch when {
        case .userTappedIncrementButton:
            viewDisplaysTotalCount = viewDisplaysTotalCount + 1
        case .userTappedDecrementButton:
            viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
        }
    }
}

fileprivate struct CounterView: View {
    @ObservedObject var model = CounterSUI()
    var body: some View {
        VStack {
            Text("\(model.viewDisplaysTotalCount)")
            HStack {
                Button("+") {
                    model.send(.userTappedIncrementButton)
                }
                Button("-") {
                    model.send(.userTappedDecrementButton)
                }
            }
        }
    }
}

final class StatoscopeExample1: XCTestCase {
    
    func testCounterUserFlow() throws {
        try CounterSUI.GIVEN {
            CounterSUI()
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


// Below I created a protocol, this creation may be automated?


// <GENERATED>
protocol CounterProtocol {
    var viewDisplaysTotalCount: Int { get }
}
// </GENERATED>

fileprivate enum Example1 {

    final class Counter: Scope, ObservableObject, CounterProtocol {
        
        // Define state member variables
        @Published var viewDisplaysTotalCount: Int = 0
        
        // Define possible When events affecting state:
        //  ('When' naming uses to have a sentence format: subjectVerbPredicate)
        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
        }
        
        func update(_ when: When) throws {
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount = viewDisplaysTotalCount + 1
            case .userTappedDecrementButton:
                viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
            }
        }
    }

    // <GENERATED>
    struct CounterViewModel<T: CounterProtocol & ObservableObject & Scope> where T.When == Counter.When {
        @ObservedObject var model: T
        var bod: some View {
            CounterView(model: model, send: { model.send($0) })
        }
    }
    // </GENERATED>
    
    struct CounterView: View {
        let model: CounterProtocol
        let send: (Counter.When) -> Void
        var body: some View {
            VStack {
                Text("\(model.viewDisplaysTotalCount)")
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
    
    final class StatoscopeExample1: XCTestCase {
        
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
            .configureViewSnapshot(self, { sut in
                CounterView(model: sut, send: {_ in})
            })
            .runTest()
        }
    }
}
