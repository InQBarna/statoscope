import Statoscope

enum Tutorial02 {

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
        }
    }
}

import StatoscopeTesting
import XCTest

extension Tutorial02 {
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
    }
}
