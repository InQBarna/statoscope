@Reducer
struct NewsFeedArticleReducer {
    struct State: Injectable {
        static var defaultValue: State { State() }
        var favoritesEnabled: Bool = false
        var id: String = ""
        var loading: Bool = false
        var loadedDTO: ArticleDTO?

        // Skips the direct parent (NewsFeedListReducer) and reads the root two levels
        // up — safe here because `favorites` is declared directly on NewsFeedReducer's
        // own State, not mirrored from somewhere else.
        @SuperState var newsFeed: NewsFeedReducer.State
    }

    enum When {
        case systemLoadedScope
        case networkDidFinish(ArticleDTO)
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
            let articleId = state.id  // Copy to avoid capturing inout parameter

            state.loading = true
            effectsState.enqueue(
                AnyEffect {
                    ArticleDTO(id: articleId, title: "Article \(articleId)", content: "Content for \(articleId)")
                }
                .map(When.networkDidFinish)
            )

        case .networkDidFinish(let dto):
            state.loading = false
            state.loadedDTO = dto

        case .favorite:
            // Same no-op as NewsFeedListReducer's own `.favorite` case above —
            // NewsFeedReducer.updateSubstate reacts to it after this runs.
            break
        }
    }
}
