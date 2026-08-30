@Reducer
struct NewsFeedArticleReducer {
    struct State {
        var id: String = ""
        var loading: Bool = false
        var loadedTitle: String?
        var isFavorite: Bool = false
    }

    enum When {
        case systemLoadedScope
        case articleLoaded(title: String)
        case favorite
    }

    static func update(
        _ when: When,
        state: inout State,
        effectsState: inout EffectsState<When>,
        dependencies: ReducerDependencies
    ) throws {
        let articleId = state.id
        switch when {
        case .systemLoadedScope:
            state.loading = true
            effectsState.enqueue(
                AnyEffect { "Article \(articleId)" }
                    .map(When.articleLoaded)
            )
        case .articleLoaded(let title):
            state.loading = false
            state.loadedTitle = title
        case .favorite:
            state.isFavorite.toggle()
        }
    }
}
