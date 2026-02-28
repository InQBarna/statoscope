//
//  Tutorial01_StateAndWhen.swift
//  Statoscope
//
//  Examples from Tutorial 01: State and When
//

import Foundation
// @extract:begin StateAndWhen-Counter-01
// @extract:begin StateAndWhen-Counter-02
// @extract:begin StateAndWhen-Counter-03
// @extract:begin StateAndWhen-Counter-04
// @extract:begin StateAndWhen-Counter-05
import Statoscope
// @extract:end StateAndWhen-Counter-01

enum Tutorial0101 {
    
    final class Counter: Statostore, ObservableObject {
        
        @Published var viewDisplaysTotalCount: Int = 0
        // @extract:end StateAndWhen-Counter-02

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
        }
        // @extract:end StateAndWhen-Counter-03

        func update(_ when: When) throws {
            // @extract:end StateAndWhen-Counter-04
            switch when {
            case .userTappedIncrementButton:
                viewDisplaysTotalCount += 1
            case .userTappedDecrementButton:
                viewDisplaysTotalCount = max(0, viewDisplaysTotalCount - 1)
            }
            // @extract:begin StateAndWhen-Counter-04
        }
        // @extract:begin StateAndWhen-Counter-02
        // @extract:begin StateAndWhen-Counter-03
    }
}
// @extract:end StateAndWhen-Counter-02
// @extract:end StateAndWhen-Counter-03
// @extract:end StateAndWhen-Counter-04
// @extract:end StateAndWhen-Counter-05

// @extract:begin StateAndWhen-CounterTests-01
// @extract:begin StateAndWhen-CounterTests-02
// @extract:begin StateAndWhen-CounterTests-03
// @extract:begin StateAndWhen-CounterTests-04
import StatoscopeTesting
import XCTest

extension Tutorial0101 {
    
    final class CounterTests: XCTestCase {

        func testBasicCounterFlow() throws {
            // @extract:end StateAndWhen-CounterTests-01
            try Counter.GIVEN {
                Counter()
            }
            // @extract:end StateAndWhen-CounterTests-02
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedIncrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 1)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)
            .WHEN(.userTappedDecrementButton)
            .THEN(\.viewDisplaysTotalCount, equals: 0)  // Can't go below 0
            // @extract:end StateAndWhen-CounterTests-03
            .runTest()
            // @extract:begin StateAndWhen-CounterTests-01
            // @extract:begin StateAndWhen-CounterTests-02
            // @extract:begin StateAndWhen-CounterTests-03
        }
    }
}
// @extract:end StateAndWhen-CounterTests-01
// @extract:end StateAndWhen-CounterTests-02
// @extract:end StateAndWhen-CounterTests-03
// @extract:end StateAndWhen-CounterTests-04

