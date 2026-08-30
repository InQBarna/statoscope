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
