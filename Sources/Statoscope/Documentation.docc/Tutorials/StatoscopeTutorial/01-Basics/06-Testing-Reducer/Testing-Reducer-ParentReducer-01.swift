@Reducer
struct NewsFeedReducer {
    struct State {
        var loading: Bool = false
        var loadedArticles: [ArticleDTO]?
        @SubState var readingArticle: NewsFeedArticleReducer.State?
        var favorites: [Favorite] = []
    }

    enum When {
        case systemLoadedScope
        case networkDidFinish([ArticleDTO])
        case navigateToChild(id: String)
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
            state.loading = true
            state.favorites = try persistence.get()
            effectsState.enqueue(
                AnyEffect {
                    [
                        ArticleDTO(id: "1", title: "Article 1"),
                        ArticleDTO(id: "2", title: "Article 2")
                    ]
                }
                .map(When.networkDidFinish)
            )

        case .networkDidFinish(let articles):
            state.loading = false
            state.loadedArticles = articles

        case .navigateToChild(let id):
            var articleState = NewsFeedArticleReducer.State()
            articleState.id = id
            state.readingArticle = articleState

        case .favorite(let id):
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
}
