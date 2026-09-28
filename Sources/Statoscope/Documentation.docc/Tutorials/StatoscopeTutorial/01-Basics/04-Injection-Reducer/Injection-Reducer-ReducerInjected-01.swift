@Reducer
struct NewsFeedStatusReducer {
    struct State {
        @ReducerInjected(DateProvider.self) var date: DateProvider
        @ReducerInjected(RealNetworkProvider.self) var network: NetworkProvider

        var lastCheckedAt: Date?
    }

    enum When {
        case checkNow
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .checkNow:
            state.lastCheckedAt = state.date.currentDate()
        }
    }
}
