@_spi(Internal) @testable import Statoscope

/// Tutorial 02: CloudCounter with State, When and Effects using Reducer pattern
enum Tutorial02Reducer {

    struct DTO: Codable, Equatable {
        let count: Int
    }

    @Reducer
    struct CloudCounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
            var viewShowsLoadingAndDisablesButtons: Bool = false
        }
    }
}
