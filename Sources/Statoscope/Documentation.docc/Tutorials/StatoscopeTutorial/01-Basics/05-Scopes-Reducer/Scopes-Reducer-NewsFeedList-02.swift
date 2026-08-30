@Reducer
struct NewsFeedListReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var favoritesEnabled: Bool = false
        var loading: Bool = false
        var loadedDTO: FeedListDTO?
        @SubState var readingArticle: NewsFeedArticleReducer.State?
        var favorites: [Favorite] = []
    }

    enum When {
        case systemLoadedScope
        case networkListDidFinish(FeedListDTO)
        case navigateFromListToChild(id: String)
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
                    FeedListDTO(articles: [
                        ArticleDTO(id: "1", title: "Article 1", content: "Content 1"),
                        ArticleDTO(id: "2", title: "Article 2", content: "Content 2")
                    ])
                }
                .map(When.networkListDidFinish)
            )

        case .networkListDidFinish(let dto):
            state.loading = false
            state.loadedDTO = dto

        case .navigateFromListToChild(let id):
            // Create child article scope
            var articleState = NewsFeedArticleReducer.State()
            articleState.favoritesEnabled = state.favoritesEnabled
            articleState.id = id
            state.readingArticle = articleState

        case .favorite(let id):
            guard state.favoritesEnabled else { return }

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
