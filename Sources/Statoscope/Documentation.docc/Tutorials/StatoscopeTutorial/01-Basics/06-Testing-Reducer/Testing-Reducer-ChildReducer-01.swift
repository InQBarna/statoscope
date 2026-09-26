/// A real, *named* effect — deliberately not the `AnyEffect { ... }` closure shorthand.
/// `WHEN_EffectCompletes` (see below) needs to look an effect up by its own type, and a bare
/// closure has no nameable type of its own: every `AnyEffect { ... }.map(...)` with the same
/// `ResultType` is indistinguishable from any other. Reach for a named `Effect` conformance
/// whenever a test needs to target one specifically.
struct FetchArticleTitleEffect: Effect {
    let articleId: String
    func runEffect() async throws -> String {
        "Article \(articleId)"
    }
}

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
                FetchArticleTitleEffect(articleId: articleId)
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
