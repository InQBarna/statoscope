@_spi(Internal) @testable import Statoscope

/// Tutorial 01-01: Basic Counter with State and When using Reducer pattern
enum Tutorial01Reducer {

    @Reducer
    struct CounterReducer {
        struct State {
            var viewDisplaysTotalCount: Int = 0
        }

        enum When {
            case userTappedIncrementButton
            case userTappedDecrementButton
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
