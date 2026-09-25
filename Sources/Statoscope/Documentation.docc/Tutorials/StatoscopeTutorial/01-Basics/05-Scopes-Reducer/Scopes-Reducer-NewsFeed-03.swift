@Reducer
struct NewsFeedReducer: MiddlewareReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var loadingFeatureToggles: Bool = true
        var favorites: [Favorite] = []
        @SubState var atList: NewsFeedListReducer.State?
    }

    enum When {
        case systemLoadedScope
        case featureTogglesLoaded(favoritesEnabled: Bool)
        case toggleFavorite(id: String)
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
            // The root is now the single owner of `favorites` — load it once here,
            // instead of every child loading its own copy on its own systemLoadedScope.
            let persistence: PersistenceProvider = try dependencies.resolve()
            state.favorites = try persistence.get()
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

        case .toggleFavorite(let id):
            let date: DateProvider = try dependencies.resolve()
            let persistence: PersistenceProvider = try dependencies.resolve()

            if let favIndex = state.favorites.firstIndex(where: { $0.id == id }) {
                state.favorites.remove(at: favIndex)
            } else {
                state.favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
            }
            try persistence.set(state.favorites)
        }
    }

    // Both NewsFeedListReducer and NewsFeedArticleReducer send `.favorite(id:)` — this
    // single updateSubstate catches it from either one, no matter how deep in the tree
    // it was sent.
    static func updateSubstate<Child: Reducer>(
        _ childType: Child.Type,
        childState: Child.State,
        childWhen: Child.When,
        parentState: State,
        dependencies: ReducerDependencies
    ) throws -> When? {
        if let listWhen = childWhen as? NewsFeedListReducer.When,
           case .favorite(let id) = listWhen {
            return .toggleFavorite(id: id)
        }
        if let articleWhen = childWhen as? NewsFeedArticleReducer.When,
           case .favorite(let id) = articleWhen {
            return .toggleFavorite(id: id)
        }
        return nil
    }
}
