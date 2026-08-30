@Reducer
struct NewsFeedListReducer {
    struct State {
        var loading: Bool = false
        var loadedArticles: [ArticleDTO]?
        var favorites: [Favorite] = []
    }

    enum When {
        case systemLoadedScope
        case networkDidFinish([ArticleDTO])
        case favorite(id: String)
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        switch when {
        case .systemLoadedScope:
            let persistence: PersistenceProvider = try dependencies.resolve()
            let network: NetworkProvider = try dependencies.resolve()

            state.loading = true
            state.loadedArticles = nil
            state.favorites = try persistence.get()
            effectsState.enqueue(
                AnyEffect {
                    try await network.fetchArticles()
                }
                .map(When.networkDidFinish)
            )

        case .networkDidFinish(let articles):
            state.loading = false
            state.loadedArticles = articles

        case .favorite(let id):
            let date: DateProvider = try dependencies.resolve()
            let persistence: PersistenceProvider = try dependencies.resolve()

            if let favIndex = state.favorites.firstIndex(where: { $0.id == id }) {
                // Remove from favorites
                state.favorites.remove(at: favIndex)
            } else {
                // Add to favorites
                state.favorites.append(Favorite(id: id, dateAdded: date.currentDate()))
            }
            try persistence.set(state.favorites)
        }
    }
}
