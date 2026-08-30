@Reducer
struct NewsFeedReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var loadingFeatureToggles: Bool = true
        @SubState var atList: NewsFeedListReducer.State?
    }

    enum When {
        case systemLoadedScope
        case featureTogglesLoaded(favoritesEnabled: Bool)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .systemLoadedScope:
            state.loadingFeatureToggles = true
            // Simulate loading feature toggles
            effectsState.enqueue(
                AnyEffect { true }  // Simulate favoritesEnabled = true
                    .map { When.featureTogglesLoaded(favoritesEnabled: $0) }
            )

        case .featureTogglesLoaded(let favoritesEnabled):
            state.loadingFeatureToggles = false
            // Create child scope with feature toggle parameter
            var listState = NewsFeedListReducer.State()
            listState.favoritesEnabled = favoritesEnabled
            state.atList = listState
        }
    }
}
