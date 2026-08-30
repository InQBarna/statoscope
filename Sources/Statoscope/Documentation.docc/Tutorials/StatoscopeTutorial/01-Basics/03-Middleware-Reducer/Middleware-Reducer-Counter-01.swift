@_spi(Internal) @testable import Statoscope

/// Tutorial 03: Middleware with Reducer pattern
enum Tutorial03Reducer {

    @Reducer
    struct CounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
        }

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
            case errorCase  // Will throw an error
        }

        static func update(
            _ when: When,
            state: inout State,
            effectsState: inout EffectsState<When>,
            dependencies: ReducerDependencies
        ) throws {
        }
    }
}
