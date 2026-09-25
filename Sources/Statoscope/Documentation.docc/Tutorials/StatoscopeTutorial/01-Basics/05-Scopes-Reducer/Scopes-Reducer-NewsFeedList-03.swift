@Reducer
struct NewsFeedListReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var favoritesEnabled: Bool = false
        var loading: Bool = false
        var loadedDTO: FeedListDTO?
        @SubState var readingArticle: NewsFeedArticleReducer.State?

        // No more local `favorites` copy — reads the root's canonical list directly.
        // NewsFeedListReducer implements no MiddlewareReducer at all; it doesn't need
        // to, since the root reacts to `.favorite` from this reducer's own When
        // without any relay code here (see the next type, where Article sends the
        // same event two levels further down and the root still reacts to it directly).
        @SuperState var newsFeed: NewsFeedReducer.State
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
            state.loading = true
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

        case .favorite:
            // A no-op here: this reducer no longer owns `favorites`, so its own
            // update() has nothing left to do with the event — it still runs (forwarding
            // always happens), it just does nothing. NewsFeedReducer.updateSubstate
            // reacts to it afterward. Kept here only because `When` must stay
            // exhaustive — the case itself is still what the view sends.
            break
        }
    }
}
